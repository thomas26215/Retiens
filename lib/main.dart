import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_scope.dart';
import 'data/app_state.dart';
import 'screens/root_screen.dart';
import 'services/cloud_sync.dart';
import 'services/fx.dart';
import 'services/home_widgets.dart';
import 'services/notifications.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  final state = await AppState.load();
  state.applyFeedbackSettings();
  // Les sons et le compte se chargent pendant que l'app s'affiche.
  unawaited(Fx.instance.init());
  unawaited(CloudSync.instance.init(state));
  HomeWidgets.instance.init(state);
  await state.applyReminders();
  runApp(RetiensApp(state: state));
}

class RetiensApp extends StatefulWidget {
  const RetiensApp({super.key, required this.state});

  final AppState state;

  @override
  State<RetiensApp> createState() => _RetiensAppState();
}

class _RetiensAppState extends State<RetiensApp> with WidgetsBindingObserver {
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    super.dispose();
  }

  // La date a pu changer pendant que l'app était en arrière-plan.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.state.refresh();
      _scheduleMidnight();
    }
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _midnight = Timer(next.difference(now), () {
      widget.state.refresh();
      _scheduleMidnight();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'Retiens',
          debugShowCheckedModeBanner: false,
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: _light,
          darkTheme: _dark,
          themeMode: state.themeMode,
          home: const RootScreen(),
        ),
      ),
    );
  }
}

final _light = buildTheme(Brightness.light);
final _dark = buildTheme(Brightness.dark);
