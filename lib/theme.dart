import 'package:flutter/material.dart';

import 'logic/scheduler.dart';
import 'models/subject.dart';

const brandColor = Color(0xFF2A78D6);

/// Couleurs d'état (toujours accompagnées d'une icône et d'un libellé).
const goodColor = Color(0xFF0CA30C);
const criticalColor = Color(0xFFD03B3B);

/// Flamme de la série et trophée de fin de journée.
const streakColor = Color(0xFFEB6834);
const trophyColor = Color(0xFFE09A00);

/// Rampe séquentielle (bleu) de la carte d'activité, du plus faible au plus
/// fort. En sombre, l'ancre s'inverse : le plus faible se rapproche du fond.
const _heatLight = [Color(0xFFB7D3F6), Color(0xFF6DA7EC), Color(0xFF2A78D6), Color(0xFF184F95)];
const _heatDark = [Color(0xFF104281), Color(0xFF256ABF), Color(0xFF5598E7), Color(0xFF9EC5F4)];

List<Color> heatRamp(Brightness b) =>
    b == Brightness.dark ? _heatDark : _heatLight;

/// Couleurs des notes (Oublié, Difficile, Bien, Facile), validées pour le
/// daltonisme dans cet ordre ; toujours accompagnées d'une icône et d'un libellé.
const _ratingLight = [Color(0xFFE34948), Color(0xFFEDA100), Color(0xFF1BAF7A), Color(0xFF2A78D6)];
const _ratingDark = [Color(0xFFE34948), Color(0xFFC98500), Color(0xFF199E70), Color(0xFF3987E5)];

Color ratingColor(BuildContext context, Rating r) =>
    (Theme.of(context).brightness == Brightness.dark
        ? _ratingDark
        : _ratingLight)[r.index];

IconData ratingIcon(Rating r) => switch (r) {
      Rating.again => Icons.sentiment_very_dissatisfied_rounded,
      Rating.hard => Icons.sentiment_neutral_rounded,
      Rating.good => Icons.sentiment_satisfied_rounded,
      Rating.easy => Icons.sentiment_very_satisfied_rounded,
    };

ThemeData buildTheme(Brightness brightness) {
  // « fidelity » garde le bleu vif de la marque au lieu d'un bleu grisé.
  final scheme = ColorScheme.fromSeed(
    seedColor: brandColor,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Manrope',
  );
  final t = base.textTheme;
  final text = t.copyWith(
    displaySmall: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
    headlineLarge: t.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
    headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
    headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
    titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    labelMedium: t.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    bodyMedium: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
    bodySmall: t.bodySmall?.copyWith(fontWeight: FontWeight.w500),
  );

  final radius = BorderRadius.circular(16);
  // Bordure « soulignée » invisible : le libellé reste à l'intérieur du champ.
  final fieldBorder = UnderlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide.none,
  );

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.primaryContainer,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelMedium?.copyWith(
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder,
      errorBorder: fieldBorder,
      focusedErrorBorder: fieldBorder,
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: text.labelLarge),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      extendedTextStyle: text.labelLarge?.copyWith(fontSize: 15),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: text.labelLarge,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.titleMedium?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(textStyle: text.labelLarge),
    ),
    // Android 14+ : l'écran suit le geste retour (aperçu de la page d'avant).
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
  );
}

/// Couleur d'affichage d'une matière, ajustée au thème courant.
Color subjectColor(BuildContext context, Subject? s) {
  final scheme = Theme.of(context).colorScheme;
  if (s == null) return scheme.outline;
  final i = subjectPalette.indexOf(s.colorValue);
  if (i >= 0 && scheme.brightness == Brightness.dark) {
    return Color(subjectPaletteDark[i]);
  }
  return Color(s.colorValue);
}

/// Texte lisible (noir ou blanc) posé sur [background].
Color onColor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : const Color(0xFF111111);
