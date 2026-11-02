import 'package:flutter/material.dart';

import '../logic/dates.dart';
import '../logic/format.dart';

/// Marques d'un jour du calendrier.
class DayMarks {
  const DayMarks({this.colors = const [], this.exam = false});

  /// Couleurs des matières concernées (3 au plus sont affichées).
  final List<Color> colors;
  final bool exam;
}

/// Calendrier mensuel : un point par matière révisée ou à réviser, un drapeau
/// les jours d'examen. Toucher un jour le sélectionne.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.selected,
    required this.today,
    required this.marksFor,
    required this.onSelect,
    required this.onMonthChanged,
  });

  /// N'importe quel jour du mois affiché.
  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final DayMarks Function(DateTime day) marksFor;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onMonthChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                capitalize(formatMonthYear(first)),
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Mois précédent',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () =>
                  onMonthChanged(DateTime(month.year, month.month - 1, 1)),
            ),
            IconButton(
              tooltip: 'Mois suivant',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () =>
                  onMonthChanged(DateTime(month.year, month.month + 1, 1)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final d in weekdayInitials)
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Glisser vers la gauche ou la droite change de mois ; la grille
        // arrive du côté du geste.
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() < 250) return;
            onMonthChanged(DateTime(month.year, month.month + (v < 0 ? 1 : -1), 1));
          },
          child: _MonthSwitcher(
            month: first,
            child: Column(
              key: ValueKey(first),
              children: [
                for (var r = 0; r < rows; r++)
                  Row(
                    children: [
                      for (var c = 0; c < 7; c++)
                        Expanded(
                          child: _buildDay(context, r * 7 + c - leading + 1, daysInMonth),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDay(BuildContext context, int dayNumber, int daysInMonth) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 52);
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final day = DateTime(month.year, month.month, dayNumber);
    final isSelected = day == dateOnly(selected);
    final isToday = day == today;
    final isPast = day.isBefore(today);
    final marks = marksFor(day);

    final numberColor = isSelected
        ? scheme.onPrimary
        : isPast
            ? scheme.onSurfaceVariant
            : scheme.onSurface;

    return SizedBox(
      height: 52,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onSelect(day),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutBack,
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? scheme.primary : null,
                shape: BoxShape.circle,
                border: isToday && !isSelected
                    ? Border.all(color: scheme.primary, width: 2)
                    : null,
              ),
              child: Text(
                '$dayNumber',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: numberColor,
                  fontWeight: isToday || isSelected
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (marks.exam)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Icon(
                        Icons.flag_rounded,
                        size: 9,
                        color: scheme.tertiary,
                      ),
                    ),
                  for (final c in marks.colors.take(3))
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: isPast ? c.withValues(alpha: 0.5) : c,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fait glisser la grille du mois dans le sens du changement de mois.
class _MonthSwitcher extends StatefulWidget {
  const _MonthSwitcher({required this.month, required this.child});

  final DateTime month;
  final Widget child;

  @override
  State<_MonthSwitcher> createState() => _MonthSwitcherState();
}

class _MonthSwitcherState extends State<_MonthSwitcher> {
  double _dir = 1;

  @override
  void didUpdateWidget(_MonthSwitcher old) {
    super.didUpdateWidget(old);
    if (old.month != widget.month) {
      _dir = widget.month.isAfter(old.month) ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, anim) {
          final incoming = child.key == ValueKey(widget.month);
          final from = Offset((incoming ? 0.35 : -0.35) * _dir, 0);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(begin: from, end: Offset.zero).animate(anim),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}
