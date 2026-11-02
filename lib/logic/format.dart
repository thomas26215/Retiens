import 'dates.dart';

const _months = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

const _monthsLong = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

const _weekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const _weekdaysShort = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];

/// Initiales des jours, du lundi au dimanche.
const weekdayInitials = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// « 22 oct. 2026 »
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// « 22 oct. »
String formatDayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// « mer. 22 oct. »
String formatShortDay(DateTime d) =>
    '${_weekdaysShort[d.weekday - 1]} ${formatDayMonth(d)}';

/// « mercredi 22 octobre »
String formatLongDay(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_monthsLong[d.month - 1]}';

/// « octobre 2026 »
String formatMonthYear(DateTime d) => '${_monthsLong[d.month - 1]} ${d.year}';

/// « oct. »
String formatMonthShort(DateTime d) => _months[d.month - 1];

String formatTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// « 1 sujet », « 3 sujets » (0 au singulier, comme en français).
String plural(int n, String word, [String? pluralWord]) =>
    '$n ${n > 1 ? (pluralWord ?? '${word}s') : word}';

/// « aujourd'hui », « demain », « dans 5 j », « hier », « il y a 3 j ».
String formatRelativeDay(DateTime day, DateTime today) {
  final diff = daysBetween(today, day);
  if (diff == 0) return "aujourd'hui";
  if (diff == 1) return 'demain';
  if (diff == -1) return 'hier';
  if (diff > 1) return 'dans $diff j';
  return 'il y a ${-diff} j';
}
