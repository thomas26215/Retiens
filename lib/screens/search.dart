import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../widgets/common.dart';
import '../widgets/topic_card.dart';

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'œ': 'oe', 'æ': 'ae',
};

/// Minuscules sans accents, pour une recherche tolérante.
String normalize(String s) {
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b.toString();
}

/// Recherche dans les titres et les notes de tous les sujets.
class TopicSearchDelegate extends SearchDelegate<void> {
  TopicSearchDelegate() : super(searchFieldLabel: 'Rechercher un sujet');

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            tooltip: 'Effacer',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        tooltip: 'Retour',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final app = AppScope.of(context);
    final q = normalize(query.trim());
    if (q.isEmpty) {
      return const EmptyState(
        icon: Icons.search_rounded,
        title: 'Rechercher',
        message: 'Tape un mot du titre ou de la note.',
      );
    }
    final results = app.topics.where((t) {
      final subject = app.subjectById(t.subjectId)?.name ?? '';
      final chapter = app.chapterOf(t)?.name ?? '';
      return normalize('${t.title} ${t.note} $subject $chapter').contains(q);
    }).toList();
    if (results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Aucun résultat',
        message: 'Rien ne correspond à « ${query.trim()} ».',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      itemBuilder: (_, i) => TopicCard(topic: results[i], swipeable: false),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
    );
  }
}
