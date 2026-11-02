import 'dart:convert';

/// État synchronisé avec le compte (document Firestore `users/{uid}`) :
///
/// ```
/// {
///   'subjects': {id: {…matière, 'u': ms}},
///   'topics':   {id: {…sujet, 'u': ms}},
///   'deleted':  {id: ms},                 // suppressions (pierres tombales)
///   'logs':     {appareil: {'yyyy-MM-dd': n}},
///   'pace': 'normal', 'paceAt': ms,
/// }
/// ```
///
/// Chaque élément porte sa date de modification `u` : à la fusion, la version
/// la plus récente l'emporte, élément par élément. Le nombre de révisions par
/// jour est tenu par appareil (chacun n'écrit que le sien), donc les
/// révisions faites le même jour sur deux téléphones s'additionnent.
typedef CloudState = Map<String, dynamic>;

/// Durée de conservation des suppressions.
const tombstoneDays = 180;

/// Fusionne l'état [local] de l'appareil [deviceId] avec l'état [remote].
CloudState mergeCloud(
  CloudState local,
  CloudState remote, {
  required String deviceId,
  required int now,
}) {
  final deleted = <String, int>{};
  final oldest = now - tombstoneDays * Duration.millisecondsPerDay;
  for (final source in [remote, local]) {
    _map(source['deleted']).forEach((id, v) {
      final at = (v as num).toInt();
      if (at < oldest) return;
      final known = deleted[id];
      if (known == null || at > known) deleted[id] = at;
    });
  }

  Map<String, dynamic> entities(String key) {
    final out = <String, dynamic>{};
    final l = _map(local[key]);
    final r = _map(remote[key]);
    for (final id in {...l.keys, ...r.keys}) {
      final a = l[id] as Map?;
      final b = r[id] as Map?;
      // À égalité, la version locale l'emporte.
      final Map winner;
      if (a == null) {
        winner = b!;
      } else if (b == null) {
        winner = a;
      } else {
        winner = _stamp(b) > _stamp(a) ? b : a;
      }
      final del = deleted[id];
      if (del != null && del >= _stamp(winner)) continue;
      out[id] = Map<String, dynamic>.from(winner);
    }
    return out;
  }

  // Chaque appareil fait foi pour son propre compteur.
  final logs = <String, dynamic>{};
  final lLogs = _map(local['logs']);
  final rLogs = _map(remote['logs']);
  for (final device in {...lLogs.keys, ...rLogs.keys}) {
    final own = device == deviceId;
    final src = own ? lLogs[device] : (rLogs[device] ?? lLogs[device]);
    final m = Map<String, dynamic>.from(_map(src));
    if (m.isNotEmpty) logs[device] = m;
  }

  final lPaceAt = (local['paceAt'] as num?)?.toInt() ?? 0;
  final rPaceAt = (remote['paceAt'] as num?)?.toInt() ?? 0;
  final paceFromRemote = rPaceAt > lPaceAt && remote['pace'] != null;

  return {
    'subjects': entities('subjects'),
    'topics': entities('topics'),
    'deleted': deleted,
    'logs': logs,
    'pace': paceFromRemote ? remote['pace'] : local['pace'],
    'paceAt': paceFromRemote ? rPaceAt : lPaceAt,
  };
}

/// Encodage canonique (clés triées) pour comparer deux états, quel que soit
/// l'ordre des clés renvoyé par la base.
String canonical(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _sorted(v[k])};
  }
  if (v is List) return v.map(_sorted).toList();
  // Un double entier (3.0) et un int (3) doivent être égaux.
  if (v is double && v == v.roundToDouble() && v.abs() < 1e15) return v.toInt();
  return v;
}

int _stamp(Map m) => (m['u'] as num?)?.toInt() ?? 0;

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.map((k, v) => MapEntry('$k', v)) : <String, dynamic>{};
