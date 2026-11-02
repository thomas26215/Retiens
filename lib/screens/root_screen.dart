import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../services/fx.dart';
import '../services/home_widgets.dart';
import '../widgets/motion.dart';
import 'planning_tab.dart';
import 'progress_tab.dart';
import 'routes.dart';
import 'subject_sheet.dart';
import 'subjects_tab.dart';
import 'today_tab.dart';

/// Écran principal : quatre onglets (Aujourd'hui, Planning, Matières, Progrès).
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _index = 0;
  StreamSubscription<Uri?>? _widgetClicks;

  @override
  void initState() {
    super.initState();
    final widgets = HomeWidgets.instance;
    _widgetClicks = widgets.clicks.listen(_openFromWidget);
    widgets.initialClick().then(_openFromWidget);
  }

  @override
  void dispose() {
    _widgetClicks?.cancel();
    super.dispose();
  }

  /// Ouverture depuis un widget : retiens://today, retiens://add,
  /// retiens://topic?id=…
  void _openFromWidget(Uri? uri) {
    if (uri == null || !mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _index = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = AppScope.of(context);
      switch (uri.host) {
        case 'add':
          startAddTopic(context);
        case 'topic':
          final id = uri.queryParameters['id'];
          if (id != null && app.topicById(id) != null) openTopic(context, id);
      }
    });
  }

  // Matières et Progrès rejouent leurs animations à chaque visite.
  int _visits = 0;

  void _go(int index) {
    if (index == _index) return;
    Fx.instance.select();
    setState(() {
      _index = index;
      _visits++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final due = app.dueCount();

    Widget? fab;
    if (_index == 2) {
      fab = FloatingActionButton.extended(
        key: const ValueKey('subject'),
        heroTag: 'subject',
        onPressed: () {
          Fx.instance.tap();
          showSubjectSheet(context);
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Matière'),
      );
    } else if (_index != 3 && app.subjects.isNotEmpty) {
      fab = FloatingActionButton.extended(
        key: const ValueKey('topic'),
        heroTag: 'topic',
        onPressed: () {
          Fx.instance.tap();
          startAddTopic(context);
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Sujet étudié'),
      );
    }

    Widget badge(IconData icon) => Badge(
          isLabelVisible: due > 0,
          label: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
              child: child,
            ),
            child: Text('$due', key: ValueKey(due)),
          ),
          child: Icon(icon),
        );

    return Scaffold(
      body: FadeIndexedStack(
        index: _index,
        children: [
          TodayTab(onOpenTab: _go),
          const PlanningTab(),
          SubjectsTab(key: ValueKey('s${_index == 2 ? _visits : 0}')),
          ProgressTab(key: ValueKey('p${_index == 3 ? _visits : 0}')),
        ],
      ),
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: fab != null ? Pressable(key: fab.key, child: fab) : null,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: [
          NavigationDestination(
            icon: badge(Icons.today_outlined),
            selectedIcon: badge(Icons.today_rounded),
            label: "Aujourd'hui",
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Planning',
          ),
          const NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories_rounded),
            label: 'Matières',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Progrès',
          ),
        ],
      ),
    );
  }
}
