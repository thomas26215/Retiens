import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/subject.dart';
import '../models/topic.dart';
import '../services/fx.dart';

/// Demande le nom d'un chapitre (création si [initial] est nul, sinon
/// renommage). `null` si annulé.
Future<String?> askChapterName(BuildContext context, {String? initial}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ChapterNameDialog(initial: initial),
  );
}

/// Crée un chapitre dans [subject] après avoir demandé son nom.
Future<Chapter?> createChapter(BuildContext context, Subject subject) async {
  final app = AppScope.of(context);
  final name = await askChapterName(context);
  if (name == null) return null;
  Fx.instance.added();
  return app.addChapter(subject, name);
}

/// Choix du chapitre d'un sujet (feuille en bas d'écran).
Future<void> pickChapterFor(BuildContext context, Topic topic) async {
  final app = AppScope.of(context);
  final subject = app.subjectById(topic.subjectId);
  if (subject == null) return;
  final current = app.chapterOf(topic)?.id;
  final chosen = await showModalBottomSheet<(String?,)>(
    context: context,
    useSafeArea: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      Widget option(String? id, String label, IconData icon) => ListTile(
            leading: Icon(icon),
            title: Text(label),
            trailing: current == id
                ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                : null,
            onTap: () => Navigator.pop(ctx, (id,)),
          );
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Ranger dans…', style: theme.textTheme.titleLarge),
            ),
            for (final c in subject.chapters)
              option(c.id, c.name, Icons.folder_outlined),
            option(null, 'Autre', Icons.inbox_outlined),
          ],
        ),
      );
    },
  );
  if (chosen == null || chosen.$1 == current) return;
  Fx.instance.toggle();
  app.moveTopicToChapter(topic, chosen.$1);
}

class _ChapterNameDialog extends StatefulWidget {
  const _ChapterNameDialog({this.initial});

  final String? initial;

  @override
  State<_ChapterNameDialog> createState() => _ChapterNameDialogState();
}

class _ChapterNameDialogState extends State<_ChapterNameDialog> {
  late final _name = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.initial == null;
    return AlertDialog(
      title: Text(creating ? 'Nouveau chapitre' : 'Renommer le chapitre'),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: 'Nom',
          hintText: 'Ex. Chapitre 1 : nombres complexes',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _name.text.trim().isEmpty ? null : _submit,
          child: Text(creating ? 'Créer' : 'Renommer'),
        ),
      ],
    );
  }
}
