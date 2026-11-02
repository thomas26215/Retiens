import 'package:flutter/widgets.dart';

import 'data/app_state.dart';

/// Expose l'[AppState] à tout l'arbre de widgets et reconstruit les
/// dépendants à chaque changement.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope introuvable dans l\'arbre de widgets');
    return scope!.notifier!;
  }
}
