import 'package:flutter/material.dart';

import '../logic/dates.dart';
import '../logic/format.dart';
import '../theme.dart';
import 'motion.dart';

/// Carte d'activité : une case par jour (colonnes = semaines, lignes = jours),
/// teinte selon le nombre de révisions. Toucher une case affiche le détail.
class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({
    super.key,
    required this.countFor,
    required this.today,
    this.weeks = 17,
  });

  final int Function(DateTime day) countFor;
  final DateTime today;
  final int weeks;

  static const _gap = 3.0;
  static const _labelWidth = 18.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ramp = heatRamp(theme.brightness);
    final empty = scheme.surfaceContainerHighest;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final thisMonday = addDays(today, -(today.weekday - 1));
    final start = addDays(thisMonday, -7 * (weeks - 1));

    Color colorFor(int n) {
      if (n <= 0) return empty;
      if (n == 1) return ramp[0];
      if (n <= 3) return ramp[1];
      if (n <= 5) return ramp[2];
      return ramp[3];
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // -1 : marge contre les arrondis qui feraient déborder la ligne.
        final cell = ((constraints.maxWidth - _labelWidth - 1) / weeks - _gap)
            .clamp(8.0, 20.0);
        final step = cell + _gap;

        // Libellés de mois au-dessus de la première semaine de chaque mois
        // (pas sur les deux dernières colonnes, faute de place).
        final monthLabels = <Widget>[];
        for (var w = 0; w < weeks - 2; w++) {
          final monday = addDays(start, 7 * w);
          final startsMonth = w == 0
              ? addDays(monday, 7).month == monday.month
              : addDays(monday, -7).month != monday.month;
          if (startsMonth) {
            monthLabels.add(Positioned(
              left: _labelWidth + w * step,
              child: Text(formatMonthShort(monday), style: labelStyle),
            ));
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 16,
              width: double.infinity,
              child: Stack(clipBehavior: Clip.none, children: monthLabels),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _labelWidth,
                  child: Column(
                    children: [
                      for (var d = 0; d < 7; d++)
                        SizedBox(
                          height: step,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              d.isEven && d < 6 ? weekdayInitials[d] : '',
                              style: labelStyle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Les semaines apparaissent une à une, de gauche à droite.
                for (var w = 0; w < weeks; w++)
                  FadeSlideIn(
                    delay: Duration(milliseconds: 250 + 22 * w),
                    duration: const Duration(milliseconds: 350),
                    offset: 8,
                    scale: 0.7,
                    child: Padding(
                      padding: const EdgeInsets.only(right: _gap),
                      child: Column(
                        children: [
                          for (var d = 0; d < 7; d++)
                            _cell(
                              context,
                              addDays(start, 7 * w + d),
                              cell,
                              colorFor,
                              scheme,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Moins', style: labelStyle),
                const SizedBox(width: 6),
                for (final c in [empty, ...ramp])
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                const SizedBox(width: 3),
                Text('Plus', style: labelStyle),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _cell(
    BuildContext context,
    DateTime day,
    double size,
    Color Function(int) colorFor,
    ColorScheme scheme,
  ) {
    final box = SizedBox(width: size, height: size);
    if (day.isAfter(today)) {
      return Padding(padding: const EdgeInsets.only(bottom: _gap), child: box);
    }
    final n = countFor(day);
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: Tooltip(
        message: '${n == 0 ? 'Aucune révision' : plural(n, 'révision')}'
            ' · ${formatShortDay(day)}',
        triggerMode: TooltipTriggerMode.tap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colorFor(n),
            borderRadius: BorderRadius.circular(3),
            border: day == today
                ? Border.all(color: scheme.onSurface, width: 1.5)
                : null,
          ),
        ),
      ),
    );
  }
}
