import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/app_state.dart';
import '../logic/dates.dart';
import '../logic/format.dart';
import '../logic/scheduler.dart';
import '../models/subject.dart';
import '../models/topic.dart';
import '../theme.dart';
import '../services/fx.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/month_calendar.dart';
import '../widgets/topic_card.dart';
import 'routes.dart';

class PlanningTab extends StatefulWidget {
  const PlanningTab({super.key});

  @override
  State<PlanningTab> createState() => _PlanningTabState();
}

class _PlanningTabState extends State<PlanningTab> {
  DateTime? _month;
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final today = app.today;
    final month = _month ?? DateTime(today.year, today.month, 1);
    final selected = _selected ?? today;

    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final planned = app.plannedBetween(today, monthEnd);

    final reviewedByDay = <DateTime, List<Topic>>{};
    for (final t in app.topics) {
      for (final r in t.history) {
        if (r.day.isBefore(monthStart) || r.day.isAfter(monthEnd)) continue;
        final list = reviewedByDay.putIfAbsent(r.day, () => []);
        if (!list.contains(t)) list.add(t);
      }
    }

    DayMarks marksFor(DateTime day) {
      final topics = <Topic>[
        ...?reviewedByDay[day],
        ...?planned[day]?.map((p) => p.topic),
      ];
      final colors = <Color>[];
      final seen = <String>{};
      for (final t in topics) {
        if (seen.add(t.subjectId)) {
          colors.add(subjectColor(context, app.subjectById(t.subjectId)));
        }
      }
      final exam = app.subjects.any((s) => s.examDate == day);
      return DayMarks(colors: colors, exam: exam);
    }

    final next7 = app.plannedBetween(today, addDays(today, 6));
    final weekLoad = next7.values.fold<int>(0, (n, l) => n + l.length);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: TabHeader(title: 'Planning', actions: [SettingsButton()]),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  child: MonthCalendar(
                    month: month,
                    selected: selected,
                    today: today,
                    marksFor: marksFor,
                    onSelect: (d) {
                      Fx.instance.tap();
                      setState(() => _selected = d);
                    },
                    onMonthChanged: (m) {
                      Fx.instance.toggle();
                      setState(() => _month = m);
                    },
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Text(
                weekLoad == 0
                    ? 'Aucune révision prévue ces 7 prochains jours.'
                    : '${plural(weekLoad, 'révision')} prévue${weekLoad > 1 ? 's' : ''} '
                        'ces 7 prochains jours.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          ..._dayDetails(context, app, selected, planned),
          const SliverToBoxAdapter(child: SizedBox(height: 112)),
        ],
      ),
    );
  }

  List<Widget> _dayDetails(
    BuildContext context,
    AppState app,
    DateTime day,
    Map<DateTime, List<PlannedReview>> planned,
  ) {
    final today = app.today;
    final exams = app.subjects.where((s) => s.examDate == day).toList();
    final reviewed = app.reviewedOn(day);
    final isToday = day == today;
    final due = isToday ? app.dueTopics() : const <Topic>[];
    final future = day.isAfter(today) ? planned[day] ?? const [] : const <PlannedReview>[];

    final items = <Widget>[
      for (final s in exams) _ExamRow(subject: s),
      for (final t in due) TopicCard(topic: t),
      for (final p in future) _PlannedRow(review: p),
      for (final (t, r) in reviewed) _ReviewedRow(topic: t, review: r),
    ];

    final relative = formatRelativeDay(day, today);
    return [
      SliverToBoxAdapter(
        child: SectionHeader(
          capitalize(formatLongDay(day)),
          trailing: Text(
            relative,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
      ),
      if (items.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              day.isBefore(today)
                  ? 'Aucune révision ce jour-là.'
                  : 'Rien de prévu ce jour-là.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: items.length,
            // Changer de jour fait arriver la liste en cascade.
            itemBuilder: (_, i) => FadeSlideIn(
              key: ValueKey('${dateKey(day)}#$i'),
              delay: stagger(i),
              child: items[i],
            ),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
          ),
        ),
    ];
  }
}

/// Révision prévue (planning) : sujet, étape, et « estimé » si ce n'est pas
/// le prochain rappel du sujet.
class _PlannedRow extends StatelessWidget {
  const _PlannedRow({required this.review});

  final PlannedReview review;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = review.topic;
    final subject = app.subjectById(t.subjectId);
    final step = '${ordinal(review.number)} révision';
    return _Row(
      subject: subject,
      title: t.title,
      subtitle: [
        if (subject != null) subject.name,
        if (app.chapterOf(t) case final c?) c.name,
        step,
        if (!review.isNext) 'estimé',
      ].join(' · '),
      icon: review.isNext ? Icons.event_rounded : Icons.event_repeat_rounded,
      onTap: () => openTopic(context, t.id),
    );
  }
}

class _ReviewedRow extends StatelessWidget {
  const _ReviewedRow({required this.topic, required this.review});

  final Topic topic;
  final Review review;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final subject = app.subjectById(topic.subjectId);
    final rating = review.rating;
    return _Row(
      subject: subject,
      title: topic.title,
      subtitle: [
        if (subject != null) subject.name,
        if (app.chapterOf(topic) case final c?) c.name,
        rating == null ? 'revu' : 'revu · ${rating.label.toLowerCase()}',
      ].join(' · '),
      icon: rating == null ? Icons.check_circle_rounded : ratingIcon(rating),
      iconColor: rating == null ? goodColor : ratingColor(context, rating),
      onTap: () => openTopic(context, topic.id),
    );
  }
}

class _ExamRow extends StatelessWidget {
  const _ExamRow({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Row(
      subject: subject,
      title: 'Examen · ${subject.name}',
      subtitle: 'Bonne chance !',
      icon: Icons.flag_rounded,
      iconColor: scheme.tertiary,
      background: scheme.tertiaryContainer,
      onTap: () => openSubject(context, subject.id),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.subject,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.iconColor,
    this.background,
  });

  final Subject? subject;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? iconColor;
  final Color? background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: background ?? scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 36,
                decoration: BoxDecoration(
                  color: subjectColor(context, subject),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 20, color: iconColor ?? scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
