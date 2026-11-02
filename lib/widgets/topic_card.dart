import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/app_state.dart';
import '../logic/dates.dart';
import '../logic/format.dart';
import '../logic/scheduler.dart';
import '../models/topic.dart';
import '../screens/routes.dart';
import '../services/fx.dart';
import '../theme.dart';
import 'animated_topics.dart';
import 'celebrations.dart';
import 'common.dart';
import 'motion.dart';
import 'rating.dart';

/// Carte d'un sujet : matière, titre, solidité du souvenir et prochain rappel.
/// S'il est à revoir : boutons « Demain » / « Revu » (qui demande une note),
/// et balayage (vers la droite : noter, vers la gauche : demain).
class TopicCard extends StatelessWidget {
  const TopicCard({
    super.key,
    required this.topic,
    this.showSubject = true,
    this.swipeable = true,
    this.showLastReview = false,
  });

  final Topic topic;
  final bool showSubject;
  final bool swipeable;

  /// Affiche la note de la dernière révision et un bouton pour l'annuler.
  final bool showLastReview;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subject = app.subjectById(topic.subjectId);
    final color = subjectColor(context, subject);
    final isDue = app.isDue(topic);
    final canUndo =
        showLastReview && !isDue && app.canUndoLastReview(topic);
    final lastRating = topic.history.isEmpty ? null : topic.history.last.rating;

    final card = Pressable(
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openTopic(context, topic.id),
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, 14, isDue || canUndo ? 8 : 14, 14),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showSubject && subject != null)
                        Text(
                          [subject.name, if (app.chapterOf(topic) case final c?) c.name].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      Text(
                        topic.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Tooltip(
                            message: 'Souvenir : ${memoryLabels[topic.memory].toLowerCase()}',
                            child: MemoryMeter(level: topic.memory, color: color),
                          ),
                          const SizedBox(width: 10),
                          Flexible(child: TopicStatus(topic: topic)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isDue) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Revoir demain',
                    icon: const Icon(Icons.snooze_rounded),
                    color: scheme.onSurfaceVariant,
                    onPressed: () => postponeWithUndo(context, app, topic),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Revu',
                    icon: const Icon(Icons.check_rounded),
                    onPressed: () async {
                      Fx.instance.tap();
                      final r = await showRatingSheet(context, topic);
                      if (r != null && context.mounted) {
                        reviewWithUndo(context, app, topic, r);
                      }
                    },
                  ),
                ],
                if (canUndo) ...[
                  const SizedBox(width: 4),
                  if (lastRating != null)
                    Tooltip(
                      message: 'Noté « ${lastRating.label} »',
                      child: FadeSlideIn(
                        scale: 0.3,
                        offset: 0,
                        duration: const Duration(milliseconds: 600),
                        child: Icon(
                          ratingIcon(lastRating),
                          color: ratingColor(context, lastRating),
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Annuler la dernière révision',
                    icon: const Icon(Icons.undo_rounded),
                    color: scheme.onSurfaceVariant,
                    onPressed: () => undoLastReviewWithRedo(context, app, topic),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (!isDue || !swipeable) return card;
    return _Swipeable(topic: topic, app: app, child: card);
  }
}

/// Balayage d'une carte à revoir. Le fond réagit quand le geste est assez
/// long pour compter (petit son, vibration, icône qui grossit).
class _Swipeable extends StatefulWidget {
  const _Swipeable({required this.topic, required this.app, required this.child});

  final Topic topic;
  final AppState app;
  final Widget child;

  @override
  State<_Swipeable> createState() => _SwipeableState();
}

class _SwipeableState extends State<_Swipeable> {
  final _reached = ValueNotifier(false);

  @override
  void dispose() {
    _reached.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topic = widget.topic;
    final app = widget.app;
    return Dismissible(
      key: ValueKey('${topic.id}|${topic.due}|${topic.reviewCount}'),
      onUpdate: (d) {
        if (d.reached != d.previousReached) {
          _reached.value = d.reached;
          if (d.reached) Fx.instance.swipeArmed();
        }
      },
      background: _SwipeBackground(
        reached: _reached,
        alignment: Alignment.centerLeft,
        color: goodColor,
        foreground: Colors.white,
        icon: Icons.check_rounded,
        label: 'Revu',
      ),
      secondaryBackground: _SwipeBackground(
        reached: _reached,
        alignment: Alignment.centerRight,
        color: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
        icon: Icons.snooze_rounded,
        label: 'Demain',
      ),
      // La carte est déjà sortie de l'écran quand on arrive ici : l'action est
      // enregistrée tout de suite (son, éclat) et la liste referme l'espace.
      // Fermer la feuille de notation sans choisir ramène la carte.
      confirmDismiss: (direction) async {
        final origin = centerOf(context);
        if (direction == DismissDirection.endToStart) {
          pendingExits[topic.id] = TopicExit.swiped;
          postponeWithUndo(context, app, topic, origin: origin);
          return true;
        }
        final r = await showRatingSheet(context, topic);
        if (r == null || !context.mounted) {
          _reached.value = false;
          return false;
        }
        pendingExits[topic.id] = TopicExit.swiped;
        reviewWithUndo(context, app, topic, r, origin: origin);
        return true;
      },
      child: widget.child,
    );
  }
}

/// Ligne de statut : numéro de la révision et date du rappel.
class TopicStatus extends StatelessWidget {
  const TopicStatus({super.key, required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = app.today;
    final due = topic.due;
    final step = '${ordinal(topic.reviewCount + 1)} révision';

    final IconData icon;
    final Color iconColor;
    final String text;
    var strong = false;
    if (due == null) {
      icon = Icons.verified_rounded;
      iconColor = goodColor;
      text = 'Plus de rappel';
    } else if (!due.isAfter(today)) {
      final late = daysBetween(due, today);
      if (late > 0) {
        icon = Icons.schedule_rounded;
        iconColor = criticalColor;
        text = '$step · en retard de $late j';
        strong = true;
      } else {
        icon = Icons.bolt_rounded;
        iconColor = scheme.primary;
        text = "$step · aujourd'hui";
      }
    } else {
      icon = Icons.event_rounded;
      iconColor = scheme.onSurfaceVariant;
      text = '$step · ${formatRelativeDay(due, today)}';
    }

    // Le statut change en fondu (révision notée, annulée…).
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, if (current != null) current],
      ),
      child: Row(
        key: ValueKey(text),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: strong ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: strong ? FontWeight.w700 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.reached,
    required this.alignment,
    required this.color,
    required this.foreground,
    required this.icon,
    required this.label,
  });

  final ValueListenable<bool> reached;
  final Alignment alignment;
  final Color color;
  final Color foreground;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: reached,
      builder: (context, on, _) {
        final children = [
          AnimatedScale(
            scale: on ? 1.35 : 0.9,
            duration: const Duration(milliseconds: 260),
            curve: on ? Curves.elasticOut : Curves.easeOut,
            child: Icon(icon, color: foreground),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: foreground),
          ),
        ];
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: on ? color : Color.lerp(color, Colors.grey, 0.45),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: alignment,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: alignment == Alignment.centerLeft
                ? children
                : children.reversed.toList(),
          ),
        );
      },
    );
  }
}

/// Enregistre la révision notée [rating] avec son, éclat de couleur et
/// bandeau pour annuler. Célèbre la fin de la journée, un souvenir devenu
/// solide ou la série qui continue.
void reviewWithUndo(
  BuildContext context,
  AppState app,
  Topic topic,
  Rating rating, {
  Offset? origin,
}) {
  final at = origin ?? centerOf(context);
  final dueBefore = app.dueCount();
  final firstToday = app.reviewedToday == 0;
  final levelBefore = topic.memory;
  final color = ratingColor(context, rating);

  pendingExits.putIfAbsent(topic.id, () => TopicExit.right);
  final snap = app.review(topic, rating);
  Fx.instance.rated(rating);

  final next = topic.due;
  if (at != null) {
    showBurst(
      context,
      center: at,
      icon: ratingIcon(rating),
      color: color,
      label: next == null ? 'Fini' : formatRelativeDay(next, app.today),
      sparks: rating == Rating.easy ? 18 : 12,
    );
  }

  final levelAfter = topic.memory;
  if (dueBefore > 0 && app.dueCount() == 0) {
    celebrateDay(context, app);
  } else if (levelAfter >= 4 && levelAfter > levelBefore) {
    Fx.instance.levelUp(delay: const Duration(milliseconds: 350));
    showBanner(
      context,
      icon: Icons.workspace_premium_rounded,
      title: 'Souvenir ${memoryLabels[levelAfter].toLowerCase()} !',
      subtitle: topic.title,
      color: goodColor,
      delay: const Duration(milliseconds: 300),
    );
  } else if (firstToday && app.streak >= 2) {
    Fx.instance.streak(delay: const Duration(milliseconds: 350));
    showBanner(
      context,
      icon: Icons.local_fire_department_rounded,
      title: '${app.streak} jours de suite !',
      subtitle: 'Ta série continue',
      color: streakColor,
      delay: const Duration(milliseconds: 300),
    );
  }

  final message = next == null
      ? '${rating.label} · plus de rappel avant l\'examen'
      : '${rating.label} · prochain rappel ${formatRelativeDay(next, app.today)}';
  showUndoSnack(context, message, () {
    Fx.instance.undone();
    app.restore(topic, snap);
  });
}

/// Plus rien à revoir aujourd'hui : fanfare, confettis et bannière.
void celebrateDay(BuildContext context, AppState app) {
  Fx.instance.dayComplete(delay: const Duration(milliseconds: 380));
  showConfetti(context);
  final n = app.reviewedToday;
  final streak = app.streak;
  showBanner(
    context,
    icon: Icons.emoji_events_rounded,
    title: 'Journée terminée !',
    subtitle: [
      plural(n, 'révision'),
      if (streak >= 2) '$streak jours de suite',
    ].join(' · '),
    color: trophyColor,
    delay: const Duration(milliseconds: 250),
  );
}

/// Annule la dernière révision du sujet, avec un bandeau pour la rétablir.
void undoLastReviewWithRedo(BuildContext context, AppState app, Topic topic) {
  final snap = app.undoLastReview(topic);
  if (snap == null) return;
  Fx.instance.undone();
  final due = topic.due;
  final message = due == null
      ? 'Révision annulée'
      : app.isDue(topic)
          ? 'Révision annulée : de nouveau à revoir'
          : 'Révision annulée · rappel ${formatRelativeDay(due, app.today)}';
  showUndoSnack(
    context,
    message,
    () {
      Fx.instance.tap();
      app.restore(topic, snap);
    },
    actionLabel: 'Rétablir',
  );
}

/// Repousse le sujet à demain, avec un bandeau pour annuler.
void postponeWithUndo(
  BuildContext context,
  AppState app,
  Topic topic, {
  Offset? origin,
}) {
  final at = origin ?? centerOf(context);
  final color = Theme.of(context).colorScheme.secondary;
  pendingExits.putIfAbsent(topic.id, () => TopicExit.left);
  final snap = app.postpone(topic);
  Fx.instance.postponed();
  if (at != null) {
    showBurst(
      context,
      center: at,
      icon: Icons.snooze_rounded,
      color: color,
      label: 'Demain',
      sparks: 8,
    );
  }
  showUndoSnack(context, 'Rappel repoussé à demain', () {
    Fx.instance.undone();
    app.restore(topic, snap);
  });
}
