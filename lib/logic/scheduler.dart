import 'dart:math' as math;

import 'dates.dart';

/// Ressenti noté après une révision.
enum Rating {
  again('Oublié', "J'avais presque tout oublié"),
  hard('Difficile', 'Ça revenait, mais avec effort'),
  good('Bien', "Je me souvenais de l'essentiel"),
  easy('Facile', 'Je le maîtrise parfaitement');

  const Rating(this.label, this.description);

  final String label;
  final String description;
}

/// Rythme général : multiplie tous les intervalles (sauf « Oublié »).
class Pace {
  const Pace(this.key, this.label, this.description, this.factor);

  final String key;
  final String label;
  final String description;
  final double factor;
}

const paces = <Pace>[
  Pace('soutenu', 'Soutenu', 'Rappels plus rapprochés, avant un examen', 0.7),
  Pace('normal', 'Normal', 'Le bon compromis pour la plupart des cours', 1),
  Pace('detendu', 'Détendu', 'Rappels plus espacés, moins de révisions', 1.4),
];

Pace paceByKey(String key) =>
    paces.firstWhere((p) => p.key == key, orElse: () => paces[1]);

/// Facilité de départ d'un sujet : l'intervalle est multiplié par ce
/// facteur à chaque révision notée « Bien ».
const defaultEase = 2.5;
const minEase = 1.3;
const maxEase = 3.2;

/// Variation de la facilité selon la note.
const easeChange = <Rating, double>{
  Rating.again: -0.2,
  Rating.hard: -0.15,
  Rating.good: 0,
  Rating.easy: 0.15,
};

double clampEase(double e) => e.clamp(minEase, maxEase).toDouble();

/// Intervalle maximal entre deux rappels, en jours.
const maxInterval = 180;

/// Intervalles après la première révision réussie (ou après un oubli).
const _firstHard = 3;
const _firstGood = 6;
const _firstEasy = 10;

/// Effet d'une note : nouvel intervalle (jours) et nouvelle facilité.
class Outcome {
  const Outcome(this.interval, this.ease);

  final int interval;
  final double ease;

  @override
  bool operator ==(Object other) =>
      other is Outcome && other.interval == interval && other.ease == ease;

  @override
  int get hashCode => Object.hash(interval, ease);

  @override
  String toString() => 'Outcome($interval j, facilité $ease)';
}

/// Effet de chacune des quatre notes sur un sujet.
///
/// - [interval] : intervalle actuel en jours (0 ou 1 si le sujet vient d'être
///   étudié ou a été oublié : on repart alors des intervalles de départ).
/// - [elapsed] : jours écoulés depuis la révision précédente ; une réussite
///   après un retard compte le temps réellement tenu.
/// - [pace] : facteur du rythme général.
///
/// Les intervalles sont toujours croissants : Oublié < Difficile < Bien < Facile.
Map<Rating, Outcome> outcomes({
  required int interval,
  required double ease,
  required int elapsed,
  double pace = 1,
}) {
  final fresh = interval <= 1;
  final base = math.max(interval, elapsed).toDouble();

  int scale(double days) =>
      (days * pace).round().clamp(1, maxInterval);

  final hard = scale(fresh ? _firstHard.toDouble() : interval * 1.2);
  final good = math.max(
    hard + 1,
    scale(fresh ? _firstGood.toDouble() : base * ease),
  );
  final easy = math.max(
    good + 1,
    scale(fresh ? _firstEasy.toDouble() : base * ease * 1.3),
  );

  double next(Rating r) =>
      r == Rating.good ? ease : clampEase(ease + easeChange[r]!);

  return {
    Rating.again: Outcome(1, next(Rating.again)),
    Rating.hard: Outcome(math.min(hard, maxInterval), next(Rating.hard)),
    Rating.good: Outcome(math.min(good, maxInterval), next(Rating.good)),
    Rating.easy: Outcome(math.min(easy, maxInterval), next(Rating.easy)),
  };
}

/// Ramène [day] avant l'examen : aucun rappel après la veille.
///
/// Renvoie `null` s'il ne reste aucun jour possible : examen passé ou
/// aujourd'hui, ou veille déjà avant [earliest].
DateTime? capToExam(
  DateTime day, {
  required DateTime today,
  required DateTime earliest,
  DateTime? examDate,
}) {
  final d = dateOnly(day);
  if (examDate == null) return d;
  final exam = dateOnly(examDate);
  if (!exam.isAfter(dateOnly(today))) return null;
  final eve = addDays(exam, -1);
  if (!d.isAfter(eve)) return d;
  return eve.isBefore(dateOnly(earliest)) ? null : eve;
}

/// Premier rappel d'un sujet étudié le [studiedOn] : le lendemain, ou
/// aujourd'hui s'il a été étudié il y a plus longtemps.
DateTime? firstDue({
  required DateTime studiedOn,
  required DateTime today,
  DateTime? examDate,
}) {
  final t = dateOnly(today);
  var d = addDays(dateOnly(studiedOn), 1);
  if (d.isBefore(t)) d = t;
  // Pas de révision le jour même de l'étude, même la veille d'un examen.
  return capToExam(d, today: t, earliest: d, examDate: examDate);
}

/// Rappels à venir d'un sujet si chaque révision est notée « Bien » :
/// le prochain ([due], ramené à [today] s'il est en retard) puis les suivants,
/// au plus [limit]. Vide si le sujet n'a plus de rappel.
List<DateTime> projectedDates({
  required DateTime? due,
  required int interval,
  required double ease,
  required DateTime today,
  DateTime? examDate,
  double pace = 1,
  int limit = 8,
}) {
  final out = <DateTime>[];
  if (due == null) return out;
  final t = dateOnly(today);
  DateTime? d = due.isBefore(t) ? t : dateOnly(due);
  var current = interval;
  while (d != null && out.length < limit) {
    out.add(d);
    final next = outcomes(
      interval: current,
      ease: ease,
      elapsed: current,
      pace: pace,
    )[Rating.good]!;
    current = next.interval;
    d = capToExam(
      addDays(d, current),
      today: d,
      earliest: addDays(d, 1),
      examDate: examDate,
    );
  }
  return out;
}

/// Solidité du souvenir, de 0 (jamais revu) à 5, d'après l'intervalle.
int memoryLevel(int interval) {
  if (interval >= 60) return 5;
  if (interval >= 21) return 4;
  if (interval >= 7) return 3;
  if (interval >= 3) return 2;
  if (interval >= 1) return 1;
  return 0;
}

const memoryLabels = [
  'Nouveau',
  'Fragile',
  'En cours',
  'Correct',
  'Solide',
  'Ancré',
];

/// « 1re », « 2e », « 3e »…
String ordinal(int n) => n == 1 ? '1re' : '${n}e';
