import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../data/app_state.dart';
import '../logic/dates.dart';
import '../models/topic.dart';

/// Widgets de l'écran d'accueil (Android) : « Révisions du jour » et
/// « Série ». L'app prépare les données, les widgets natifs les affichent
/// (android/app/src/main/kotlin/…/*WidgetProvider.kt).
class HomeWidgets {
  HomeWidgets._();

  static final HomeWidgets instance = HomeWidgets._();

  static const todayWidget = 'com.solobyte.revise.TodayWidgetProvider';
  static const streakWidget = 'com.solobyte.revise.StreakWidgetProvider';

  /// Clé des données partagées avec les widgets.
  static const dataKey = 'retiens_widget';

  bool _ready = false;
  Timer? _debounce;

  /// Faux dans les tests et hors Android.
  bool get available => _ready;

  void init(AppState app) {
    if (kIsWeb || !Platform.isAndroid) return;
    _ready = true;
    app.addListener(() => _schedule(app));
    _schedule(app);
  }

  void _schedule(AppState app) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _push(app));
  }

  Future<void> _push(AppState app) async {
    try {
      await HomeWidget.saveWidgetData<String>(
        dataKey,
        jsonEncode(buildWidgetData(app)),
      );
      await HomeWidget.updateWidget(qualifiedAndroidName: todayWidget);
      await HomeWidget.updateWidget(qualifiedAndroidName: streakWidget);
    } catch (e) {
      debugPrint('Widgets : $e');
    }
  }

  /// Liens ouverts depuis un widget pendant que l'app tourne.
  Stream<Uri?> get clicks =>
      _ready ? HomeWidget.widgetClicked : const Stream.empty();

  /// Lien qui a lancé l'app depuis un widget, le cas échéant.
  Future<Uri?> initialClick() async {
    if (!_ready) return null;
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } catch (_) {
      return null;
    }
  }

  /// Propose d'ajouter un widget à l'écran d'accueil. Faux si le lanceur ne
  /// le permet pas (il faut alors passer par l'écran d'accueil).
  Future<bool> pin(String widget) async {
    if (!_ready) return false;
    try {
      if (await HomeWidget.isRequestPinWidgetSupported() != true) return false;
      await HomeWidget.requestPinWidget(qualifiedAndroidName: widget);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Données des widgets, préparées pour les [days] prochains jours : si l'app
/// n'est pas ouverte, le widget affiche quand même le bon jour (en supposant
/// qu'aucune révision n'a été faite entre-temps).
///
/// ```
/// {
///   'v': 1,
///   'days': {'yyyy-MM-dd': {'n': 3, 'items': [{'id', 't', 'c'}, …]}},
///   'done': 2, 'doneDay': 'yyyy-MM-dd',      // révisions faites ce jour-là
///   'streak': 5, 'streakDay': 'yyyy-MM-dd',  // dernier jour de la série
/// }
/// ```
Map<String, dynamic> buildWidgetData(AppState app, {int days = 14, int items = 4}) {
  final today = app.today;
  final pending = app.topics.where((t) => t.due != null).toList()
    ..sort((a, b) {
      final c = a.due!.compareTo(b.due!);
      return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
    });

  Map<String, dynamic> entry(Topic t) => {
        'id': t.id,
        't': t.title,
        'c': app.subjectById(t.subjectId)?.colorValue ?? 0xFF8A8A8A,
      };

  final byDay = <String, dynamic>{};
  for (var i = 0; i < days; i++) {
    final d = addDays(today, i);
    final due = pending.where((t) => !t.due!.isAfter(d)).toList();
    byDay[dateKey(d)] = {
      'n': due.length,
      'items': [for (final t in due.take(items)) entry(t)],
    };
  }

  final streak = app.streak;
  final streakDay = app.reviewedToday > 0 ? today : addDays(today, -1);
  return {
    'v': 1,
    'days': byDay,
    'done': app.reviewedToday,
    'doneDay': dateKey(today),
    'streak': streak,
    'streakDay': dateKey(streakDay),
  };
}
