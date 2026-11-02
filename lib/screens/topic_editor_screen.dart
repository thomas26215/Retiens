import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../logic/dates.dart';
import '../logic/format.dart';
import '../logic/scheduler.dart';
import '../services/fx.dart';
import '../theme.dart';
import '../widgets/celebrations.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../models/subject.dart';
import 'chapter_dialogs.dart';
import 'subject_sheet.dart';

/// Création (topicId == null) ou modification d'un sujet à réviser.
class TopicEditorScreen extends StatefulWidget {
  const TopicEditorScreen({
    super.key,
    this.subjectId,
    this.topicId,
    this.chapterId,
  });

  /// Matière (et chapitre) présélectionnés à la création.
  final String? subjectId;
  final String? chapterId;
  final String? topicId;

  @override
  State<TopicEditorScreen> createState() => _TopicEditorScreenState();
}

class _TopicEditorScreenState extends State<TopicEditorScreen> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _titleFocus = FocusNode();
  String? _subjectId;
  String? _chapterId;
  DateTime _studiedOn = dateOnly(DateTime.now());
  bool _loaded = false;
  bool _showTitleError = false;
  int _shake = 0;

  bool get _isEditing => widget.topicId != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final app = AppScope.of(context);
    final id = widget.topicId;
    if (id != null) {
      final topic = app.topicById(id);
      if (topic != null) {
        _title.text = topic.title;
        _note.text = topic.note;
        _subjectId = topic.subjectId;
        _chapterId = app.chapterOf(topic)?.id;
        _studiedOn = topic.studiedOn;
      }
    } else {
      _subjectId = widget.subjectId ??
          (app.subjects.isEmpty ? null : app.subjects.first.id);
      _chapterId = widget.chapterId;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _save({required bool keepOpen, Offset? origin}) {
    final title = _title.text.trim();
    final subjectId = _subjectId;
    if (title.isEmpty) {
      Fx.instance.error();
      setState(() {
        _showTitleError = true;
        _shake++;
      });
      _titleFocus.requestFocus();
      return;
    }
    if (subjectId == null) {
      Fx.instance.error();
      showInfoSnack(context, 'Choisis une matière.');
      return;
    }
    final app = AppScope.of(context);
    final note = _note.text.trim();
    final id = widget.topicId;
    if (id != null) {
      final topic = app.topicById(id);
      if (topic != null) {
        app.updateTopic(
          topic,
          subjectId: subjectId,
          title: title,
          note: note,
          studiedOn: _studiedOn,
          chapterId: _chapterId,
        );
      }
    } else {
      app.addTopic(
        subjectId: subjectId,
        title: title,
        note: note,
        studiedOn: _studiedOn,
        chapterId: _chapterId,
      );
    }
    Fx.instance.added();
    if (origin != null) {
      showBurst(
        context,
        center: origin,
        icon: id == null ? Icons.add_task_rounded : Icons.check_rounded,
        color: Theme.of(context).colorScheme.primary,
        label: id == null ? 'Ajouté' : 'Enregistré',
        sparks: 10,
      );
    }
    if (keepOpen) {
      _title.clear();
      _note.clear();
      _titleFocus.requestFocus();
      showInfoSnack(context, '« $title » ajouté. Au suivant !');
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _studiedOn.isAfter(now) ? now : _studiedOn,
      firstDate: now.subtract(const Duration(days: 365 * 2)),
      lastDate: now,
      helpText: "Jour où tu l'as étudié",
    );
    if (picked != null) setState(() => _studiedOn = dateOnly(picked));
  }

  Future<void> _newSubject() async {
    final s = await showSubjectSheet(context);
    if (s != null && mounted) {
      setState(() {
        _subjectId = s.id;
        _chapterId = null;
      });
    }
  }

  Future<void> _newChapter(Subject subject) async {
    final c = await createChapter(context, subject);
    if (c != null && mounted) setState(() => _chapterId = c.id);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = app.today;
    final yesterday = addDays(today, -1);
    final subject = _subjectId == null ? null : app.subjectById(_subjectId!);
    final topic = widget.topicId == null ? null : app.topicById(widget.topicId!);
    final reviewed = topic != null && topic.reviewCount > 0;
    final planned = projectedDates(
      due: reviewed
          ? topic.due
          : firstDue(
              studiedOn: _studiedOn,
              today: today,
              examDate: subject?.examDate,
            ),
      interval: topic?.interval ?? 0,
      ease: topic?.ease ?? defaultEase,
      today: today,
      examDate: subject?.examDate,
      pace: app.pace.factor,
      limit: 5,
    );
    final isOtherDay = _studiedOn != today && _studiedOn != yesterday;

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(text, style: theme.textTheme.titleSmall),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifier le sujet' : "J'ai étudié…"),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Shake(
            trigger: _shake,
            child: TextField(
            controller: _title,
            focusNode: _titleFocus,
            autofocus: !_isEditing,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            style: theme.textTheme.titleMedium,
            onChanged: (_) {
              if (_showTitleError) setState(() => _showTitleError = false);
            },
            decoration: InputDecoration(
              labelText: 'Sujet',
              hintText: 'Ex. Les nombres complexes',
              errorText: _showTitleError ? 'Donne un titre au sujet' : null,
            ),
          ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note (facultatif)',
              hintText: 'Pages, lien, idées clés à retenir…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          label('Matière'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in app.subjects)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: subjectColor(context, s)),
                  label: Text(s.name),
                  selected: _subjectId == s.id,
                  showCheckmark: false,
                  onSelected: (_) {
                    Fx.instance.toggle();
                    setState(() {
                      if (_subjectId != s.id) _chapterId = null;
                      _subjectId = s.id;
                    });
                  },
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Nouvelle matière'),
                onPressed: _newSubject,
              ),
            ],
          ),
          // Chapitre de la matière choisie (« Autre » : sans chapitre).
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: subject == null
                ? const SizedBox(width: double.infinity)
                : Column(
                    key: ValueKey(subject.id),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      label('Chapitre'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in subject.chapters)
                            ChoiceChip(
                              avatar: Icon(
                                Icons.folder_rounded,
                                size: 18,
                                color: subjectColor(context, subject),
                              ),
                              label: Text(c.name),
                              selected: _chapterId == c.id,
                              showCheckmark: false,
                              onSelected: (_) {
                                Fx.instance.toggle();
                                setState(() => _chapterId = c.id);
                              },
                            ),
                          ChoiceChip(
                            avatar: const Icon(Icons.inbox_outlined, size: 18),
                            label: const Text('Autre'),
                            selected: subject.chapterById(_chapterId) == null,
                            showCheckmark: false,
                            onSelected: (_) {
                              Fx.instance.toggle();
                              setState(() => _chapterId = null);
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.create_new_folder_outlined, size: 18),
                            label: const Text('Nouveau chapitre'),
                            onPressed: () => _newChapter(subject),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          label('Étudié'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text("Aujourd'hui"),
                selected: _studiedOn == today,
                showCheckmark: false,
                onSelected: (_) {
                  Fx.instance.toggle();
                  setState(() => _studiedOn = today);
                },
              ),
              ChoiceChip(
                label: const Text('Hier'),
                selected: _studiedOn == yesterday,
                showCheckmark: false,
                onSelected: (_) {
                  Fx.instance.toggle();
                  setState(() => _studiedOn = yesterday);
                },
              ),
              ChoiceChip(
                avatar: Icon(
                  Icons.event_rounded,
                  size: 18,
                  color: isOtherDay ? scheme.onSecondaryContainer : null,
                ),
                label: Text(isOtherDay ? formatShortDay(_studiedOn) : 'Autre jour'),
                selected: isOtherDay,
                showCheckmark: false,
                onSelected: (_) => _pickDate(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notifications_active_outlined, size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text('Rappels prévus', style: theme.textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (planned.isEmpty)
                    Text(
                      'Aucun rappel : l\'examen est trop proche.',
                      style: theme.textTheme.bodyMedium,
                    )
                  else
                    // Les dates se recalculent en fondu quand on change le jour.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Wrap(
                        key: ValueKey(planned.join()),
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < planned.length; i++)
                            FadeSlideIn(
                              delay: stagger(i, stepMs: 60),
                              scale: 0.85,
                              offset: 6,
                              child: _DateChip(
                                top: 'J+${daysBetween(_studiedOn, planned[i])}',
                                bottom: formatShortDay(planned[i]),
                                past: !planned[i].isAfter(today),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    '${planned.isNotEmpty && !planned.first.isAfter(today) ? 'La première révision est à faire dès aujourd\'hui. ' : ''}'
                    'Dates estimées si chaque révision se passe bien : une '
                    'révision difficile rapproche les suivantes, une facile '
                    'les éloigne.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Pressable(
            child: Builder(
              builder: (button) => FilledButton(
                onPressed: () => _save(keepOpen: false, origin: centerOf(button)),
                child: Text(_isEditing ? 'Enregistrer' : 'Ajouter'),
              ),
            ),
          ),
          if (!_isEditing) ...[
            const SizedBox(height: 8),
            Builder(
              builder: (button) => TextButton.icon(
                onPressed: () => _save(keepOpen: true, origin: centerOf(button)),
                icon: const Icon(Icons.playlist_add_rounded),
                label: const Text('Ajouter et en saisir un autre'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.top, required this.bottom, required this.past});

  final String top;
  final String bottom;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: past ? scheme.surfaceContainerHighest : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            top,
            style: theme.textTheme.labelLarge?.copyWith(
              color: past ? scheme.onSurfaceVariant : scheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            bottom,
            style: theme.textTheme.bodySmall?.copyWith(
              color: past ? scheme.onSurfaceVariant : scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
