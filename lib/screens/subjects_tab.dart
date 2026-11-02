import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../logic/dates.dart';
import '../logic/format.dart';
import '../models/subject.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import 'routes.dart';
import 'search.dart';
import 'subject_sheet.dart';

class SubjectsTab extends StatelessWidget {
  const SubjectsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: TabHeader(
              title: 'Matières',
              actions: [
                if (app.topics.isNotEmpty)
                  IconButton(
                    tooltip: 'Rechercher un sujet',
                    icon: const Icon(Icons.search_rounded),
                    onPressed: () => showSearch<void>(
                      context: context,
                      delegate: TopicSearchDelegate(),
                    ),
                  ),
                const SettingsButton(),
              ],
            ),
          ),
          if (app.subjects.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.auto_stories_rounded,
                title: 'Aucune matière',
                message: 'Regroupe tes sujets par matière, avec leur date '
                    "d'examen pour adapter les rappels.",
                action: FilledButton.icon(
                  onPressed: () => showSubjectSheet(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Créer une matière'),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList.separated(
                itemCount: app.subjects.length,
                itemBuilder: (_, i) => FadeSlideIn(
                  delay: stagger(i, stepMs: 60),
                  child: Pressable(child: _SubjectCard(subject: app.subjects[i])),
                ),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 112)),
        ],
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = subjectColor(context, subject);
    final count = app.topics.where((t) => t.subjectId == subject.id).length;
    final due = app.dueCount(subjectId: subject.id);
    final ratio = app.subjectMastery(subject.id);
    final exam = subject.examDate;
    final examDays = exam == null ? null : daysBetween(app.today, exam);

    return Card(
      child: InkWell(
        onTap: () => openSubject(context, subject.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SubjectAvatar(subject: subject, size: 46),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (subject.chapters.isNotEmpty)
                              plural(subject.chapters.length, 'chapitre'),
                            count == 0
                                ? 'aucun sujet'
                                : plural(count, 'sujet'),
                            if (count > 0) due == 0 ? 'rien à revoir' : '$due à revoir',
                          ].join(' · ').replaceFirstMapped(
                                RegExp(r'^.'),
                                (m) => m[0]!.toUpperCase(),
                              ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (due > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$due',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onPrimary,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
              if (count > 0) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: ProgressBar(value: ratio, color: color)),
                    const SizedBox(width: 12),
                    Text(
                      'maîtrise ${(ratio * 100).round()} %',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
              if (exam != null && examDays != null && examDays >= 0) ...[
                const SizedBox(height: 12),
                InfoPill(
                  icon: Icons.flag_rounded,
                  label: examDays == 0
                      ? "Examen aujourd'hui"
                      : 'Examen ${formatShortDay(exam)} · J-$examDays',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
