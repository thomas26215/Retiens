import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:retiens/data/app_state.dart';
import 'package:retiens/logic/dates.dart';
import 'package:retiens/logic/scheduler.dart';
import 'package:retiens/models/subject.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _fresh([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return AppState.load();
}

void main() {
  test('révision notée : intervalle, historique, compteur, puis annulation', () async {
    final app = await _fresh();
    final s = app.addSubject('Maths', subjectPalette[0], null);
    final t = app.addTopic(
      subjectId: s.id,
      title: 'Chapitre 1',
      studiedOn: addDays(app.today, -1),
    );
    expect(app.dueCount(), 1);

    final snap = app.review(t, Rating.good);
    expect(t.reviewCount, 1);
    expect(t.interval, 6);
    expect(t.due, addDays(app.today, 6));
    expect(t.history.single.rating, Rating.good);
    expect(app.reviewedToday, 1);
    expect(app.dueCount(), 0);
    expect(app.reviewedOn(app.today).single.$1, t);

    app.restore(t, snap);
    expect(t.reviewCount, 0);
    expect(t.interval, 0);
    expect(t.history, isEmpty);
    expect(app.reviewedToday, 0);
    expect(app.dueCount(), 1);
  });

  test('annuler la dernière révision : état d\'avant exact, plusieurs fois', () async {
    final app = await _fresh();
    final s = app.addSubject('Maths', subjectPalette[0], null);
    final t = app.addTopic(subjectId: s.id, title: 'C1', studiedOn: addDays(app.today, -1));
    final firstDue = t.due;
    app.review(t, Rating.hard);
    app.review(t, Rating.good);
    expect(app.reviewedToday, 2);

    expect(app.undoLastReview(t), isNotNull);
    expect(t.reviewCount, 1);
    expect(t.interval, 3);
    expect(t.ease, closeTo(defaultEase - 0.15, 1e-9));
    expect(t.due, addDays(app.today, 3));
    expect(t.history.single.rating, Rating.hard);
    expect(app.reviewedToday, 1);

    final snap = app.undoLastReview(t)!;
    expect(t.reviewCount, 0);
    expect(t.interval, 0);
    expect(t.ease, defaultEase);
    expect(t.due, firstDue);
    expect(app.isDue(t), isTrue);
    expect(app.reviewedToday, 0);
    expect(app.canUndoLastReview(t), isFalse);
    expect(app.undoLastReview(t), isNull);

    // « Rétablir » : la révision annulée revient, compteur compris.
    app.restore(t, snap);
    expect(t.history.single.rating, Rating.hard);
    expect(t.interval, 3);
    expect(app.reviewedToday, 1);
  });

  test('annulation possible après redémarrage de l\'app', () async {
    final app = await _fresh();
    final s = app.addSubject('Maths', subjectPalette[0], null);
    final t = app.addTopic(subjectId: s.id, title: 'C1', studiedOn: addDays(app.today, -1));
    app.review(t, Rating.easy);
    await Future<void>.delayed(Duration.zero);

    final again = await AppState.load();
    final back = again.topics.single;
    expect(again.undoLastReview(back), isNotNull);
    expect(back.interval, 0);
    expect(back.ease, defaultEase);
    expect(again.isDue(back), isTrue);
  });

  test('anciennes révisions (sans état enregistré) : annulation estimée', () async {
    final today = dateOnly(DateTime.now());
    final d1 = addDays(today, -10);
    final d2 = addDays(today, -4);
    final data = {
      'subjects': [
        {'id': 's', 'name': 'Maths', 'color': subjectPalette[0], 'examDate': null},
      ],
      'topics': [
        {
          'id': 't',
          'subjectId': 's',
          'title': 'C1',
          'note': '',
          'studiedOn': dateKey(addDays(today, -11)),
          'stepsDone': 2,
          'interval': 20,
          'ease': 2.65,
          'due': dateKey(addDays(today, 16)),
          'createdAt': addDays(today, -11).toIso8601String(),
          'history': [
            {'d': dateKey(d1), 'r': 'good'},
            {'d': dateKey(d2), 'r': 'easy'},
          ],
        },
      ],
      'log': {dateKey(d1): 1, dateKey(d2): 2},
    };
    final app = await _fresh({'retiens_topics_v1': jsonEncode(data)});
    final t = app.topics.single;
    expect(app.undoLastReview(t), isNotNull);
    expect(t.reviewCount, 1);
    expect(t.interval, 6);
    expect(t.ease, closeTo(2.5, 1e-9));
    expect(t.due, d2);
    expect(app.isDue(t), isTrue);
    expect(app.reviewsOn(d2), 1);
    expect(app.reviewsOn(d1), 1);
  });

  test('pas d\'annulation à travers « Réétudié aujourd\'hui »', () async {
    final app = await _fresh();
    final s = app.addSubject('Maths', subjectPalette[0], null);
    final t = app.addTopic(subjectId: s.id, title: 'C1', studiedOn: addDays(app.today, -1));
    app.review(t, Rating.good);
    expect(app.canUndoLastReview(t), isTrue);
    app.restart(t);
    expect(app.canUndoLastReview(t), isFalse);
    expect(app.undoLastReview(t), isNull);
    expect(app.topicsReviewedToday, [t]);
  });

  test('« Oublié » : rappel demain et facilité en baisse', () async {
    final app = await _fresh();
    final s = app.addSubject('Maths', subjectPalette[0], null);
    final t = app.addTopic(subjectId: s.id, title: 'C1', studiedOn: addDays(app.today, -1));
    app.review(t, Rating.again);
    expect(t.due, addDays(app.today, 1));
    expect(t.interval, 1);
    expect(t.ease, closeTo(defaultEase - 0.2, 1e-9));
  });

  test('aperçu : chaque note donne un rappel plus lointain', () async {
    final app = await _fresh();
    final s = app.addSubject('Maths', subjectPalette[0], null);
    final t = app.addTopic(subjectId: s.id, title: 'C1', studiedOn: addDays(app.today, -1));
    final p = app.previewDue(t);
    expect(p[Rating.again], addDays(app.today, 1));
    expect(p[Rating.hard], addDays(app.today, 3));
    expect(p[Rating.good], addDays(app.today, 6));
    expect(p[Rating.easy], addDays(app.today, 10));
  });

  test('examen proche : le rappel est ramené à la veille', () async {
    final app = await _fresh();
    final s = app.addSubject('Maths', subjectPalette[0], addDays(app.today, 4));
    final t = app.addTopic(subjectId: s.id, title: 'C1', studiedOn: addDays(app.today, -1));
    app.review(t, Rating.easy);
    expect(t.due, addDays(app.today, 3));
  });

  test('réétudié, arrêt et reprise des rappels', () async {
    final app = await _fresh();
    final s = app.addSubject('Maths', subjectPalette[0], null);
    final t = app.addTopic(subjectId: s.id, title: 'C1', studiedOn: addDays(app.today, -40));
    app.review(t, Rating.easy);
    final ease = t.ease;

    app.restart(t);
    expect(t.studiedOn, app.today);
    expect(t.reviewCount, 0);
    expect(t.interval, 0);
    expect(t.ease, ease);
    expect(t.due, addDays(app.today, 1));

    app.stop(t);
    expect(t.isDone, isTrue);
    expect(app.resume(t), isTrue);
    expect(t.due, addDays(app.today, 1));
  });

  test('séries : actuelle et meilleure', () async {
    final app = await _fresh();
    final today = app.today;
    for (final d in [0, 1, 2, 5, 6, 7, 8]) {
      app.log[dateKey(addDays(today, -d))] = 1;
    }
    expect(app.streak, 3);
    expect(app.bestStreak, 4);
    expect(app.totalReviews, 7);
  });

  test('planning : prochain rappel puis suivants estimés', () async {
    final app = await _fresh();
    final s = app.addSubject('Maths', subjectPalette[0], null);
    app.addTopic(subjectId: s.id, title: 'C1', studiedOn: app.today);
    final plan = app.plannedBetween(app.today, addDays(app.today, 30));
    expect(plan.keys.toList()..sort(), [
      addDays(app.today, 1),
      addDays(app.today, 7),
      addDays(app.today, 22),
    ]);
    expect(plan[addDays(app.today, 1)]!.single.isNext, isTrue);
    expect(plan[addDays(app.today, 7)]!.single.number, 2);
    expect(plan[addDays(app.today, 7)]!.single.isNext, isFalse);
  });

  test('statistiques : notes et maîtrise', () async {
    final app = await _fresh();
    final s = app.addSubject('Maths', subjectPalette[0], null);
    final a = app.addTopic(subjectId: s.id, title: 'A', studiedOn: addDays(app.today, -1));
    final b = app.addTopic(subjectId: s.id, title: 'B', studiedOn: addDays(app.today, -1));
    app.review(a, Rating.good);
    app.review(b, Rating.again);
    final counts = app.ratingsBetween(addDays(app.today, -29), app.today);
    expect(counts[Rating.good], 1);
    expect(counts[Rating.again], 1);
    expect(counts[Rating.easy], 0);
    // A : intervalle 6 j (niveau 2), B : 1 j (niveau 1) → 3 / 10.
    expect(app.subjectMastery(s.id), closeTo(0.3, 1e-9));
  });

  test('sauvegarde : export puis restauration', () async {
    final app = await _fresh();
    final s = app.addSubject('Maths', subjectPalette[2], addDays(app.today, 30));
    final t = app.addTopic(
      subjectId: s.id,
      title: 'Chapitre 1',
      studiedOn: addDays(app.today, -1),
      note: 'p. 1-20',
    );
    app.review(t, Rating.hard);
    app.setPace('detendu');
    final backup = app.exportJson();

    final other = await _fresh();
    expect(other.inspectBackup('pas du json'), isNull);
    expect(other.inspectBackup('{"a": 1}'), isNull);
    expect(other.inspectBackup(backup), (subjects: 1, topics: 1));
    expect(await other.importJson(backup), isTrue);
    expect(other.subjects.single.name, 'Maths');
    final back = other.topics.single;
    expect(back.note, 'p. 1-20');
    expect(back.history.single.rating, Rating.hard);
    expect(back.interval, t.interval);
    expect(back.ease, t.ease);
    expect(other.reviewedToday, 1);
    expect(other.paceKey, 'detendu');
  });

  test('données de la version à rappels fixes reprises telles quelles', () async {
    final today = dateOnly(DateTime.now());
    final old = {
      'subjects': [
        {'id': 's', 'name': 'Maths', 'color': 0xFF009688, 'examDate': null},
      ],
      'topics': [
        {
          'id': 't',
          'subjectId': 's',
          'title': 'Chapitre 1',
          'note': '',
          'studiedOn': dateKey(addDays(today, -8)),
          'stepsDone': 1,
          'due': dateKey(addDays(today, -1)),
          'createdAt': addDays(today, -8).toIso8601String(),
          'history': [dateKey(addDays(today, -7))],
        },
      ],
      'log': {dateKey(addDays(today, -7)): 1},
      'rhythm': 'intensif',
      'customSteps': [1, 3, 10, 30],
    };
    final app = await _fresh({'retiens_topics_v1': jsonEncode(old)});
    final t = app.topics.single;
    expect(app.paceKey, 'soutenu');
    expect(app.subjects.single.colorValue, subjectPalette[2]);
    expect(t.interval, 6);
    expect(app.dueCount(), 1);
    app.review(t, Rating.good);
    expect(t.reviewCount, 2);
    expect(t.history.map((r) => r.rating), [null, Rating.good]);
  });

  test('réglages conservés au redémarrage', () async {
    final app = await _fresh();
    app.setPace('soutenu');
    await Future<void>.delayed(Duration.zero);
    final again = await AppState.load();
    expect(again.paceKey, 'soutenu');
  });

  test('nouvelle matière : première couleur libre', () async {
    final app = await _fresh();
    app.addSubject('A', subjectPalette[0], null);
    expect(app.nextSubjectColor(), subjectPalette[1]);
  });
}
