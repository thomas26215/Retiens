import 'package:flutter_test/flutter_test.dart';
import 'package:retiens/data/app_state.dart';
import 'package:retiens/data/sync_merge.dart';
import 'package:retiens/logic/dates.dart';
import 'package:retiens/logic/scheduler.dart';
import 'package:retiens/models/subject.dart';
import 'package:retiens/services/cloud_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _day = Duration.millisecondsPerDay;
const _now = 1000 * _day;

Map<String, dynamic> _topic(String id, int u, {String title = 'T'}) =>
    {'id': id, 'title': title, 'u': u};

CloudState _state({
  Map<String, dynamic> topics = const {},
  Map<String, dynamic> deleted = const {},
  Map<String, dynamic> logs = const {},
  String pace = 'normal',
  int paceAt = 0,
}) =>
    {
      'subjects': <String, dynamic>{},
      'topics': topics,
      'deleted': deleted,
      'logs': logs,
      'pace': pace,
      'paceAt': paceAt,
    };

Future<AppState> _device(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  return AppState.load();
}

void main() {
  group('fusion', () {
    test('élément par élément, la version la plus récente l\'emporte', () {
      final local = _state(topics: {
        'a': _topic('a', 10, title: 'A local'),
        'b': _topic('b', 30, title: 'B local'),
        'c': _topic('c', 5),
      });
      final remote = _state(topics: {
        'a': _topic('a', 20, title: 'A distant'),
        'b': _topic('b', 25, title: 'B distant'),
        'd': _topic('d', 7),
      });
      final m = mergeCloud(local, remote, deviceId: 'x', now: _now);
      final topics = m['topics'] as Map;
      expect(topics.keys, unorderedEquals(['a', 'b', 'c', 'd']));
      expect(topics['a']['title'], 'A distant');
      expect(topics['b']['title'], 'B local');
    });

    test('une suppression l\'emporte sur les versions plus anciennes', () {
      const t = _now - _day;
      final local = _state(topics: {'a': _topic('a', t + 10), 'b': _topic('b', t + 50)});
      final remote = _state(deleted: {'a': t + 20, 'b': t + 40});
      final m = mergeCloud(local, remote, deviceId: 'x', now: _now);
      // a supprimé après sa dernière modification ; b modifié après.
      expect((m['topics'] as Map).keys, ['b']);
      expect(m['deleted'], {'a': t + 20, 'b': t + 40});
    });

    test('les vieilles suppressions sont oubliées', () {
      final m = mergeCloud(
        _state(deleted: {'old': _now - 200 * _day, 'new': _now - _day}),
        _state(),
        deviceId: 'x',
        now: _now,
      );
      expect((m['deleted'] as Map).keys, ['new']);
    });

    test('compteurs : chaque appareil fait foi pour le sien', () {
      final local = _state(logs: {
        'x': {'2026-10-23': 3},
        'y': {'2026-10-23': 1},
      });
      final remote = _state(logs: {
        'x': {'2026-10-23': 1},
        'y': {'2026-10-23': 2},
        'z': {'2026-10-22': 4},
      });
      final m = mergeCloud(local, remote, deviceId: 'x', now: _now);
      expect(m['logs'], {
        'x': {'2026-10-23': 3},
        'y': {'2026-10-23': 2},
        'z': {'2026-10-22': 4},
      });
    });

    test('le rythme le plus récemment choisi l\'emporte', () {
      final m = mergeCloud(
        _state(pace: 'soutenu', paceAt: 5),
        _state(pace: 'detendu', paceAt: 9),
        deviceId: 'x',
        now: _now,
      );
      expect(m['pace'], 'detendu');
      expect(m['paceAt'], 9);
    });

    test('comparaison indépendante de l\'ordre des clés et des 3.0', () {
      expect(canonical({'b': 1, 'a': 3.0}), canonical({'a': 3, 'b': 1}));
      expect(canonical({'a': 2.5}), isNot(canonical({'a': 2})));
    });
  });

  group('état local', () {
    test('modifications datées, suppressions enregistrées', () async {
      final app = await _device({});
      final s = app.addSubject('Maths', subjectPalette[0], null);
      final t = app.addTopic(subjectId: s.id, title: 'C1', studiedOn: app.today);
      expect(t.updatedAt, greaterThan(0));
      expect(s.updatedAt, greaterThan(0));

      final before = t.updatedAt;
      app.setThemeMode(app.themeMode); // ne touche pas aux sujets
      expect(t.updatedAt, before);

      app.deleteTopic(t.id);
      expect(app.deleted.keys, [t.id]);
    });

    test('deux appareils convergent, révisions additionnées', () async {
      final a = await _device({'retiens_device_id': 'A'});
      final s = a.addSubject('Maths', subjectPalette[0], null);
      final t = a.addTopic(
        subjectId: s.id,
        title: 'C1',
        studiedOn: addDays(a.today, -1),
      );
      final u = a.addTopic(
        subjectId: s.id,
        title: 'C2',
        studiedOn: addDays(a.today, -1),
      );
      a.review(t, Rating.good);

      // Le téléphone B se connecte au même compte (vide jusque-là).
      final b = await _device({'retiens_device_id': 'B'});
      final cloud = a.toCloud();
      b.applyCloud(mergeCloud(b.toCloud(), cloud, deviceId: 'B', now: _now));
      expect(b.topics.map((x) => x.title), ['C1', 'C2']);
      expect(b.reviewedToday, 1);

      // B révise C2 : A le reçoit, les compteurs s'additionnent.
      b.review(b.topicById(u.id)!, Rating.easy);
      a.applyCloud(mergeCloud(a.toCloud(), b.toCloud(), deviceId: 'A', now: _now));
      expect(a.reviewedToday, 2);
      expect(a.topicById(u.id)!.history.single.rating, Rating.easy);

      // A supprime C1 : B le perd à la synchronisation suivante.
      a.deleteTopic(t.id);
      b.applyCloud(mergeCloud(b.toCloud(), a.toCloud(), deviceId: 'B', now: _now));
      expect(b.topics.map((x) => x.title), ['C2']);
      // Le compteur de A n'a pas bougé : la révision de C1 reste comptée.
      expect(b.reviewedToday, 2);
    });

    test('annuler sur un appareil une révision faite sur un autre', () async {
      final a = await _device({'retiens_device_id': 'A'});
      final s = a.addSubject('Maths', subjectPalette[0], null);
      final t = a.addTopic(subjectId: s.id, title: 'C1', studiedOn: addDays(a.today, -1));
      a.review(t, Rating.good);

      final b = await _device({'retiens_device_id': 'B'});
      b.applyCloud(mergeCloud(b.toCloud(), a.toCloud(), deviceId: 'B', now: _now));
      expect(b.reviewedToday, 1);
      b.undoLastReview(b.topics.single);
      expect(b.reviewedToday, 0);
      expect(b.log[dateKey(b.today)], -1);

      a.applyCloud(mergeCloud(a.toCloud(), b.toCloud(), deviceId: 'A', now: _now));
      expect(a.reviewedToday, 0);
      expect(a.isDue(a.topics.single), isTrue);
    });

    test('le compteur des autres appareils survit au redémarrage', () async {
      final a = await _device({'retiens_device_id': 'A'});
      a.otherLogs['B'] = {dateKey(a.today): 2};
      a.setThemeMode(a.themeMode);
      await Future<void>.delayed(Duration.zero);
      final again = await AppState.load();
      expect(again.reviewedToday, 2);
    });

    test('sauvegarde manuelle : compteurs de tous les appareils', () async {
      final a = await _device({'retiens_device_id': 'A'});
      a.log[dateKey(a.today)] = 1;
      a.otherLogs['B'] = {dateKey(a.today): 2};
      final other = await _device({'retiens_device_id': 'C'});
      expect(await other.importJson(a.exportJson()), isTrue);
      expect(other.reviewedToday, 3);
      expect(other.otherLogs, isEmpty);
    });
  });

  test('messages d\'erreur de connexion en français', () {
    expect(
      CloudSync.authMessage(
        'internal-error',
        'An internal error has occurred. [ CONFIGURATION_NOT_FOUND ]',
      ),
      contains('pas activée dans la console'),
    );
    expect(CloudSync.authMessage('email-already-in-use'), contains('existe déjà'));
    expect(CloudSync.authMessage('bizarre'), 'Erreur de connexion (bizarre).');
  });
}
