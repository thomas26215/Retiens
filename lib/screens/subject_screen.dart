import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../logic/dates.dart';
import '../logic/format.dart';
import '../models/topic.dart';
import '../services/fx.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/topic_card.dart';
import '../data/app_state.dart';
import '../models/subject.dart';
import 'chapter_dialogs.dart';
import 'routes.dart';
import 'subject_sheet.dart';

enum _Filter { all, due, active, done }

class SubjectScreen extends StatefulWidget {
  const SubjectScreen({super.key, required this.subjectId});

  final String subjectId;

  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  _Filter _filter = _Filter.all;

  /// Chapitres repliés (id, ou [_other] pour « Autre »).
  final Set<String> _collapsed = {};
  static const _other = '_autre';

  void _toggle(String key) {
    Fx.instance.toggle();
    setState(() => _collapsed.contains(key) ? _collapsed.remove(key) : _collapsed.add(key));
  }

  Future<void> _delete(int topicCount, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la matière ?'),
        content: Text(
          topicCount == 0
              ? '« $name » sera supprimée.'
              : '« $name » et ses ${plural(topicCount, 'sujet')} seront supprimés. '
                  'Action irréversible.',
        ),
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
    if (ok == true && mounted) {
      final app = AppScope.of(context);
      Fx.instance.deleted();
      Navigator.of(context).pop();
      app.deleteSubject(widget.subjectId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final subject = app.subjectById(widget.subjectId);
    if (subject == null) {
      return const Scaffold(body: Center(child: Text('Matière introuvable')));
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = subjectColor(context, subject);
    final all = app.topicsOf(subject.id);
    final today = app.today;
    bool isDue(Topic t) => t.due != null && !t.due!.isAfter(today);
    final dueCount = all.where(isDue).length;
    final solidCount = all.where((t) => t.memory >= 4).length;
    final ratio = app.subjectMastery(subject.id);

    final shown = switch (_filter) {
      _Filter.all => all,
      _Filter.due => all.where(isDue).toList(),
      _Filter.active => all.where((t) => !t.isDone && !isDue(t)).toList(),
      _Filter.done => all.where((t) => t.isDone).toList(),
    };

    final exam = subject.examDate;
    String? examLine;
    if (exam != null) {
      final days = daysBetween(today, exam);
      examLine = days > 0
          ? 'Examen ${formatLongDay(exam)} · J-$days'
          : days == 0
              ? "Examen aujourd'hui"
              : 'Examen passé (${formatDate(exam)})';
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Modifier la matière',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showSubjectSheet(context, subject: subject),
          ),
          PopupMenuButton<String>(
            onSelected: (_) => _delete(all.length, subject.name),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Supprimer la matière')),
            ],
          ),
        ],
      ),
      floatingActionButton: Pressable(
        child: FloatingActionButton.extended(
          onPressed: () {
            Fx.instance.tap();
            openEditor(context, subjectId: subject.id);
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Sujet étudié'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SubjectAvatar(subject: subject, size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        subject.name,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _MiniStat(value: '${all.length}', label: 'sujets'),
                    _MiniStat(value: '$dueCount', label: 'à revoir'),
                    _MiniStat(value: '$solidCount', label: 'solides'),
                  ],
                ),
                if (all.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: ProgressBar(value: ratio, color: color)),
                      const SizedBox(width: 12),
                      Text(
                        'maîtrise ${(ratio * 100).round()} %',
                        style: theme.textTheme.labelLarge,
                      ),
                    ],
                  ),
                ],
                if (examLine != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(Icons.flag_rounded, size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          capitalize(examLine),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (all.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (f, label) in [
                    (_Filter.all, 'Tous'),
                    (_Filter.due, 'À revoir'),
                    (_Filter.active, 'En cours'),
                    (_Filter.done, 'Sans rappel'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _filter == f,
                        showCheckmark: false,
                        onSelected: (_) {
                          Fx.instance.toggle();
                          setState(() => _filter = f);
                        },
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (subject.chapters.isEmpty)
            _ChapterPrompt(onCreate: () => createChapter(context, subject))
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      plural(subject.chapters.length, 'chapitre'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => createChapter(context, subject),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Chapitre'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          if (subject.chapters.isNotEmpty &&
              _filter != _Filter.all &&
              shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Aucun sujet dans cette catégorie.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else if (subject.chapters.isNotEmpty)
            // Un bloc par chapitre, puis « Autre » (sans chapitre).
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Column(
                key: ValueKey(_filter),
                children: [
                  for (var i = 0; i <= subject.chapters.length; i++)
                    Builder(builder: (context) {
                      final chapter =
                          i < subject.chapters.length ? subject.chapters[i] : null;
                      final inSection = all
                          .where((t) => chapter == null
                              ? app.chapterOf(t) == null
                              : t.chapterId == chapter.id)
                          .toList();
                      final visible =
                          inSection.where((t) => shown.contains(t)).toList();
                      // « Autre » n'apparaît que s'il contient des sujets ; un
                      // filtre masque les chapitres sans sujet correspondant.
                      if (chapter == null && inSection.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      if (_filter != _Filter.all && visible.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final key = chapter?.id ?? _other;
                      return FadeSlideIn(
                        key: ValueKey(key),
                        delay: stagger(i),
                        child: _ChapterSection(
                          subjectId: subject.id,
                          chapter: chapter,
                          index: i,
                          chapterCount: subject.chapters.length,
                          all: inSection,
                          topics: visible,
                          collapsed: _collapsed.contains(key),
                          onToggle: () => _toggle(key),
                        ),
                      );
                    }),
                ],
              ),
            )
          else if (all.isEmpty)
            EmptyState(
              icon: Icons.edit_note_rounded,
              title: 'Aucun sujet',
              message: 'Ajoute ce que tu viens d\'étudier (une leçon, une '
                  'fiche…) : Retiens te le rappellera au bon moment.',
            )
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Aucun sujet dans cette catégorie.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            // Changer de filtre fait réapparaître la liste en cascade.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Column(
                key: ValueKey(_filter),
                children: [
                  for (var i = 0; i < shown.length; i++)
                    FadeSlideIn(
                      key: ValueKey(shown[i].id),
                      delay: stagger(i),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TopicCard(topic: shown[i], showSubject: false),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedCount(
            value: int.parse(value),
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Invitation à créer le premier chapitre.
class _ChapterPrompt extends StatelessWidget {
  const _ChapterPrompt({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: InkWell(
        onTap: onCreate,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Icon(Icons.folder_copy_outlined, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Organiser en chapitres', style: theme.textTheme.titleSmall),
                    Text(
                      'Range les sujets par chapitre ; le reste va dans « Autre ».',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.add_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un chapitre (ou « Autre ») : en-tête repliable avec compteurs et
/// maîtrise, menu d'actions, puis ses sujets.
class _ChapterSection extends StatelessWidget {
  const _ChapterSection({
    required this.subjectId,
    required this.chapter,
    required this.index,
    required this.chapterCount,
    required this.all,
    required this.topics,
    required this.collapsed,
    required this.onToggle,
  });

  final String subjectId;

  /// `null` pour « Autre ».
  final Chapter? chapter;
  final int index;
  final int chapterCount;

  /// Tous les sujets du chapitre / ceux qui passent le filtre.
  final List<Topic> all;
  final List<Topic> topics;
  final bool collapsed;
  final VoidCallback onToggle;

  Future<void> _action(BuildContext context, String action) async {
    final app = AppScope.of(context);
    final subject = app.subjectById(subjectId);
    final c = chapter;
    if (subject == null) return;
    switch (action) {
      case 'add':
        Fx.instance.tap();
        await openEditor(context, subjectId: subjectId, chapterId: c?.id);
      case 'rename':
        if (c == null) return;
        final name = await askChapterName(context, initial: c.name);
        if (name != null) {
          Fx.instance.toggle();
          app.renameChapter(subject, c, name);
        }
      case 'up':
      case 'down':
        if (c == null) return;
        Fx.instance.toggle();
        app.moveChapter(subject, c, action == 'up' ? -1 : 1);
      case 'delete':
        if (c == null) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Supprimer le chapitre ?'),
            content: Text(
              all.isEmpty
                  ? '« ${c.name} » sera supprimé.'
                  : '« ${c.name} » sera supprimé. Ses ${plural(all.length, 'sujet')} '
                      'passeront dans « Autre », avec leurs révisions.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        );
        if (ok == true) {
          Fx.instance.deleted();
          app.deleteChapter(subject, c);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subject = app.subjectById(subjectId);
    final color = subjectColor(context, subject);
    final dueCount = all.where(app.isDue).length;
    final mastery = AppState.masteryOf(all);
    final c = chapter;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: collapsed ? -0.25 : 0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      child: Icon(Icons.expand_more_rounded, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      c == null ? Icons.inbox_outlined : Icons.folder_rounded,
                      size: 20,
                      color: c == null ? scheme.onSurfaceVariant : color,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c?.name ?? 'Autre',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  all.isEmpty
                                      ? 'Aucun sujet'
                                      : '${plural(all.length, 'sujet')}'
                                          '${dueCount > 0 ? ' · $dueCount à revoir' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: dueCount > 0 ? scheme.primary : scheme.onSurfaceVariant,
                                    fontWeight: dueCount > 0 ? FontWeight.w700 : null,
                                  ),
                                ),
                              ),
                              if (all.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 56,
                                  child: ProgressBar(value: mastery, color: color, height: 5),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Actions du chapitre',
                      onSelected: (a) => _action(context, a),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'add', child: Text('Ajouter un sujet')),
                        if (c != null) ...[
                          const PopupMenuItem(value: 'rename', child: Text('Renommer')),
                          if (index > 0)
                            const PopupMenuItem(value: 'up', child: Text('Monter')),
                          if (index < chapterCount - 1)
                            const PopupMenuItem(value: 'down', child: Text('Descendre')),
                          const PopupMenuItem(value: 'delete', child: Text('Supprimer le chapitre')),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Repli / dépli animé.
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: collapsed
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: topics.isEmpty
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _action(context, 'add'),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Ajouter un sujet à ce chapitre'),
                            ),
                          )
                        : Column(
                            children: [
                              for (var i = 0; i < topics.length; i++)
                                FadeSlideIn(
                                  key: ValueKey(topics[i].id),
                                  delay: stagger(i),
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: TopicCard(topic: topics[i], showSubject: false),
                                  ),
                                ),
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
