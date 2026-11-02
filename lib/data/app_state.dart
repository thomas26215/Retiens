import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/dates.dart';
import '../logic/scheduler.dart';
import '../models/subject.dart';
import '../models/topic.dart';
import '../services/fx.dart';
import '../services/notifications.dart';
import 'sync_merge.dart';

int _seq = 0;

String _newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${(_seq++).toRadixString(36)}';

/// État d'un sujet avant une action, pour pouvoir l'annuler.
class TopicSnapshot {
  TopicSnapshot.of(Topic t)
      : reviewCount = t.reviewCount,
        interval = t.interval,
        ease = t.ease,
        due = t.due,
        studiedOn = t.studiedOn,
        history = List.of(t.history);

  final int reviewCount;
  final int interval;
  final double ease;
  final DateTime? due;
  final DateTime studiedOn;
  final List<Review> history;
}

/// Une révision prévue un jour donné (planning).
class PlannedReview {
  const PlannedReview(this.topic, this.number, {required this.isNext});

  final Topic topic;

  /// Numéro de la révision depuis l'étude (1 pour la première).
  final int number;

  /// Vrai pour le prochain rappel du sujet, faux pour les suivants (estimés).
  final bool isNext;
}

/// Contenu d'une sauvegarde, pour confirmation avant restauration.
typedef BackupSummary = ({int subjects, int topics});

/// État de l'application : matières, sujets à réviser, historique, réglages.
/// Persisté en JSON dans shared_preferences.
class AppState extends ChangeNotifier {
  AppState._(this._prefs);

  static const _storageKey = 'retiens_topics_v1';

  final SharedPreferences _prefs;

  final List<Subject> subjects = [];
  final List<Topic> topics = [];

  /// Nombre de révisions faites par jour sur cet appareil (clé `yyyy-MM-dd`).
  /// Peut être négatif un jour donné si l'on annule ici une révision faite
  /// sur un autre appareil.
  final Map<String, int> log = {};

  /// Révisions comptées par les autres appareils du compte (même format).
  final Map<String, Map<String, int>> otherLogs = {};

  /// Éléments supprimés (id → date en ms), pour propager les suppressions.
  final Map<String, int> deleted = {};

  /// Date du dernier changement de rythme (ms), pour la synchronisation.
  int paceAt = 0;

  /// Identifiant de cet appareil : chacun tient son propre compteur.
  late final String deviceId = _loadDeviceId();

  /// Appelé après chaque modification locale (synchronisation du compte).
  /// [authoritative] : l'état local doit remplacer celui du compte
  /// (restauration d'une sauvegarde, remise à zéro).
  void Function({required bool authoritative})? onLocalChange;

  bool _authoritativeNext = false;

  /// Contenu de chaque élément au dernier enregistrement, pour repérer ce qui
  /// a changé (date de modification) ou disparu (suppression).
  final Map<String, String> _fingerprints = {};

  bool reminderEnabled = false;
  int reminderHour = 19;
  int reminderMinute = 0;
  String paceKey = 'normal';
  ThemeMode themeMode = ThemeMode.system;
  bool soundOn = true;
  bool hapticsOn = true;

  Future<void> _reminderChain = Future<void>.value();

  static Future<AppState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final state = AppState._(prefs);
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        state._fromJson(jsonDecode(raw) as Map<String, dynamic>);
        state._resetFingerprints();
      } catch (e) {
        // Données illisibles : on garde une copie plutôt que de les écraser.
        await prefs.setString('${_storageKey}_corrupt', raw);
        debugPrint('Données illisibles, copie conservée : $e');
      }
    }
    return state;
  }

  // --- Lecture -------------------------------------------------------------

  DateTime get today => dateOnly(DateTime.now());

  Pace get pace => paceByKey(paceKey);

  Subject? subjectById(String id) {
    for (final s in subjects) {
      if (s.id == id) return s;
    }
    return null;
  }

  Topic? topicById(String id) {
    for (final t in topics) {
      if (t.id == id) return t;
    }
    return null;
  }

  int _byDue(Topic a, Topic b) {
    final c = a.due!.compareTo(b.due!);
    return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
  }

  bool isDue(Topic t) => t.due != null && !t.due!.isAfter(today);

  /// Sujets à réviser aujourd'hui ou en retard.
  List<Topic> dueTopics({String? subjectId}) {
    final list = topics
        .where((x) =>
            isDue(x) && (subjectId == null || x.subjectId == subjectId))
        .toList()
      ..sort(_byDue);
    return list;
  }

  int dueCount({String? subjectId}) => dueTopics(subjectId: subjectId).length;

  /// Prochains rappels (après aujourd'hui).
  List<Topic> upcoming({int limit = 8}) {
    final t = today;
    final list = topics.where((x) => x.due != null && x.due!.isAfter(t)).toList()
      ..sort(_byDue);
    return list.take(limit).toList();
  }

  /// Sujets dont la dernière révision date d'aujourd'hui.
  List<Topic> get topicsReviewedToday {
    final t = today;
    return topics.where((x) => x.lastReviewed == t).toList();
  }

  /// Sujets d'une matière : à réviser d'abord, terminés en dernier.
  List<Topic> topicsOf(String subjectId) {
    final list = topics.where((x) => x.subjectId == subjectId).toList()
      ..sort((a, b) {
        if (a.due == null && b.due == null) {
          return a.createdAt.compareTo(b.createdAt);
        }
        if (a.due == null) return 1;
        if (b.due == null) return -1;
        return _byDue(a, b);
      });
    return list;
  }

  DateTime? examOf(Topic t) => subjectById(t.subjectId)?.examDate;

  /// Matières dont l'examen est aujourd'hui ou plus tard, la plus proche d'abord.
  List<Subject> get upcomingExams {
    final t = today;
    return subjects
        .where((s) => s.examDate != null && !s.examDate!.isBefore(t))
        .toList()
      ..sort((a, b) => a.examDate!.compareTo(b.examDate!));
  }

  // --- Planification -------------------------------------------------------

  Map<Rating, Outcome> _outcomesFor(Topic t) {
    final from = t.lastReviewed ?? t.studiedOn;
    return outcomes(
      interval: t.interval,
      ease: t.ease,
      elapsed: daysBetween(from, today),
      pace: pace.factor,
    );
  }

  DateTime? _dueAfter(Topic t, int interval) => capToExam(
        addDays(today, interval),
        today: today,
        earliest: addDays(today, 1),
        examDate: examOf(t),
      );

  /// Prochain rappel selon la note donnée aujourd'hui (`null` : plus aucun,
  /// l'examen est trop proche).
  Map<Rating, DateTime?> previewDue(Topic t) => {
        for (final e in _outcomesFor(t).entries) e.key: _dueAfter(t, e.value.interval),
      };

  /// Rappels restants d'un sujet, en supposant chaque révision notée « Bien ».
  List<DateTime> remainingDates(Topic t, {int limit = 8}) => projectedDates(
        due: t.due,
        interval: t.interval,
        ease: t.ease,
        today: today,
        examDate: examOf(t),
        pace: pace.factor,
        limit: limit,
      );

  // --- Progression ---------------------------------------------------------

  /// Maîtrise d'une matière, de 0 à 1 : solidité moyenne de ses sujets.
  double subjectMastery(String subjectId) =>
      masteryOf(topics.where((x) => x.subjectId == subjectId));

  /// Maîtrise d'un ensemble de sujets (un chapitre…), de 0 à 1.
  static double masteryOf(Iterable<Topic> list) {
    if (list.isEmpty) return 0;
    final sum = list.fold<int>(0, (n, t) => n + t.memory);
    return sum / (list.length * (memoryLabels.length - 1));
  }

  /// Sujets au souvenir solide (au moins 3 semaines d'intervalle).
  int get solidCount => topics.where((t) => t.memory >= 4).length;

  /// Révisions du jour [key], tous appareils confondus.
  int _count(String key) {
    var n = log[key] ?? 0;
    for (final m in otherLogs.values) {
      n += m[key] ?? 0;
    }
    return n;
  }

  Set<String> get _logDays => {
        ...log.keys,
        for (final m in otherLogs.values) ...m.keys,
      };

  int get reviewedToday => reviewsOn(today);

  int reviewsOn(DateTime day) => math.max(0, _count(dateKey(day)));

  int get totalReviews =>
      _logDays.fold(0, (a, k) => a + math.max(0, _count(k)));

  /// Révisions faites entre [from] et [to] inclus.
  int reviewsBetween(DateTime from, DateTime to) {
    var n = 0;
    for (var d = dateOnly(from); !d.isAfter(to); d = addDays(d, 1)) {
      n += reviewsOn(d);
    }
    return n;
  }

  /// Nombre de révisions par note entre [from] et [to] inclus.
  Map<Rating, int> ratingsBetween(DateTime from, DateTime to) {
    final out = {for (final r in Rating.values) r: 0};
    for (final t in topics) {
      for (final r in t.history) {
        if (r.rating == null || r.day.isBefore(from) || r.day.isAfter(to)) {
          continue;
        }
        out[r.rating!] = out[r.rating!]! + 1;
      }
    }
    return out;
  }

  /// Jours consécutifs avec au moins une révision (aujourd'hui compris s'il y en a).
  int get streak {
    var day = today;
    if (_count(dateKey(day)) <= 0) day = addDays(day, -1);
    var n = 0;
    while (_count(dateKey(day)) > 0) {
      n++;
      day = addDays(day, -1);
    }
    return n;
  }

  /// Plus longue série de jours consécutifs avec au moins une révision.
  int get bestStreak {
    final days = _logDays
        .where((k) => _count(k) > 0)
        .map(DateTime.parse)
        .toList()
      ..sort();
    var best = 0;
    var run = 0;
    DateTime? prev;
    for (final d in days) {
      run = prev != null && daysBetween(prev, d) == 1 ? run + 1 : 1;
      if (run > best) best = run;
      prev = d;
    }
    return best;
  }

  // --- Planning ------------------------------------------------------------

  /// Révisions prévues entre [from] et [to] inclus, regroupées par jour.
  /// Les sujets en retard comptent pour aujourd'hui ; les rappels après le
  /// prochain supposent des révisions notées « Bien ».
  Map<DateTime, List<PlannedReview>> plannedBetween(DateTime from, DateTime to) {
    final out = <DateTime, List<PlannedReview>>{};
    for (final t in topics) {
      final dates = remainingDates(t, limit: 12);
      for (var i = 0; i < dates.length; i++) {
        final d = dates[i];
        if (d.isBefore(from)) continue;
        if (d.isAfter(to)) break;
        out
            .putIfAbsent(d, () => [])
            .add(PlannedReview(t, t.reviewCount + i + 1, isNext: i == 0));
      }
    }
    for (final list in out.values) {
      list.sort((a, b) => a.topic.createdAt.compareTo(b.topic.createdAt));
    }
    return out;
  }

  /// Révisions faites le jour [day], avec leur sujet.
  List<(Topic, Review)> reviewedOn(DateTime day) {
    final d = dateOnly(day);
    return [
      for (final t in topics)
        for (final r in t.history)
          if (r.day == d) (t, r),
    ];
  }

  // --- Matières ------------------------------------------------------------

  /// Première couleur de la palette pas encore utilisée.
  int nextSubjectColor() {
    final used = subjects.map((s) => s.colorValue).toSet();
    return subjectPalette.firstWhere(
      (c) => !used.contains(c),
      orElse: () => subjectPalette[subjects.length % subjectPalette.length],
    );
  }

  Subject addSubject(String name, int colorValue, DateTime? examDate) {
    final s = Subject(
      id: _newId(),
      name: name,
      colorValue: colorValue,
      examDate: examDate == null ? null : dateOnly(examDate),
    );
    subjects.add(s);
    _commit();
    return s;
  }

  void updateSubject(
    Subject s, {
    required String name,
    required int colorValue,
    required DateTime? examDate,
  }) {
    final exam = examDate == null ? null : dateOnly(examDate);
    final examChanged = s.examDate != exam;
    s.name = name;
    s.colorValue = colorValue;
    s.examDate = exam;
    if (examChanged) {
      for (final t in topics.where((x) => x.subjectId == s.id)) {
        _reschedule(t);
      }
    }
    _commit();
  }

  void deleteSubject(String id) {
    subjects.removeWhere((s) => s.id == id);
    topics.removeWhere((t) => t.subjectId == id);
    _commit();
  }

  // --- Sujets à réviser ----------------------------------------------------

  /// Recalcule le prochain rappel après un changement de date d'étude ou
  /// d'examen, sans tenir compte d'un éventuel report.
  void _reschedule(Topic t) {
    final exam = examOf(t);
    if (t.reviewCount == 0) {
      t.due = firstDue(studiedOn: t.studiedOn, today: today, examDate: exam);
      return;
    }
    var d = addDays(t.lastReviewed ?? t.studiedOn, t.interval);
    if (d.isBefore(today)) d = today;
    t.due = capToExam(d, today: today, earliest: today, examDate: exam);
  }

  Topic addTopic({
    required String subjectId,
    required String title,
    required DateTime studiedOn,
    String note = '',
    String? chapterId,
  }) {
    final t = Topic(
      id: _newId(),
      subjectId: subjectId,
      title: title,
      note: note,
      chapterId: subjectById(subjectId)?.chapterById(chapterId)?.id,
      studiedOn: dateOnly(studiedOn),
    );
    topics.add(t);
    _reschedule(t);
    _commit();
    return t;
  }

  void updateTopic(
    Topic t, {
    required String subjectId,
    required String title,
    required String note,
    required DateTime studiedOn,
    String? chapterId,
  }) {
    final scheduleChanged =
        t.subjectId != subjectId || t.studiedOn != dateOnly(studiedOn);
    t.subjectId = subjectId;
    t.title = title;
    t.note = note;
    // Un chapitre d'une autre matière ne compte pas.
    t.chapterId = subjectById(subjectId)?.chapterById(chapterId)?.id;
    t.studiedOn = dateOnly(studiedOn);
    if (scheduleChanged && t.due != null) _reschedule(t);
    _commit();
  }

  // --- Chapitres ------------------------------------------------------------

  /// Chapitre d'un sujet, ou `null` pour « Autre » (pas de chapitre, ou
  /// chapitre supprimé sur un autre appareil).
  Chapter? chapterOf(Topic t) =>
      subjectById(t.subjectId)?.chapterById(t.chapterId);

  Chapter addChapter(Subject s, String name) {
    final c = Chapter(id: _newId(), name: name);
    s.chapters.add(c);
    _commit();
    return c;
  }

  void renameChapter(Subject s, Chapter c, String name) {
    c.name = name;
    _commit();
  }

  /// Monte ([delta] < 0) ou descend le chapitre dans la liste.
  void moveChapter(Subject s, Chapter c, int delta) {
    final i = s.chapters.indexOf(c);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= s.chapters.length) return;
    s.chapters
      ..removeAt(i)
      ..insert(j, c);
    _commit();
  }

  /// Supprime le chapitre ; ses sujets passent dans « Autre ».
  void deleteChapter(Subject s, Chapter c) {
    s.chapters.remove(c);
    for (final t in topics) {
      if (t.subjectId == s.id && t.chapterId == c.id) t.chapterId = null;
    }
    _commit();
  }

  /// Range un sujet dans un chapitre de sa matière (`null` : « Autre »).
  void moveTopicToChapter(Topic t, String? chapterId) {
    t.chapterId = subjectById(t.subjectId)?.chapterById(chapterId)?.id;
    _commit();
  }

  void deleteTopic(String id) {
    topics.removeWhere((t) => t.id == id);
    _commit();
  }

  /// Révision faite et notée : le prochain rappel s'éloigne d'autant plus
  /// que la révision s'est bien passée.
  TopicSnapshot review(Topic t, Rating rating) {
    final snap = TopicSnapshot.of(t);
    final outcome = _outcomesFor(t)[rating]!;
    final day = today;
    final before = PriorState(interval: t.interval, ease: t.ease, due: t.due);
    t.reviewCount += 1;
    t.interval = outcome.interval;
    t.ease = outcome.ease;
    t.history.add(Review(day, rating, before));
    t.due = _dueAfter(t, outcome.interval);
    final key = dateKey(day);
    log[key] = (log[key] ?? 0) + 1;
    _commit();
    return snap;
  }

  /// La dernière révision peut être annulée tant qu'elle appartient au cycle
  /// en cours (pas à travers un « Réétudié aujourd'hui »).
  bool canUndoLastReview(Topic t) =>
      t.reviewCount > 0 &&
      t.history.isNotEmpty &&
      !t.history.last.day.isBefore(t.studiedOn);

  /// État du sujet avant sa dernière révision : enregistré pour les
  /// révisions récentes, estimé pour celles faites avant cet enregistrement
  /// (intervalle = écart avec la révision précédente, rappel = jour revu).
  PriorState _stateBefore(Topic t) {
    final last = t.history.last;
    final saved = last.before;
    if (saved != null) return saved;
    final n = t.history.length;
    final int interval;
    if (t.reviewCount <= 1) {
      interval = 0;
    } else {
      final previous = n > 1 ? t.history[n - 2].day : t.studiedOn;
      interval = daysBetween(previous, last.day).clamp(1, maxInterval);
    }
    final rating = last.rating;
    return PriorState(
      interval: interval,
      ease: rating == null ? t.ease : clampEase(t.ease - easeChange[rating]!),
      due: last.day,
    );
  }

  /// Annule la dernière révision du sujet : il retrouve l'intervalle, la
  /// facilité et le rappel d'avant (de nouveau à revoir, en général).
  /// `null` s'il n'y a rien à annuler.
  TopicSnapshot? undoLastReview(Topic t) {
    if (!canUndoLastReview(t)) return null;
    final snap = TopicSnapshot.of(t);
    final before = _stateBefore(t);
    t.history.removeLast();
    t.reviewCount -= 1;
    t.interval = before.interval;
    t.ease = before.ease;
    final due = before.due;
    t.due = due == null
        ? null
        : capToExam(due, today: today, earliest: today, examDate: examOf(t));
    _syncLog(snap.history, t.history);
    _commit();
    return snap;
  }

  /// Pas le temps aujourd'hui : rappel demain, sans changer l'intervalle.
  TopicSnapshot postpone(Topic t) {
    final snap = TopicSnapshot.of(t);
    t.due = addDays(today, 1);
    _commit();
    return snap;
  }

  /// Le sujet a été réétudié aujourd'hui : le cycle de rappels recommence
  /// (la facilité apprise est conservée).
  TopicSnapshot restart(Topic t) {
    final snap = TopicSnapshot.of(t);
    t.studiedOn = today;
    t.reviewCount = 0;
    t.interval = 0;
    _reschedule(t);
    _commit();
    return snap;
  }

  /// Plus de rappel pour ce sujet.
  TopicSnapshot stop(Topic t) {
    final snap = TopicSnapshot.of(t);
    t.due = null;
    _commit();
    return snap;
  }

  /// Reprend les rappels d'un sujet arrêté. Faux si l'examen est passé.
  bool resume(Topic t) {
    _reschedule(t);
    _commit();
    return t.due != null;
  }

  /// Remet le sujet dans l'état [s] (annulation d'une action).
  void restore(Topic t, TopicSnapshot s) {
    final current = List.of(t.history);
    t.reviewCount = s.reviewCount;
    t.interval = s.interval;
    t.ease = s.ease;
    t.due = s.due;
    t.studiedOn = s.studiedOn;
    t.history
      ..clear()
      ..addAll(s.history);
    _syncLog(current, t.history);
    _commit();
  }

  /// Met à jour le nombre de révisions par jour quand l'historique d'un sujet
  /// passe de [before] à [after].
  void _syncLog(List<Review> before, List<Review> after) {
    final delta = <String, int>{};
    for (final r in after) {
      final k = dateKey(r.day);
      delta[k] = (delta[k] ?? 0) + 1;
    }
    for (final r in before) {
      final k = dateKey(r.day);
      delta[k] = (delta[k] ?? 0) - 1;
    }
    delta.forEach((k, d) {
      if (d == 0) return;
      final n = (log[k] ?? 0) + d;
      if (n != 0) {
        log[k] = n;
      } else {
        log.remove(k);
      }
    });
  }

  // --- Réglages ------------------------------------------------------------

  Future<void> setReminder({bool? enabled, int? hour, int? minute}) {
    if (enabled != null) reminderEnabled = enabled;
    if (hour != null) reminderHour = hour;
    if (minute != null) reminderMinute = minute;
    _commit();
    return _reminderChain;
  }

  /// Le nouveau rythme s'applique à la prochaine révision de chaque sujet.
  void setPace(String key) {
    paceKey = paceByKey(key).key;
    paceAt = DateTime.now().millisecondsSinceEpoch;
    _commit();
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    _commit();
  }

  void setSound(bool on) {
    soundOn = Fx.instance.sound = on;
    _commit();
  }

  void setHaptics(bool on) {
    hapticsOn = Fx.instance.haptics = on;
    _commit();
  }

  Future<void> resetAll() {
    subjects.clear();
    topics.clear();
    log.clear();
    otherLogs.clear();
    reminderEnabled = false;
    _authoritativeNext = true;
    _commit();
    return _reminderChain;
  }

  /// À appeler quand la date a pu changer (retour dans l'app, minuit).
  void refresh() {
    notifyListeners();
    unawaited(applyReminders());
  }

  // --- Sauvegarde ----------------------------------------------------------

  String exportJson() => const JsonEncoder.withIndent(' ').convert({
        'app': 'retiens',
        'exportedAt': DateTime.now().toIso8601String(),
        ..._toJson(forExport: true),
      });

  /// Lit une sauvegarde sans l'appliquer. `null` si elle est illisible.
  BackupSummary? inspectBackup(String raw) {
    final parsed = _parseBackup(raw);
    if (parsed == null) return null;
    final summary = (
      subjects: parsed.subjects.length,
      topics: parsed.topics.length,
    );
    parsed.dispose();
    return summary;
  }

  /// Remplace toutes les données par la sauvegarde [raw]. Les données
  /// actuelles sont gardées de côté au cas où. Renvoie faux si illisible.
  Future<bool> importJson(String raw) async {
    final parsed = _parseBackup(raw);
    if (parsed == null) return false;
    parsed.dispose();
    await _prefs.setString(
      '${_storageKey}_before_import',
      jsonEncode(_toJson()),
    );
    _fromJson(jsonDecode(raw.trim()) as Map<String, dynamic>);
    _authoritativeNext = true;
    _commit();
    return true;
  }

  AppState? _parseBackup(String raw) {
    try {
      final j = jsonDecode(raw.trim());
      if (j is! Map<String, dynamic> || j['topics'] is! List) return null;
      return AppState._(_prefs).._fromJson(j);
    } catch (_) {
      return null;
    }
  }

  // --- Notifications -------------------------------------------------------

  /// Reprogramme toutes les notifications. Les appels sont exécutés l'un après
  /// l'autre pour éviter que deux synchronisations ne se chevauchent.
  Future<void> applyReminders() {
    _reminderChain = _reminderChain.then((_) => _syncReminders()).catchError(
      (Object e) {
        debugPrint('Synchronisation des rappels : $e');
      },
    );
    return _reminderChain;
  }

  Future<void> _syncReminders() async {
    final service = NotificationService.instance;
    await service.cancelAll();
    if (!reminderEnabled) return;

    final now = DateTime.now();
    final t = today;
    final timeToday =
        DateTime(t.year, t.month, t.day, reminderHour, reminderMinute);

    // Une notification par jour : les sujets en retard sont rappelés au
    // prochain créneau disponible.
    final byDay = <DateTime, List<Topic>>{};
    for (final topic in topics) {
      final due = topic.due;
      if (due == null) continue;
      var day = due.isBefore(t) ? t : due;
      if (day == t && !timeToday.isAfter(now)) day = addDays(t, 1);
      byDay.putIfAbsent(day, () => []).add(topic);
    }

    final days = byDay.keys.toList()..sort();
    var id = 1;
    // iOS plafonne à 64 notifications programmées.
    for (final day in days.take(60)) {
      final list = byDay[day]!;
      final n = list.length;
      final names = list.take(3).map((x) => x.title).join(', ');
      final more = n > 3 ? ' et ${n - 3} autre${n - 3 > 1 ? 's' : ''}' : '';
      await service.scheduleOnce(
        id: id++,
        day: day,
        hour: reminderHour,
        minute: reminderMinute,
        title: n == 1 ? '1 sujet à revoir' : '$n sujets à revoir',
        body: '$names$more',
      );
    }
  }

  // --- Persistance ---------------------------------------------------------

  void _commit() {
    _stampChanges();
    notifyListeners();
    _save();
    unawaited(applyReminders());
    final authoritative = _authoritativeNext;
    _authoritativeNext = false;
    onLocalChange?.call(authoritative: authoritative);
  }

  void _save() =>
      unawaited(_prefs.setString(_storageKey, jsonEncode(_toJson())));

  /// Date de modification des éléments changés, suppression des disparus.
  void _stampChanges() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final seen = <String>{};
    void check(String id, Map<String, dynamic> json, void Function() touch) {
      seen.add(id);
      json.remove('u');
      final fp = jsonEncode(json);
      if (_fingerprints[id] == fp) return;
      _fingerprints[id] = fp;
      touch();
      deleted.remove(id);
    }

    for (final s in subjects) {
      check(s.id, s.toJson(), () => s.updatedAt = now);
    }
    for (final t in topics) {
      check(t.id, t.toJson(), () => t.updatedAt = now);
    }
    final gone = _fingerprints.keys.where((id) => !seen.contains(id)).toList();
    for (final id in gone) {
      _fingerprints.remove(id);
      deleted[id] = now;
    }
  }

  void _resetFingerprints() {
    _fingerprints.clear();
    for (final s in subjects) {
      _fingerprints[s.id] = jsonEncode(s.toJson()..remove('u'));
    }
    for (final t in topics) {
      _fingerprints[t.id] = jsonEncode(t.toJson()..remove('u'));
    }
  }

  String _loadDeviceId() {
    const key = 'retiens_device_id';
    final known = _prefs.getString(key);
    if (known != null) return known;
    final rnd = math.Random.secure();
    final id = List.generate(12, (_) => rnd.nextInt(36).toRadixString(36)).join();
    unawaited(_prefs.setString(key, id));
    return id;
  }

  // --- Synchronisation du compte -------------------------------------------

  /// État à synchroniser (voir [mergeCloud]). Les réglages propres à
  /// l'appareil (rappels, thème, sons) n'en font pas partie.
  CloudState toCloud() => {
        'subjects': {for (final s in subjects) s.id: s.toJson()},
        'topics': {for (final t in topics) t.id: t.toJson()},
        'deleted': Map<String, dynamic>.of(deleted),
        'logs': {
          for (final e in otherLogs.entries)
            if (e.key != deviceId) e.key: Map<String, dynamic>.of(e.value),
          if (log.isNotEmpty) deviceId: Map<String, dynamic>.of(log),
        },
        'pace': paceKey,
        'paceAt': paceAt,
      };

  /// Remplace les données synchronisées par [c] (issu d'une fusion). Le
  /// compteur de cet appareil reste celui de l'appareil.
  void applyCloud(CloudState c) {
    List<T> ordered<T>(
      List<T> current,
      String Function(T) idOf,
      Map<String, dynamic> incoming,
      T Function(Map<String, dynamic>) parse,
    ) {
      // Ordre conservé pour les éléments connus, nouveaux à la fin.
      final known = [for (final x in current) idOf(x)];
      final ids = [
        ...known.where(incoming.containsKey),
        ...(incoming.keys.where((id) => !known.contains(id)).toList()..sort()),
      ];
      return [
        for (final id in ids) parse(Map<String, dynamic>.from(incoming[id] as Map)),
      ];
    }

    final s = ordered(subjects, (x) => x.id, _asMap(c['subjects']), Subject.fromJson);
    final t = ordered(topics, (x) => x.id, _asMap(c['topics']), Topic.fromJson);
    subjects
      ..clear()
      ..addAll(s);
    topics
      ..clear()
      ..addAll(t);
    deleted
      ..clear()
      ..addAll(_asMap(c['deleted']).map((k, v) => MapEntry(k, (v as num).toInt())));
    otherLogs.clear();
    _asMap(c['logs']).forEach((device, m) {
      if (device == deviceId) return;
      otherLogs[device] =
          _asMap(m).map((k, v) => MapEntry(k, (v as num).toInt()));
    });
    final pace = c['pace'] as String?;
    if (pace != null) paceKey = paceByKey(pace).key;
    paceAt = (c['paceAt'] as num?)?.toInt() ?? paceAt;
    _resetFingerprints();
    notifyListeners();
    _save();
    unawaited(applyReminders());
  }

  static Map<String, dynamic> _asMap(Object? v) =>
      v is Map ? v.map((k, v) => MapEntry('$k', v)) : <String, dynamic>{};

  /// Révisions par jour, tous appareils confondus (pour les sauvegardes).
  Map<String, int> _totalLog() => {
        for (final k in _logDays)
          if (_count(k) != 0) k: _count(k),
      };

  Map<String, dynamic> _toJson({bool forExport = false}) => {
        'subjects': subjects.map((s) => s.toJson()).toList(),
        'topics': topics.map((t) => t.toJson()).toList(),
        'log': forExport ? _totalLog() : log,
        if (!forExport) 'otherLogs': otherLogs,
        if (!forExport) 'deleted': deleted,
        'paceAt': paceAt,
        'reminderEnabled': reminderEnabled,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
        'pace': paceKey,
        'theme': themeMode.name,
        'sound': soundOn,
        'haptics': hapticsOn,
      };

  // Anciens rythmes fixes → rythme général équivalent.
  static const _paceFromRhythm = {
    'intensif': 'soutenu',
    'leger': 'detendu',
  };

  void _fromJson(Map<String, dynamic> j) {
    subjects
      ..clear()
      ..addAll((j['subjects'] as List? ?? [])
          .map((e) => Subject.fromJson(e as Map<String, dynamic>)));
    topics
      ..clear()
      ..addAll((j['topics'] as List? ?? [])
          .map((e) => Topic.fromJson(e as Map<String, dynamic>)));
    log
      ..clear()
      ..addAll((j['log'] as Map? ?? {})
          .map((k, v) => MapEntry(k as String, (v as num).toInt())));
    otherLogs.clear();
    _asMap(j['otherLogs']).forEach((device, m) {
      otherLogs[device] =
          _asMap(m).map((k, v) => MapEntry(k, (v as num).toInt()));
    });
    deleted
      ..clear()
      ..addAll(_asMap(j['deleted']).map((k, v) => MapEntry(k, (v as num).toInt())));
    paceAt = (j['paceAt'] as num?)?.toInt() ?? 0;
    reminderEnabled = j['reminderEnabled'] as bool? ?? false;
    reminderHour = (j['reminderHour'] as num?)?.toInt() ?? 19;
    reminderMinute = (j['reminderMinute'] as num?)?.toInt() ?? 0;
    final pace = j['pace'] as String? ??
        _paceFromRhythm[j['rhythm'] as String? ?? ''] ??
        'normal';
    paceKey = paceByKey(pace).key;
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == j['theme'],
      orElse: () => ThemeMode.system,
    );
    soundOn = j['sound'] as bool? ?? true;
    hapticsOn = j['haptics'] as bool? ?? true;
  }

  /// Applique les réglages de sons et vibrations (au démarrage).
  void applyFeedbackSettings() {
    Fx.instance
      ..sound = soundOn
      ..haptics = hapticsOn;
  }
}
