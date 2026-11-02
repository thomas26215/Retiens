import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../logic/dates.dart';
import '../logic/format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../logic/scheduler.dart';
import '../widgets/heatmap.dart';
import '../widgets/motion.dart';
import '../widgets/rating.dart';
import 'routes.dart';

class ProgressTab extends StatelessWidget {
  const ProgressTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = app.today;
    final last30 = app.reviewsBetween(addDays(today, -29), today);
    final total = app.topics.length;
    final ratings = app.ratingsBetween(addDays(today, -29), today);
    final rated = ratings.values.fold<int>(0, (a, b) => a + b);
    final success = rated == 0
        ? 0
        : ((ratings[Rating.good]! + ratings[Rating.easy]!) * 100 / rated).round();

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: TabHeader(title: 'Progrès', actions: [SettingsButton()]),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          index: 0,
                          icon: Icons.local_fire_department_rounded,
                          iconColor: app.streak > 0 ? streakColor : null,
                          flicker: app.streak > 0,
                          value: app.streak,
                          label: app.streak > 1 ? 'jours de suite' : 'jour de suite',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatTile(
                          index: 1,
                          icon: Icons.emoji_events_rounded,
                          value: app.bestStreak,
                          label: 'meilleure série',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          index: 2,
                          icon: Icons.replay_rounded,
                          value: app.totalReviews,
                          label: app.totalReviews > 1
                              ? 'révisions au total'
                              : 'révision au total',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatTile(
                          index: 3,
                          icon: Icons.verified_rounded,
                          value: app.solidCount,
                          format: (n) => '$n/$total',
                          label: 'sujets solides',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: _FadeSliver(
              delay: 220,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Activité', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${plural(last30, 'révision')} ces 30 derniers jours',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ActivityHeatmap(countFor: app.reviewsOn, today: today),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: _FadeSliver(
              delay: 300,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ressenti', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        rated == 0
                            ? 'Notes des révisions, 30 derniers jours'
                            : '$success % de révisions réussies (bien ou facile) '
                                'ces 30 derniers jours',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      RatingBreakdown(counts: ratings),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (app.subjects.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: _FadeSliver(
                delay: 380,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Par matière', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          'Maîtrise : solidité moyenne du souvenir des sujets',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 14),
                        for (final s in app.subjects)
                          Builder(builder: (context) {
                            final ratio = app.subjectMastery(s.id);
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => openSubject(context, s.id),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            s.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleSmall,
                                          ),
                                        ),
                                        Text(
                                          '${(ratio * 100).round()} %',
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ProgressBar(
                                      value: ratio,
                                      color: subjectColor(context, s),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

/// Bloc qui apparaît en fondu, dans une liste de slivers.
class _FadeSliver extends StatelessWidget {
  const _FadeSliver({required this.delay, required this.child});

  final int delay;
  final Widget child;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: FadeSlideIn(delay: Duration(milliseconds: delay), child: child),
      );
}

/// Chiffre clé : icône, nombre qui défile, libellé.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.index,
    required this.icon,
    required this.value,
    required this.label,
    this.format,
    this.iconColor,
    this.flicker = false,
  });

  final int index;
  final IconData icon;
  final int value;
  final String label;
  final String Function(int)? format;
  final Color? iconColor;
  final bool flicker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FadeSlideIn(
      delay: stagger(index, stepMs: 60),
      scale: 0.9,
      child: Pressable(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flicker(
                  active: flicker,
                  child: Icon(icon, color: iconColor ?? scheme.primary, size: 22),
                ),
                const SizedBox(height: 10),
                AnimatedCount(
                  value: value,
                  format: format,
                  duration: Duration(milliseconds: 700 + 120 * index),
                  style: theme.textTheme.headlineMedium,
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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
