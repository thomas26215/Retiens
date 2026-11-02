import 'package:flutter_test/flutter_test.dart';
import 'package:retiens/data/app_state.dart';
import 'package:retiens/logic/dates.dart';
import 'package:retiens/logic/scheduler.dart';
import 'package:retiens/models/subject.dart';
import 'package:retiens/services/home_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('données des widgets : 14 jours, sujets cumulés, 4 lignes max', () async {
    SharedPreferences.setMockInitialValues({});
    final app = await AppState.load();
    final today = app.today;
    final s = app.addSubject('Maths', subjectPalette[3], null);
    // Deux sujets à revoir aujourd'hui (dont un en retard), un demain.
    for (final (title, days) in [('A', -5), ('B', -1), ('C', 0)]) {
      app.addTopic(subjectId: s.id, title: title, studiedOn: addDays(today, days));
    }
    for (var i = 0; i < 4; i++) {
      app.addTopic(subjectId: s.id, title: 'D$i', studiedOn: addDays(today, 1));
    }

    final data = buildWidgetData(app);
    final days = data['days'] as Map<String, dynamic>;
    expect(days.length, 14);

    final d0 = days[dateKey(today)] as Map;
    expect(d0['n'], 2);
    expect([for (final i in d0['items'] as List) i['t']], ['A', 'B']);
    expect((d0['items'] as List).first['c'], subjectPalette[3]);

    // Demain : A et B toujours là (pas revus), plus C.
    final d1 = days[dateKey(addDays(today, 1))] as Map;
    expect(d1['n'], 3);
    // Après-demain : 7 sujets, la liste s'arrête à 4.
    final d2 = days[dateKey(addDays(today, 2))] as Map;
    expect(d2['n'], 7);
    expect((d2['items'] as List).length, 4);

    expect(data['done'], 0);
    expect(data['streak'], 0);

    app.review(app.topics.first, Rating.good);
    final after = buildWidgetData(app);
    expect(after['done'], 1);
    expect(after['streak'], 1);
    expect(after['streakDay'], dateKey(today));
    expect((after['days'] as Map)[dateKey(today)]['n'], 1);
  });
}
