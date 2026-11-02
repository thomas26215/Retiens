import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retiens/data/app_state.dart';
import 'package:retiens/data/sync_merge.dart';
import 'package:retiens/logic/dates.dart';
import 'package:retiens/main.dart';
import 'package:retiens/models/subject.dart';
import 'package:retiens/models/topic.dart';
import 'package:retiens/widgets/motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens_test.dart' show tapVisible;

Future<AppState> _fresh([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  return AppState.load();
}

void main() {
  test('chapitres : créer, renommer, réordonner, supprimer', () async {
    final app = await _fresh();
    final maths = app.addSubject('Maths', subjectPalette[0], null);
    final c1 = app.addChapter(maths, 'Chapitre 1');
    final c2 = app.addChapter(maths, 'Chapitre 2');
    final t = app.addTopic(
      subjectId: maths.id,
      title: 'Complexes',
      studiedOn: app.today,
      chapterId: c1.id,
    );
    final loose = app.addTopic(subjectId: maths.id, title: 'Divers', studiedOn: app.today);
    expect(app.chapterOf(t), c1);
    expect(app.chapterOf(loose), isNull);

    app.renameChapter(maths, c1, 'Ch. 1 : nombres complexes');
    expect(maths.chapters.first.name, 'Ch. 1 : nombres complexes');
    app.moveChapter(maths, c2, -1);
    expect(maths.chapters, [c2, c1]);
    app.moveChapter(maths, c2, -1); // déjà en tête : rien ne bouge
    expect(maths.chapters, [c2, c1]);

    app.moveTopicToChapter(loose, c2.id);
    expect(app.chapterOf(loose), c2);

    // Supprimer un chapitre garde ses sujets, rangés dans « Autre ».
    app.deleteChapter(maths, c1);
    expect(maths.chapters, [c2]);
    expect(app.topics, contains(t));
    expect(app.chapterOf(t), isNull);
  });

  test('changer de matière retire le chapitre de l\'ancienne', () async {
    final app = await _fresh();
    final maths = app.addSubject('Maths', subjectPalette[0], null);
    final physique = app.addSubject('Physique', subjectPalette[1], null);
    final c = app.addChapter(maths, 'Chapitre 1');
    final t = app.addTopic(
      subjectId: maths.id,
      title: 'Complexes',
      studiedOn: app.today,
      chapterId: c.id,
    );
    app.updateTopic(
      t,
      subjectId: physique.id,
      title: t.title,
      note: '',
      studiedOn: t.studiedOn,
      chapterId: c.id,
    );
    expect(t.chapterId, isNull);
    // Un chapitre d'une autre matière est refusé à la création aussi.
    final u = app.addTopic(
      subjectId: physique.id,
      title: 'Ondes',
      studiedOn: app.today,
      chapterId: c.id,
    );
    expect(u.chapterId, isNull);
  });

  test('chapitres conservés dans les sauvegardes et au redémarrage', () async {
    final app = await _fresh();
    final maths = app.addSubject('Maths', subjectPalette[0], null);
    final c = app.addChapter(maths, 'Chapitre 1');
    app.addTopic(subjectId: maths.id, title: 'A', studiedOn: app.today, chapterId: c.id);
    await Future<void>.delayed(Duration.zero);

    final again = await AppState.load();
    expect(again.subjects.single.chapters.single.name, 'Chapitre 1');
    expect(again.chapterOf(again.topics.single)?.name, 'Chapitre 1');

    final other = await _fresh();
    expect(await other.importJson(app.exportJson()), isTrue);
    expect(other.chapterOf(other.topics.single)?.name, 'Chapitre 1');

    // Anciennes données (sans chapitres) : tout est dans « Autre ».
    final old = Subject.fromJson({'id': 's', 'name': 'X', 'color': subjectPalette[0]});
    expect(old.chapters, isEmpty);
    final oldTopic = Topic.fromJson({
      'id': 't',
      'subjectId': 's',
      'title': 'T',
      'studiedOn': '2026-10-01',
      'stepsDone': 0,
      'due': null,
      'createdAt': '2026-10-01T10:00:00.000',
    });
    expect(oldTopic.chapterId, isNull);
  });

  test('synchronisation : chapitres partagés, chapitre supprimé ailleurs', () async {
    final a = await _fresh({'retiens_device_id': 'A'});
    final maths = a.addSubject('Maths', subjectPalette[0], null);
    final c = a.addChapter(maths, 'Chapitre 1');
    a.addTopic(subjectId: maths.id, title: 'A', studiedOn: a.today, chapterId: c.id);
    final now = DateTime.now().millisecondsSinceEpoch;

    final b = await _fresh({'retiens_device_id': 'B'});
    b.applyCloud(mergeCloud(b.toCloud(), a.toCloud(), deviceId: 'B', now: now));
    expect(b.chapterOf(b.topics.single)?.name, 'Chapitre 1');

    // B ajoute un sujet au chapitre pendant que A supprime le chapitre.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    b.addTopic(
      subjectId: maths.id,
      title: 'B',
      studiedOn: b.today,
      chapterId: b.subjects.single.chapters.single.id,
    );
    a.deleteChapter(maths, c);
    a.applyCloud(mergeCloud(a.toCloud(), b.toCloud(), deviceId: 'A', now: now + 10));
    // Le sujet de B pointe vers un chapitre disparu : il est dans « Autre ».
    final topicB = a.topics.firstWhere((t) => t.title == 'B');
    expect(a.subjects.single.chapters, isEmpty);
    expect(a.chapterOf(topicB), isNull);
  });

  testWidgets('écran d\'une matière : créer un chapitre, y ranger un sujet', (tester) async {
    ambientMotion = false;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final app = await _fresh();
    final maths = app.addSubject('Mathématiques', subjectPalette[0], null);
    app.addTopic(subjectId: maths.id, title: 'Complexes', studiedOn: addDays(app.today, -1));
    await tester.pumpWidget(RetiensApp(state: app));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Matières').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mathématiques').first);
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('Organiser en chapitres'));
    await tester.enterText(find.byType(TextField), 'Chapitre 1 : nombres');
    await tester.pump(); // le bouton s'active après la saisie
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();
    expect(maths.chapters.single.name, 'Chapitre 1 : nombres');
    // Le sujet existant est dans « Autre ».
    expect(find.text('Autre'), findsOneWidget);
    expect(find.text('Chapitre 1 : nombres'), findsOneWidget);

    // Fiche du sujet → « Changer de chapitre ».
    await tapVisible(tester, find.text('Complexes'));
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Changer de chapitre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapitre 1 : nombres').last);
    await tester.pumpAndSettle();
    expect(app.chapterOf(app.topics.single)?.name, 'Chapitre 1 : nombres');
    expect(find.textContaining('Mathématiques › Chapitre 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    // « Autre » est vide : il disparaît.
    expect(find.text('Autre'), findsNothing);

    // Replier le chapitre masque ses sujets.
    await tester.tap(find.text('Chapitre 1 : nombres'));
    await tester.pumpAndSettle();
    expect(find.text('Complexes'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
