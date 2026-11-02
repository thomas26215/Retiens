import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/app_state.dart';
import '../logic/dates.dart';
import '../logic/format.dart';
import '../models/subject.dart';
import '../models/topic.dart';
import '../services/cloud_sync.dart';
import '../services/fx.dart';
import '../theme.dart';
import '../widgets/animated_topics.dart';
import '../widgets/celebrations.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/sync_badge.dart';
import '../widgets/topic_card.dart';
import 'routes.dart';
import 'subject_sheet.dart';

class TodayTab extends StatelessWidget {
  const TodayTab({super.key, required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final due = app.dueTopics();
    final reviewed = app.topicsReviewedToday;
    final upcoming = app
        .upcoming(limit: 4 + reviewed.length)
        .where((t) => !reviewed.contains(t))
        .take(4)
        .toList();
    final exams = app.upcomingExams
        .where((s) => daysBetween(app.today, s.examDate!) <= 45)
        .take(3)
        .toList();

    Widget list(List<Topic> topics, {bool lastReview = false, bool cascade = false}) =>
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: AnimatedTopicSliver(
            topics: topics,
            cascade: cascade,
            itemBuilder: (context, t) =>
                TopicCard(topic: t, showLastReview: lastReview),
          ),
        );

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: FadeSlideIn(
              child: TabHeader(
                overline: capitalize(formatLongDay(app.today)),
                title: "Aujourd'hui",
                actions: [
                  SyncBadge(onTap: () => openSettings(context)),
                  const SettingsButton(),
                ],
              ),
            ),
          ),
          if (app.subjects.isEmpty)
            const SliverToBoxAdapter(child: _Welcome())
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: FadeSlideIn(
                  delay: const Duration(milliseconds: 60),
                  scale: 0.96,
                  child: _HeroCard(app: app),
                ),
              ),
            ),
            if (exams.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: FadeSlideIn(
                    delay: const Duration(milliseconds: 120),
                    child: _ExamCard(exams: exams),
                  ),
                ),
              ),
            _SliverHeader(
              visible: due.isNotEmpty,
              child: SectionHeader(
                'À revoir',
                trailing: Text(
                  'Glisse → noter · ← demain',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            list(due, cascade: true),
            _SliverHeader(
              visible: reviewed.isNotEmpty,
              child: const SectionHeader(
                "Revus aujourd'hui",
                padding: EdgeInsets.fromLTRB(20, 24, 20, 10),
              ),
            ),
            list(reviewed, lastReview: true),
            _SliverHeader(
              visible: upcoming.isNotEmpty,
              child: SectionHeader(
                'Prochainement',
                trailing: TextButton(
                  onPressed: () => onOpenTab(1),
                  child: const Text('Planning'),
                ),
                padding: const EdgeInsets.fromLTRB(20, 20, 8, 4),
              ),
            ),
            list(upcoming, cascade: true),
            if (app.topics.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.edit_note_rounded,
                  title: 'Ajoute ce que tu as étudié',
                  message: 'Une leçon, un cours, une fiche : Retiens te le '
                      'rappellera au bon moment, dès demain.',
                  action: FilledButton.icon(
                    onPressed: () => startAddTopic(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Ajouter un sujet'),
                  ),
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 112)),
        ],
      ),
    );
  }
}

/// En-tête de section qui apparaît et disparaît en douceur.
class _SliverHeader extends StatelessWidget {
  const _SliverHeader({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, anim) => SizeTransition(
          sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeInOutCubic),
          alignment: Alignment.topCenter,
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: visible
            ? KeyedSubtree(key: const ValueKey(true), child: child)
            : const SizedBox(key: ValueKey(false), width: double.infinity),
      ),
    );
  }
}

/// Résumé du jour : anneau de progression, série, révisions faites. Passe au
/// vert, trophée à l'appui, quand tout est revu.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dueCount = app.dueCount();
    final done = app.reviewedToday;
    final total = done + dueCount;
    final streak = app.streak;
    final allDone = dueCount == 0 && done > 0;

    // En sombre, des tons conteneurs pour ne pas éblouir.
    final isDark = theme.brightness == Brightness.dark;
    final fg = isDark ? scheme.onPrimaryContainer : scheme.onPrimary;
    final Color bgStart;
    final Color bgEnd;
    if (allDone) {
      // Même logique que le bleu : foncé + texte clair en clair, tons
      // conteneurs clairs + texte foncé en sombre.
      bgStart = isDark ? const Color(0xFF5CCB98) : const Color(0xFF0F7A50);
      bgEnd = isDark ? const Color(0xFF4DB5B9) : const Color(0xFF0B6A73);
    } else {
      bgStart = isDark ? scheme.primaryContainer : scheme.primary;
      // Même bleu décalé vers le violet, pour un dégradé sans teinte boueuse.
      final hsl = HSLColor.fromColor(bgStart);
      bgEnd = hsl.withHue((hsl.hue + 30) % 360).toColor();
    }

    final String headline;
    final String sub;
    if (dueCount > 0) {
      headline = '${plural(dueCount, 'sujet')} à revoir';
      sub = done > 0
          ? 'Déjà ${plural(done, 'révision')} aujourd\'hui, continue !'
          : 'Quelques minutes suffisent pour chacun.';
    } else if (done > 0) {
      headline = 'Journée bouclée !';
      final next = app.upcoming(limit: 1);
      sub = next.isEmpty
          ? 'Bravo, tout est revu.'
          : 'Bravo. Prochain rappel ${formatRelativeDay(next.first.due!, app.today)}.';
    } else {
      headline = 'Rien à revoir';
      final next = app.upcoming(limit: 1);
      sub = next.isEmpty
          ? 'Ajoute ce que tu étudies pour planifier tes révisions.'
          : 'Prochain rappel ${formatRelativeDay(next.first.due!, app.today)}.';
    }

    final Widget center;
    if (allDone) {
      center = Icon(Icons.emoji_events_rounded,
          key: const ValueKey('trophy'), color: fg, size: 36);
    } else if (total == 0) {
      center = Icon(Icons.done_all_rounded,
          key: const ValueKey('none'), color: fg, size: 30);
    } else {
      center = Text(
        '$done/$total',
        key: ValueKey('$done/$total'),
        style: theme.textTheme.titleLarge?.copyWith(
          color: fg,
          fontWeight: FontWeight.w800,
        ),
      );
    }

    return Pressable(
      scale: 0.98,
      child: GestureDetector(
        // Petit bonus : toucher le trophée relance la fête.
        onTap: allDone ? () => celebrateDay(context, app) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [bgStart, bgEnd],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProgressRing(
                    value: total == 0 ? 1 : done / total,
                    color: fg,
                    trackColor: fg.withValues(alpha: 0.22),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 550),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: center,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, if (current != null) current],
                      ),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.25),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey(headline + sub),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headline,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            sub,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: fg.withValues(alpha: 0.88),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FlamePill(streak: streak, color: fg),
                  _HeroPill(
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: "${plural(done, 'révision')} aujourd'hui",
                    color: fg,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label, required this.color});

  final Widget icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme(data: IconThemeData(color: color, size: 16), child: icon),
          const SizedBox(width: 6),
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                label,
                key: ValueKey(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Série de jours : la flamme ondule tant que la série est vivante, et
/// crépite quand on la touche.
class _FlamePill extends StatelessWidget {
  const _FlamePill({required this.streak, required this.color});

  final int streak;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: streak == 0
          ? null
          : () {
              Fx.instance.streak();
              final at = centerOf(context);
              if (at != null) {
                showBurst(
                  context,
                  center: at,
                  icon: Icons.local_fire_department_rounded,
                  color: streakColor,
                  label: plural(streak, 'jour'),
                  sparks: 14,
                );
              }
            },
      child: _HeroPill(
        icon: Flicker(
          active: streak > 0,
          child: const Icon(Icons.local_fire_department_rounded, size: 16),
        ),
        label: streak == 0 ? 'Commence une série' : '${plural(streak, 'jour')} de suite',
        color: color,
      ),
    );
  }
}

/// Examens à venir (45 prochains jours).
class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exams});

  final List<Subject> exams;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Column(
        children: [
          for (final s in exams)
            ListTile(
              onTap: () => openSubject(context, s.id),
              leading: SubjectAvatar(subject: s, size: 36),
              title: Text('Examen · ${s.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(capitalize(formatLongDay(s.examDate!))),
              trailing: _Countdown(days: daysBetween(app.today, s.examDate!)),
              titleTextStyle: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurface),
            ),
        ],
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        days == 0 ? "Aujourd'hui" : 'J-$days',
        style: theme.textTheme.labelLarge?.copyWith(
          color: scheme.onTertiaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Premier lancement : explication en trois étapes.
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget stepRow(int n, String title, String text) => FadeSlideIn(
          delay: Duration(milliseconds: 250 + 120 * n),
          child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$n',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FadeSlideIn(
                scale: 0.5,
                offset: 0,
                duration: const Duration(milliseconds: 700),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.bookmark_added_rounded,
                    color: scheme.onPrimary,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Bienvenue dans Retiens', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Tu étudies une leçon, Retiens te la rappelle juste avant '
                "que tu ne l'oublies. Quelques révisions bien placées valent "
                'mieux que dix à la veille de l\'examen.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              stepRow(1, 'Crée une matière', 'Ex. « Ingénierie des exigences », avec sa date d\'examen si tu la connais.'),
              stepRow(2, 'Ajoute ce que tu viens d\'étudier', 'Une leçon, une fiche, rangée par chapitre si tu veux.'),
              stepRow(3, 'Revois-le et dis comment ça s\'est passé', 'Oublié, difficile, bien ou facile : le prochain rappel s\'adapte à ta mémoire.'),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Fx.instance.tap();
                    showSubjectSheet(context);
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Créer ma première matière'),
                ),
              ),
              // Nouveau téléphone : retrouver ses données.
              ListenableBuilder(
                listenable: CloudSync.instance,
                builder: (context, _) {
                  final sync = CloudSync.instance;
                  if (!sync.available || sync.signedIn) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () {
                          Fx.instance.tap();
                          openAccount(context, create: false);
                        },
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text("J'ai déjà un compte"),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
