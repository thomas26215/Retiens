import '../logic/dates.dart';
import '../logic/scheduler.dart';

/// État d'un sujet juste avant une révision, pour pouvoir l'annuler.
class PriorState {
  const PriorState({required this.interval, required this.ease, this.due});

  final int interval;
  final double ease;
  final DateTime? due;

  Map<String, dynamic> toJson() => {
        'i': interval,
        'e': ease,
        'd': due == null ? null : dateKey(due!),
      };

  factory PriorState.fromJson(Map<String, dynamic> j) => PriorState(
        interval: (j['i'] as num).toInt(),
        ease: (j['e'] as num).toDouble(),
        due: j['d'] == null ? null : DateTime.parse(j['d'] as String),
      );
}

/// Une révision faite : le jour, la note et l'état d'avant. La note et l'état
/// d'avant manquent dans les anciennes données.
class Review {
  const Review(this.day, [this.rating, this.before]);

  final DateTime day;
  final Rating? rating;
  final PriorState? before;

  Object toJson() => rating == null && before == null
      ? dateKey(day)
      : {
          'd': dateKey(day),
          if (rating != null) 'r': rating!.name,
          if (before != null) 'p': before!.toJson(),
        };

  factory Review.fromJson(Object j) {
    if (j is String) return Review(DateTime.parse(j));
    final m = j as Map<String, dynamic>;
    final r = m['r'] as String?;
    final p = m['p'] as Map<String, dynamic>?;
    return Review(
      DateTime.parse(m['d'] as String),
      Rating.values.where((x) => x.name == r).firstOrNull,
      p == null ? null : PriorState.fromJson(p),
    );
  }
}

/// Un sujet à réviser (ex. « Les nombres complexes »), éventuellement rangé
/// dans un chapitre de sa matière. Le prochain rappel
/// dépend de la note donnée à chaque révision.
class Topic {
  Topic({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.studiedOn,
    this.note = '',
    this.chapterId,
    this.reviewCount = 0,
    this.interval = 0,
    this.ease = defaultEase,
    this.due,
    DateTime? createdAt,
    List<Review>? history,
    this.updatedAt = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        history = history ?? [];

  final String id;
  String subjectId;
  String title;
  String note;

  /// Chapitre de la matière ; `null` (ou chapitre disparu) : « Autre ».
  String? chapterId;

  /// Jour où le sujet a été étudié (ou réétudié) : point de départ du cycle.
  DateTime studiedOn;

  /// Nombre de révisions faites depuis [studiedOn].
  int reviewCount;

  /// Jours entre la dernière révision et le prochain rappel (0 : jamais revu).
  int interval;

  /// Facteur appliqué à l'intervalle quand une révision se passe bien.
  double ease;

  /// Prochain rappel ; `null` quand il n'y en a plus (examen passé, rappels
  /// arrêtés).
  DateTime? due;

  DateTime createdAt;

  /// Révisions faites, de la plus ancienne à la plus récente.
  final List<Review> history;

  /// Dernière modification (ms depuis 1970), pour la synchronisation.
  int updatedAt;

  bool get isDone => due == null;

  DateTime? get lastReviewed => history.isEmpty ? null : history.last.day;

  int get memory => memoryLevel(interval);

  Map<String, dynamic> toJson() => {
        'id': id,
        'subjectId': subjectId,
        'title': title,
        'note': note,
        'chapterId': chapterId,
        'studiedOn': dateKey(studiedOn),
        'stepsDone': reviewCount,
        'interval': interval,
        'ease': ease,
        'due': due == null ? null : dateKey(due!),
        'createdAt': createdAt.toIso8601String(),
        'history': history.map((r) => r.toJson()).toList(),
        'u': updatedAt,
      };

  factory Topic.fromJson(Map<String, dynamic> j) {
    final history = <Review>[
      for (final r in j['history'] as List? ?? const []) Review.fromJson(r as Object),
    ];
    // Première version : seule la dernière révision était conservée.
    final last = j['lastReviewed'] as String?;
    if (history.isEmpty && last != null) {
      history.add(Review(DateTime.parse(last)));
    }

    final studiedOn = DateTime.parse(j['studiedOn'] as String);
    final due = j['due'] == null ? null : DateTime.parse(j['due'] as String);
    final count = (j['stepsDone'] as num).toInt();

    // Données d'avant les notes : on déduit l'intervalle de l'écart entre la
    // dernière révision (ou l'étude) et le rappel prévu.
    var interval = (j['interval'] as num?)?.toInt();
    if (interval == null) {
      final from = history.isEmpty ? studiedOn : history.last.day;
      if (count == 0) {
        interval = 0;
      } else if (due == null) {
        interval = 30; // cycle J+1 / J+7 / J+30 terminé
      } else {
        interval = daysBetween(from, due).clamp(1, maxInterval);
      }
    }

    return Topic(
      id: j['id'] as String,
      subjectId: j['subjectId'] as String,
      title: j['title'] as String,
      note: j['note'] as String? ?? '',
      chapterId: j['chapterId'] as String?,
      studiedOn: studiedOn,
      reviewCount: count,
      interval: interval,
      ease: (j['ease'] as num?)?.toDouble() ?? defaultEase,
      due: due,
      createdAt: DateTime.parse(j['createdAt'] as String),
      history: history,
      updatedAt: (j['u'] as num?)?.toInt() ?? 0,
    );
  }
}
