import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retiens/data/app_state.dart';
import 'package:retiens/logic/dates.dart';
import 'package:retiens/logic/scheduler.dart';
import 'package:retiens/main.dart';
import 'package:retiens/models/subject.dart';
import 'package:retiens/widgets/motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Données d'exemple : deux matières, des sujets à revoir, en cours, terminés.
Future<AppState> sampleState() async {
  SharedPreferences.setMockInitialValues({});
  final app = await AppState.load();
  final today = app.today;
  final maths = app.addSubject('Mathématiques', subjectPalette[0], addDays(today, 20));
  final ie = app.addSubject(
    'Ingénierie des exigences et modélisation des systèmes',
    subjectPalette[3],
    null,
  );
  app.addTopic(
    subjectId: maths.id,
    title: 'Chapitre 1 : fondamentaux de l\'algèbre linéaire et espaces vectoriels',
    studiedOn: addDays(today, -1),
    note: 'p. 1-20, refaire les exercices 3 et 4',
  );
  app.addTopic(subjectId: maths.id, title: 'Chapitre 2 : matrices', studiedOn: addDays(today, -9));
  app.addTopic(subjectId: ie.id, title: 'Exigences fonctionnelles', studiedOn: today);
  final done = app.addTopic(subjectId: ie.id, title: 'Cas d\'utilisation', studiedOn: addDays(today, -3));
  app.review(done, Rating.good);
  for (var d = 1; d < 12; d += 2) {
    app.log[dateKey(addDays(today, -d))] = d % 5 + 1;
  }
  return app;
}

/// Ferme les bandeaux, fait défiler [finder] jusqu'au milieu de l'écran (hors
/// du bouton flottant) puis le touche.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
      .clearSnackBars();
  await tester.pumpAndSettle();
  final element = finder.evaluate().first;
  await Scrollable.ensureVisible(element, alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Bouton retour de l'AppBar (infobulle en français, d'où pas de pageBack()).
Future<void> back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Retour'));
  await tester.pumpAndSettle();
}

void main() {
  // La flamme ondule en continu : l'interface ne serait jamais stable.
  setUp(() => ambientMotion = false);

  testWidgets('tous les écrans s\'affichent sans erreur sur un téléphone', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final app = await sampleState();
    await tester.pumpWidget(RetiensApp(state: app));
    await tester.pumpAndSettle();

    expect(find.text('Chapitre 2 : matrices'), findsOneWidget);
    final dueBefore = app.dueCount();
    await tester.tap(find.byTooltip('Revu').first);
    await tester.pumpAndSettle();
    expect(find.text('Comment ça s\'est passé ?'), findsOneWidget);
    await tester.tap(find.text('Bien'));
    await tester.pumpAndSettle();
    expect(app.dueCount(), dueBefore - 1);
    expect(find.text('Annuler'), findsOneWidget);

    // « Revus aujourd'hui » : annuler la révision, puis la rétablir.
    expect(find.text("Revus aujourd'hui"), findsOneWidget);
    await tapVisible(tester, find.byTooltip('Annuler la dernière révision').first);
    expect(app.dueCount(), dueBefore);
    await tester.tap(find.text('Rétablir'));
    await tester.pumpAndSettle();
    expect(app.dueCount(), dueBefore - 1);

    for (final tab in ['Planning', 'Matières', 'Progrès', "Aujourd'hui"]) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }

    // Fiche d'un sujet à revoir : notation directe.
    await tapVisible(tester, find.text('Chapitre 2 : matrices'));
    expect(find.text('Comment s\'est passée la révision ?'), findsOneWidget);
    await tapVisible(tester, find.text('Facile'));
    expect(app.dueCount(), 0);
    expect(find.text('Parcours'), findsOneWidget);

    // Fiche : annuler la dernière révision puis noter à nouveau.
    expect(find.text('Dernière révision : facile'), findsOneWidget);
    await tapVisible(
      tester,
      find.descendant(of: find.byType(Card), matching: find.text('Annuler')),
    );
    expect(app.dueCount(), 1);
    expect(find.text('Dernière révision : facile'), findsNothing);
    await tapVisible(tester, find.text('Bien'));
    expect(app.dueCount(), 0);
    await back(tester);

    // Fiche d'un sujet.
    await tapVisible(tester, find.text('Exigences fonctionnelles').first);
    expect(find.text('Parcours'), findsOneWidget);
    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();
    expect(find.text('Rappels prévus'), findsOneWidget);
    await back(tester);
    await tester.pumpAndSettle();
    await back(tester);
    await tester.pumpAndSettle();

    // Matière.
    await tester.tap(find.text('Matières').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mathématiques').first);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Sans rappel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Modifier la matière'));
    await tester.pumpAndSettle();
    expect(find.text('Couleur'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await back(tester);
    await tester.pumpAndSettle();

    // Réglages, en thème sombre.
    await tester.tap(find.byTooltip('Réglages').first);
    await tester.pumpAndSettle();
    // Sans configuration Firebase (tests), le compte est indisponible.
    expect(find.text('Synchronisation indisponible'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sombre'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tapVisible(tester, find.text('Sombre'));
    await tester.pumpAndSettle();
    expect(app.themeMode, ThemeMode.dark);
    await back(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Progrès').last);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('premier lancement : accueil puis création d\'une matière', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final app = await AppState.load();
    await tester.pumpWidget(RetiensApp(state: app));
    await tester.pumpAndSettle();

    expect(find.text('Bienvenue dans Retiens'), findsOneWidget);
    await tester.ensureVisible(find.text('Créer ma première matière'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer ma première matière'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Physique');
    await tester.tap(find.text('Créer la matière'));
    await tester.pumpAndSettle();
    expect(app.subjects.single.name, 'Physique');
    expect(find.text('Ajoute ce que tu as étudié'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
