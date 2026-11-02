import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/app_state.dart';
import '../logic/dates.dart';
import '../logic/format.dart';
import '../logic/scheduler.dart';
import '../models/topic.dart';
import '../services/fx.dart';
import '../theme.dart';
import '../widgets/celebrations.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/rating.dart';
import '../widgets/topic_card.dart';
import 'chapter_dialogs.dart';
import 'routes.dart';

/// Fiche d'un sujet : note, révision du jour et parcours des rappels.
class TopicScreen extends StatelessWidget {
  const TopicScreen({super.key, required this.topicId});

  final String topicId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final topic = app.topicById(topicId);
    if (topic == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Sujet supprimé')));
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subject = app.subjectById(topic.subjectId);
    final color = subjectColor(context, subject);
    final today = app.today;
    final isDue = app.isDue(topic);
    final exam = app.examOf(topic);

    Future<void> confirmDelete() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Supprimer ce sujet ?'),
          content: Text('« ${topic.title} » et son historique seront supprimés.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
                minimumSize: const Size(0, 44),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      );
      if (ok == true && context.mounted) {
        Fx.instance.deleted();
        Navigator.of(context).pop();
        app.deleteTopic(topic.id);
      }
    }

    void undoable(String message, TopicSnapshot snap) => showUndoSnack(
          context,
          message,
          () {
            Fx.instance.undone();
            app.restore(topic, snap);
          },
        );

    void restart() {
      Fx.instance.added();
      undoable('Cycle relancé depuis aujourd\'hui', app.restart(topic));
    }

    void stop() {
      Fx.instance.toggle();
      undoable('Rappels arrêtés', app.stop(topic));
    }

    void resume() {
      if (!app.resume(topic)) {
        showInfoSnack(context, "L'examen est passé : plus de rappel possible.");
      } else {
        Fx.instance.added();
      }
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Modifier',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => openEditor(context, topicId: topic.id),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'restart':
                  restart();
                case 'stop':
                  stop();
                case 'resume':
                  resume();
                case 'chapter':
                  pickChapterFor(context, topic);
                default:
                  confirmDelete();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'restart',
                child: Text("Réétudié aujourd'hui"),
              ),
              if (topic.isDone)
                const PopupMenuItem(value: 'resume', child: Text('Reprendre les rappels'))
              else
                const PopupMenuItem(value: 'stop', child: Text('Arrêter les rappels')),
              if (subject != null && subject.chapters.isNotEmpty)
                const PopupMenuItem(value: 'chapter', child: Text('Changer de chapitre')),
              const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          if (subject != null)
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => openSubject(context, subject.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SubjectAvatar(subject: subject, size: 24),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          [subject.name, if (app.chapterOf(topic) case final c?) c.name].join(' › '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          FadeSlideIn(
            child: Text(topic.title, style: theme.textTheme.headlineMedium),
          ),
          const SizedBox(height: 10),
          TopicStatus(topic: topic),
          if (topic.note.trim().isNotEmpty) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notes_rounded, size: 20, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SelectableText(
                        topic.note.trim(),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FadeSlideIn(
            delay: const Duration(milliseconds: 80),
            child: _MemoryCard(topic: topic, color: color),
          ),
          // Les blocs suivants apparaissent et disparaissent en douceur.
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: app.canUndoLastReview(topic)
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: FadeSlideIn(
                      key: ValueKey(topic.history.length),
                      child: _LastReviewCard(topic: topic),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, anim) => SizeTransition(
              sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeInOutCubic),
              alignment: Alignment.topCenter,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: isDue
                ? Column(
                    key: const ValueKey('due'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
            const SizedBox(height: 28),
            Text('Comment s\'est passée la révision ?', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            RatingButtons(
              topic: topic,
              onRated: (r, at) => reviewWithUndo(context, app, topic, r, origin: at),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Builder(
                builder: (button) => TextButton.icon(
                  onPressed: () => postponeWithUndo(
                    context,
                    app,
                    topic,
                    origin: centerOf(button),
                  ),
                  icon: const Icon(Icons.snooze_rounded),
                  label: const Text('Pas le temps : demain'),
                ),
              ),
            ),
                    ],
                  )
                : topic.isDone
                    ? Column(
                        key: const ValueKey('done'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plus de rappel pour ce sujet', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      exam != null && !exam.isAfter(today)
                          ? "L'examen est passé. Relance un cycle si tu dois le réviser à nouveau."
                          : 'Reprends les rappels quand tu veux, ou relance un cycle si tu l\'as réétudié.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: restart,
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text("Réétudié aujourd'hui"),
                        ),
                        if (exam == null || exam.isAfter(today))
                          TextButton(onPressed: resume, child: const Text('Reprendre')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
                        ],
                      )
                    : const SizedBox(key: ValueKey('none'), width: double.infinity),
          ),
          const SizedBox(height: 28),
          Text('Parcours', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          FadeSlideIn(
            delay: const Duration(milliseconds: 160),
            child: Card(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                  child: _Timeline(topic: topic, color: color),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Rythme ${app.pace.label.toLowerCase()}. Les dates « vers le » '
            'supposent des révisions notées « Bien » : elles s\'éloignent si '
            'c\'est facile et se rapprochent si c\'est difficile.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Solidité du souvenir et intervalle actuel.
/// Dernière révision (jour et note), avec un bouton pour l'annuler.
class _LastReviewCard extends StatelessWidget {
  const _LastReviewCard({required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final last = topic.history.last;
    final rating = last.rating;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              rating == null ? Icons.check_circle_outline_rounded : ratingIcon(rating),
              color: rating == null
                  ? scheme.onSurfaceVariant
                  : ratingColor(context, rating),
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rating == null
                        ? 'Dernière révision'
                        : 'Dernière révision : ${rating.label.toLowerCase()}',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    capitalize(formatRelativeDay(last.day, app.today)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => undoLastReviewWithRedo(context, app, topic),
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Annuler'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.topic, required this.color});

  final Topic topic;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final level = topic.memory;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            MemoryMeter(level: level, color: color, height: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Souvenir ${memoryLabels[level].toLowerCase()}',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    topic.interval == 0
                        ? 'Pas encore revu'
                        : '${plural(topic.reviewCount, 'révision')} · '
                            'intervalle de ${plural(topic.interval, 'jour')}',
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
    );
  }
}

enum _State { start, done, next, later, exam }

class _Entry {
  const _Entry({
    required this.state,
    required this.title,
    required this.subtitle,
    this.rating,
  });

  final _State state;
  final String title;
  final String subtitle;
  final Rating? rating;
}

/// Parcours : étude, révisions faites (avec leur note), puis rappels à venir.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.topic, required this.color});

  final Topic topic;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final today = app.today;
    final exam = app.examOf(topic);
    final remaining = app.remainingDates(topic, limit: 4);

    final entries = <_Entry>[
      _Entry(
        state: _State.start,
        title: 'Étudié',
        subtitle: capitalize(formatLongDay(topic.studiedOn)),
      ),
    ];
    // Dernières révisions du cycle en cours (les anciennes données n'en
    // gardaient qu'une : la numérotation suit le compteur).
    final history = topic.history.where((r) => !r.day.isBefore(topic.studiedOn)).toList();
    final done = history.length > topic.reviewCount
        ? history.sublist(history.length - topic.reviewCount)
        : history;
    final offset = topic.reviewCount - done.length;
    for (var i = 0; i < done.length; i++) {
      entries.add(_Entry(
        state: _State.done,
        title: '${ordinal(offset + i + 1)} révision',
        subtitle: capitalize(formatShortDay(done[i].day)),
        rating: done[i].rating,
      ));
    }
    for (var j = 0; j < remaining.length; j++) {
      final d = remaining[j];
      final String subtitle;
      if (j == 0) {
        final late = daysBetween(topic.due!, today);
        subtitle = late > 0
            ? 'En retard de $late j, à revoir maintenant'
            : late == 0
                ? "À revoir aujourd'hui"
                : 'Prévue ${formatShortDay(d)} · ${formatRelativeDay(d, today)}';
      } else {
        subtitle = 'Vers le ${formatShortDay(d)}';
      }
      entries.add(_Entry(
        state: j == 0 ? _State.next : _State.later,
        title: '${ordinal(topic.reviewCount + j + 1)} révision',
        subtitle: subtitle,
      ));
    }
    if (exam != null) {
      final days = daysBetween(today, exam);
      entries.add(_Entry(
        state: _State.exam,
        title: 'Examen',
        subtitle: '${capitalize(formatLongDay(exam))}'
            '${days > 0 ? ' · J-$days' : days == 0 ? " · aujourd'hui" : ' · passé'}',
      ));
    }

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          _TimelineRow(
            entry: entries[i],
            color: color,
            isLast: i == entries.length - 1,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.entry,
    required this.color,
    required this.isLast,
  });

  final _Entry entry;
  final Color color;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final line = scheme.outlineVariant;

    final Widget marker = switch (entry.state) {
      _State.start => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      _State.done => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, size: 16, color: onColor(color)),
        ),
      _State.next => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: scheme.primary, width: 3),
            color: scheme.surface,
          ),
        ),
      _State.later => Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: line, width: 2),
          ),
        ),
      _State.exam => Icon(Icons.flag_rounded, size: 22, color: scheme.tertiary),
    };

    final muted = entry.state == _State.later;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                SizedBox(height: 24, child: Center(child: marker)),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: line),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: muted ? scheme.onSurfaceVariant : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: entry.state == _State.next
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      fontWeight:
                          entry.state == _State.next ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (entry.rating != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 8),
              child: RatingChip(rating: entry.rating!),
            ),
        ],
      ),
    );
  }
}
