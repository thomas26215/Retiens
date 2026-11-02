import 'package:flutter/material.dart';

import '../app_scope.dart';
import 'account_screen.dart';
import 'settings_screen.dart';
import 'subject_screen.dart';
import 'subject_sheet.dart';
import 'topic_editor_screen.dart';
import 'topic_screen.dart';

Future<void> openTopic(BuildContext context, String topicId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TopicScreen(topicId: topicId)),
    );

Future<void> openSubject(BuildContext context, String subjectId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubjectScreen(subjectId: subjectId),
      ),
    );

Future<void> openEditor(
  BuildContext context, {
  String? subjectId,
  String? topicId,
  String? chapterId,
}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TopicEditorScreen(
          subjectId: subjectId,
          topicId: topicId,
          chapterId: chapterId,
        ),
      ),
    );

Future<void> openAccount(BuildContext context, {bool create = true}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountScreen(createAccount: create),
      ),
    );

Future<void> openSettings(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );

/// Ajout d'un sujet ; propose d'abord de créer une matière s'il n'y en a pas.
Future<void> startAddTopic(BuildContext context, {String? subjectId}) async {
  final app = AppScope.of(context);
  var id = subjectId;
  if (app.subjects.isEmpty) {
    final created = await showSubjectSheet(context);
    if (created == null || !context.mounted) return;
    id = created.id;
  }
  await openEditor(context, subjectId: id);
}

/// Bouton « Réglages » des en-têtes d'onglet.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Réglages',
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => openSettings(context),
    );
  }
}
