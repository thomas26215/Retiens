// Utilitaires de dates (jour calendaire local, sans heure).

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Ajoute des jours calendaires (insensible au changement d'heure).
DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Nombre de jours calendaires entre [from] et [to] (négatif si [to] est avant).
int daysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}
