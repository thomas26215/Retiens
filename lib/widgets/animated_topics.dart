import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/topic.dart';
import 'motion.dart';

/// Façon dont un sujet quitte une liste animée.
enum TopicExit {
  /// S'envole vers la droite (révision notée).
  right,

  /// Part vers la gauche (repoussé à demain).
  left,

  /// Déjà parti par un balayage : on referme seulement l'espace.
  swiped,

  /// S'efface sur place (annulation, autres cas).
  fade,
}

/// Sortie prévue pour les sujets sur le point de quitter une liste, renseignée
/// par l'action juste avant de modifier les données.
final Map<String, TopicExit> pendingExits = {};

/// Liste de sujets dont les entrées et sorties sont animées. Les sujets sont
/// comparés par identité : l'état les modifie sur place.
class AnimatedTopicSliver extends StatefulWidget {
  const AnimatedTopicSliver({
    super.key,
    required this.topics,
    required this.itemBuilder,
    this.spacing = 8,
    this.cascade = false,
  });

  final List<Topic> topics;
  final Widget Function(BuildContext context, Topic topic) itemBuilder;
  final double spacing;

  /// Au premier affichage, les cartes arrivent en cascade.
  final bool cascade;

  @override
  State<AnimatedTopicSliver> createState() => _AnimatedTopicSliverState();
}

class _AnimatedTopicSliverState extends State<AnimatedTopicSliver> {
  static const _duration = Duration(milliseconds: 420);

  GlobalKey<SliverAnimatedListState> _key = GlobalKey();
  late List<Topic> _items = List.of(widget.topics);
  bool _first = true;

  @override
  void didUpdateWidget(AnimatedTopicSliver old) {
    super.didUpdateWidget(old);
    _first = false;
    final next = widget.topics;
    final list = _key.currentState;
    if (list == null || !motionAllowed(context)) {
      _reset(next);
      return;
    }

    for (var i = _items.length - 1; i >= 0; i--) {
      final t = _items[i];
      if (next.contains(t)) continue;
      _items.removeAt(i);
      final exit = pendingExits.remove(t.id) ?? TopicExit.fade;
      list.removeItem(
        i,
        (context, anim) => _exiting(context, t, anim, exit),
        duration: exit == TopicExit.swiped
            ? const Duration(milliseconds: 320)
            : _duration,
      );
    }
    for (var i = 0; i < next.length; i++) {
      if (_items.contains(next[i])) continue;
      final at = i.clamp(0, _items.length);
      _items.insert(at, next[i]);
      list.insertItem(at, duration: _duration);
    }
    // Ordre changé autrement que par ajouts/retraits : on redessine tout.
    if (!listEquals(_items, next)) _reset(next);
  }

  void _reset(List<Topic> next) {
    _items = List.of(next);
    _key = GlobalKey();
  }

  Widget _padded(BuildContext context, Topic t) => Padding(
        padding: EdgeInsets.only(bottom: widget.spacing),
        child: widget.itemBuilder(context, t),
      );

  Widget _exiting(
    BuildContext context,
    Topic t,
    Animation<double> anim,
    TopicExit exit,
  ) {
    // anim va de 1 à 0 : d'abord la carte s'en va, puis l'espace se referme.
    if (exit == TopicExit.swiped) {
      return SizeTransition(
        sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeInOutCubic),
        child: Opacity(opacity: 0, child: _padded(context, t)),
      );
    }
    final size = CurvedAnimation(
      parent: anim,
      curve: const Interval(0, 0.55, curve: Curves.easeInOutCubic),
    );
    final away = CurvedAnimation(
      parent: anim,
      curve: const Interval(0.35, 1, curve: Curves.easeInCubic),
    );
    final dx = switch (exit) {
      TopicExit.right => 0.6,
      TopicExit.left => -0.6,
      _ => 0.0,
    };
    return SizeTransition(
      sizeFactor: size,
      child: FadeTransition(
        opacity: away,
        child: SlideTransition(
          position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(away),
          child: ScaleTransition(
            scale: Tween(begin: dx == 0 ? 0.9 : 1.0, end: 1.0).animate(away),
            child: _padded(context, t),
          ),
        ),
      ),
    );
  }

  Widget _entering(BuildContext context, Topic t, Animation<double> anim) {
    final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
    final pop = CurvedAnimation(
      parent: anim,
      curve: const Interval(0.3, 1, curve: Curves.easeOutBack),
    );
    return SizeTransition(
      sizeFactor: curved,
      child: FadeTransition(
        opacity: pop,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(pop),
          child: _padded(context, t),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SliverAnimatedList(
      key: _key,
      initialItemCount: _items.length,
      itemBuilder: (context, i, anim) {
        final t = _items[i];
        // Toujours le même emballage, pour ne pas perdre l'état des cartes
        // (balayage en cours) ; la cascade ne joue qu'au premier affichage.
        final cascade = widget.cascade && _first;
        return FadeSlideIn(
          key: ValueKey(t.id),
          delay: cascade ? stagger(i) : Duration.zero,
          duration: cascade ? const Duration(milliseconds: 420) : Duration.zero,
          child: _entering(context, t, anim),
        );
      },
    );
  }
}
