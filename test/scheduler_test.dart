import 'package:flutter_test/flutter_test.dart';
import 'package:retiens/logic/dates.dart';
import 'package:retiens/logic/scheduler.dart';
import 'package:retiens/models/topic.dart';

void main() {
  final today = DateTime(2026, 10, 22);

  group('notes', () {
    test('après l\'étude (ou un oubli) : demain, 3, 6 ou 10 jours', () {
      final o = outcomes(interval: 0, ease: defaultEase, elapsed: 1);
      expect(o[Rating.again]!.interval, 1);
      expect(o[Rating.hard]!.interval, 3);
      expect(o[Rating.good]!.interval, 6);
      expect(o[Rating.easy]!.interval, 10);
      // Un oubli ramène à 1 jour : la réussite suivante repart de là.
      expect(outcomes(interval: 1, ease: 2.0, elapsed: 1)[Rating.good]!.interval, 6);
    });

    test('ensuite, « Bien » multiplie l\'intervalle par la facilité', () {
      final o = outcomes(interval: 6, ease: 2.5, elapsed: 6);
      expect(o[Rating.hard]!.interval, 7);
      expect(o[Rating.good]!.interval, 15);
      expect(o[Rating.easy]!.interval, 20);
    });

    test('la facilité baisse si c\'est dur, monte si c\'est facile, bornée', () {
      final o = outcomes(interval: 6, ease: 2.5, elapsed: 6);
      expect(o[Rating.again]!.ease, closeTo(2.3, 1e-9));
      expect(o[Rating.hard]!.ease, closeTo(2.35, 1e-9));
      expect(o[Rating.good]!.ease, 2.5);
      expect(o[Rating.easy]!.ease, closeTo(2.65, 1e-9));
      expect(outcomes(interval: 6, ease: minEase, elapsed: 6)[Rating.again]!.ease, minEase);
      expect(outcomes(interval: 6, ease: maxEase, elapsed: 6)[Rating.easy]!.ease, maxEase);
    });

    test('les intervalles sont toujours croissants d\'une note à l\'autre', () {
      for (final interval in [0, 1, 2, 3, 6, 15, 40, 170]) {
        for (final ease in [minEase, 2.0, 2.5, maxEase]) {
          for (final pace in paces) {
            final o = outcomes(
              interval: interval,
              ease: ease,
              elapsed: interval,
              pace: pace.factor,
            );
            final days = Rating.values.map((r) => o[r]!.interval).toList();
            for (var i = 1; i < days.length; i++) {
              expect(days[i], greaterThanOrEqualTo(days[i - 1]),
                  reason: 'intervalle $interval, facilité $ease, ${pace.key}');
            }
            expect(days.last, lessThanOrEqualTo(maxInterval));
          }
        }
      }
    });

    test('une réussite en retard compte le temps réellement tenu', () {
      final o = outcomes(interval: 6, ease: 2.5, elapsed: 10);
      expect(o[Rating.good]!.interval, 25);
      expect(o[Rating.hard]!.interval, 7);
    });

    test('le rythme général espace ou rapproche les rappels', () {
      final relaxed = outcomes(interval: 0, ease: defaultEase, elapsed: 1, pace: 1.4);
      expect(relaxed[Rating.good]!.interval, 8);
      final intense = outcomes(interval: 0, ease: defaultEase, elapsed: 1, pace: 0.7);
      expect(intense[Rating.good]!.interval, 4);
      expect(intense[Rating.again]!.interval, 1);
    });
  });

  group('examen', () {
    final exam = DateTime(2026, 11, 5);

    test('jamais de rappel après la veille', () {
      expect(
        capToExam(DateTime(2026, 11, 20), today: today, earliest: today, examDate: exam),
        DateTime(2026, 11, 4),
      );
      expect(
        capToExam(DateTime(2026, 10, 30), today: today, earliest: today, examDate: exam),
        DateTime(2026, 10, 30),
      );
      expect(
        capToExam(DateTime(2026, 12, 1), today: today, earliest: today),
        DateTime(2026, 12, 1),
      );
    });

    test('plus de rappel si l\'examen est passé, ou si la veille est trop tôt', () {
      expect(capToExam(DateTime(2026, 11, 20), today: exam, earliest: exam, examDate: exam), isNull);
      final eve = DateTime(2026, 11, 4);
      expect(capToExam(DateTime(2026, 11, 10), today: eve, earliest: exam, examDate: exam), isNull);
    });

    test('premier rappel : le lendemain de l\'étude, ou tout de suite', () {
      expect(firstDue(studiedOn: today, today: today), DateTime(2026, 10, 23));
      expect(firstDue(studiedOn: DateTime(2026, 10, 1), today: today), today);
      // Étudié la veille de l'examen : pas de révision le jour même.
      expect(
        firstDue(studiedOn: today, today: today, examDate: DateTime(2026, 10, 23)),
        isNull,
      );
    });
  });

  test('projection : rappels successifs si tout se passe bien', () {
    expect(
      projectedDates(due: DateTime(2026, 10, 23), interval: 0, ease: 2.5, today: today, limit: 4),
      [
        DateTime(2026, 10, 23),
        DateTime(2026, 10, 29),
        DateTime(2026, 11, 13),
        DateTime(2026, 12, 21), // 15 × 2,5 = 37,5 → 38 jours
      ],
    );
    // En retard : la projection part d'aujourd'hui.
    expect(
      projectedDates(due: DateTime(2026, 10, 1), interval: 6, ease: 2.5, today: today, limit: 2),
      [today, DateTime(2026, 11, 6)],
    );
    // Avec un examen : on s'arrête à la veille.
    expect(
      projectedDates(
        due: DateTime(2026, 10, 23),
        interval: 0,
        ease: 2.5,
        today: today,
        examDate: DateTime(2026, 11, 10),
      ),
      [DateTime(2026, 10, 23), DateTime(2026, 10, 29), DateTime(2026, 11, 9)],
    );
    expect(projectedDates(due: null, interval: 6, ease: 2.5, today: today), isEmpty);
  });

  test('solidité du souvenir', () {
    expect([0, 1, 3, 7, 21, 60, 180].map(memoryLevel), [0, 1, 2, 3, 4, 5, 5]);
    expect(ordinal(1), '1re');
    expect(ordinal(4), '4e');
  });

  test('daysBetween ignore l\'heure', () {
    expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    expect(daysBetween(DateTime(2026, 10, 26), DateTime(2026, 10, 24)), -2);
  });

  test('un sujet et ses notes survivent à la sérialisation JSON', () {
    final t = Topic(
      id: 'a',
      subjectId: 's',
      title: 'Chapitre 1',
      note: 'p. 1-20',
      studiedOn: today,
      reviewCount: 2,
      interval: 15,
      ease: 2.35,
      due: DateTime(2026, 11, 13),
      history: [Review(DateTime(2026, 10, 23), Rating.hard), Review(DateTime(2026, 10, 29))],
    );
    final back = Topic.fromJson(t.toJson());
    expect(back.note, 'p. 1-20');
    expect(back.reviewCount, 2);
    expect(back.interval, 15);
    expect(back.ease, 2.35);
    expect(back.due, DateTime(2026, 11, 13));
    expect(back.history.map((r) => r.rating), [Rating.hard, null]);
    expect(back.lastReviewed, DateTime(2026, 10, 29));
  });

  test('anciennes données (rappels fixes) : intervalle déduit', () {
    final v1 = Topic.fromJson({
      'id': 'a',
      'subjectId': 's',
      'title': 'Ancien',
      'studiedOn': '2026-10-01',
      'stepsDone': 1,
      'due': '2026-10-08',
      'createdAt': '2026-10-01T10:00:00.000',
      'lastReviewed': '2026-10-02',
    });
    expect(v1.history.single.day, DateTime(2026, 10, 2));
    expect(v1.history.single.rating, isNull);
    expect(v1.interval, 6);
    expect(v1.ease, defaultEase);

    final v11 = Topic.fromJson({
      'id': 'b',
      'subjectId': 's',
      'title': 'Fini',
      'studiedOn': '2026-09-01',
      'stepsDone': 3,
      'due': null,
      'createdAt': '2026-09-01T10:00:00.000',
      'history': ['2026-09-02', '2026-09-08', '2026-10-01'],
    });
    expect(v11.history.length, 3);
    expect(v11.interval, 30);
    expect(v11.memory, 4);
  });
}
