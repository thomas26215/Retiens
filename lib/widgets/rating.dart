import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../logic/dates.dart';
import '../logic/format.dart';
import '../logic/scheduler.dart';
import '../models/topic.dart';
import '../theme.dart';
import 'celebrations.dart';
import 'motion.dart';

/// Note choisie et centre du bouton touché (pour y faire partir l'éclat).
typedef RatedCallback = void Function(Rating rating, Offset? origin);

/// Les quatre notes en grille 2 × 2, chacune avec la date du rappel qu'elle
/// donnerait. Les boutons arrivent en cascade.
class RatingButtons extends StatelessWidget {
  const RatingButtons({super.key, required this.topic, required this.onRated});

  final Topic topic;
  final RatedCallback onRated;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final preview = app.previewDue(topic);
    final exam = app.examOf(topic);
    final eve = exam == null ? null : addDays(exam, -1);

    String when(DateTime? d) {
      if (d == null) return 'plus de rappel';
      if (d == eve) return "veille de l'examen";
      return formatRelativeDay(d, app.today);
    }

    Widget button(Rating r) => Expanded(
          child: FadeSlideIn(
            delay: stagger(r.index, stepMs: 55),
            scale: 0.85,
            offset: 10,
            child: _RatingButton(
              rating: r,
              next: when(preview[r]),
              onTap: (origin) => onRated(r, origin),
            ),
          ),
        );

    return Column(
      children: [
        Row(children: [button(Rating.again), const SizedBox(width: 10), button(Rating.hard)]),
        const SizedBox(height: 10),
        Row(children: [button(Rating.good), const SizedBox(width: 10), button(Rating.easy)]),
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.rating,
    required this.next,
    required this.onTap,
  });

  final Rating rating;
  final String next;
  final ValueChanged<Offset?> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = ratingColor(context, rating);
    return Pressable(
      scale: 0.93,
      child: Material(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(centerOf(context)),
        splashColor: color.withValues(alpha: 0.25),
        highlightColor: color.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(ratingIcon(rating), color: color, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rating.label, style: theme.textTheme.titleSmall),
                    Text(
                      next,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Demande comment s'est passée la révision. `null` si fermé sans noter.
Future<Rating?> showRatingSheet(BuildContext context, Topic topic) {
  return showModalBottomSheet<Rating>(
    context: context,
    useSafeArea: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Comment ça s\'est passé ?', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              topic.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            RatingButtons(
              topic: topic,
              onRated: (r, _) => Navigator.pop(ctx, r),
            ),
            const SizedBox(height: 14),
            Text(
              'Plus c\'était facile, plus le prochain rappel est loin.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Répartition des notes : barre empilée (segments séparés) puis une ligne
/// par note avec icône, libellé, nombre et pourcentage.
class RatingBreakdown extends StatelessWidget {
  const RatingBreakdown({super.key, required this.counts});

  final Map<Rating, int> counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return Text(
        'Note tes révisions pour voir ici comment elles se passent.',
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    final present = Rating.values.where((r) => counts[r]! > 0).toList();
    int pct(int n) => (n * 100 / total).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // La barre se déroule de gauche à droite.
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: motionAllowed(context) ? 900 : 0),
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: v,
              child: child,
            ),
          ),
          child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < present.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: counts[present[i]]!,
                    child: Tooltip(
                      message: '${present[i].label} : ${counts[present[i]]}',
                      child: ColoredBox(color: ratingColor(context, present[i])),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        ),
        const SizedBox(height: 14),
        for (final r in Rating.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(ratingIcon(r), size: 20, color: ratingColor(context, r)),
                const SizedBox(width: 10),
                Expanded(child: Text(r.label, style: theme.textTheme.bodyMedium)),
                Text(
                  '${counts[r]} · ${pct(counts[r]!)} %',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Pastille d'une note passée : icône colorée + libellé.
class RatingChip extends StatelessWidget {
  const RatingChip({super.key, required this.rating});

  final Rating rating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ratingColor(context, rating);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ratingIcon(rating), size: 16, color: color),
        const SizedBox(width: 4),
        Text(rating.label, style: theme.textTheme.labelMedium),
      ],
    );
  }
}
