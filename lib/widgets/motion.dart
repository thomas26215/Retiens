import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animations continues (flamme qui ondule…). Coupées dans les tests, où
/// elles empêcheraient l'interface de se stabiliser.
bool ambientMotion = true;

/// Faux si le téléphone demande de réduire les animations.
bool motionAllowed(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context);

/// Délai d'apparition du [index]-ième élément d'une liste (effet cascade).
Duration stagger(int index, {int stepMs = 45, int max = 8}) =>
    Duration(milliseconds: stepMs * math.min(index, max));

/// S'enfonce légèrement quand on appuie dessus, puis rebondit.
/// N'intercepte aucun geste : l'enfant garde ses propres boutons.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.scale = 0.965});

  final Widget child;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  Offset? _start;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        _start = e.position;
        _set(true);
      },
      // Un glissement (balayage, défilement) n'est pas un appui.
      onPointerMove: (e) {
        if (_start != null && (e.position - _start!).distance > 12) _set(false);
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 320),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}

/// Apparaît en fondu en glissant vers le haut, après [delay].
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.offset = 18,
    this.scale = 1,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Décalage vertical de départ, en pixels.
  final double offset;

  /// Échelle de départ (1 : pas de zoom).
  final double scale;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  );
  int get _total => (widget.delay + widget.duration).inMicroseconds;

  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      _total == 0 ? 0 : widget.delay.inMicroseconds / _total,
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status == AnimationStatus.dismissed) {
      motionAllowed(context) && _total > 0 ? _c.forward() : _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final v = _t.value;
        return Opacity(
          opacity: v.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - v) * widget.offset),
            child: widget.scale == 1
                ? child
                : Transform.scale(scale: widget.scale + (1 - widget.scale) * v, child: child),
          ),
        );
      },
    );
  }
}

/// Nombre qui défile jusqu'à sa valeur (depuis 0 au premier affichage).
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    this.style,
    this.format,
    this.duration = const Duration(milliseconds: 750),
  });

  final int value;
  final TextStyle? style;
  final String Function(int)? format;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: motionAllowed(context) ? duration : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final n = v.round();
        return Text(format?.call(n) ?? '$n', style: style);
      },
    );
  }
}

/// Secoue l'enfant (de gauche à droite) chaque fois que [trigger] change :
/// champ à compléter, action impossible.
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && motionAllowed(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final dx = math.sin(t * math.pi * 6) * 12 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

/// Ondulation continue (flamme de la série).
class Flicker extends StatefulWidget {
  const Flicker({super.key, required this.child, this.active = true});

  final Widget child;
  final bool active;

  @override
  State<Flicker> createState() => _FlickerState();
}

class _FlickerState extends State<Flicker> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Flicker old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.active && ambientMotion && motionAllowed(context);
    if (run && !_c.isAnimating) _c.repeat();
    if (!run && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value * 2 * math.pi;
        return Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..scaleByDouble(
              1 + 0.06 * math.sin(t * 2),
              1 + 0.09 * math.sin(t * 3 + 1),
              1,
              1,
            )
            ..rotateZ(0.06 * math.sin(t)),
          child: child,
        );
      },
    );
  }
}

/// Comme [IndexedStack], mais l'onglet qui arrive apparaît en fondu (léger
/// zoom). Les onglets cachés gardent leur état, animations en pause.
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<double> _scale = Tween(begin: 0.97, end: 1.0)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void didUpdateWidget(FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      motionAllowed(context) ? _c.forward(from: 0) : _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Offstage(
            offstage: i != widget.index,
            child: TickerMode(
              enabled: i == widget.index,
              child: FadeTransition(
                opacity: i == widget.index ? _fade : kAlwaysCompleteAnimation,
                child: ScaleTransition(
                  scale: i == widget.index ? _scale : kAlwaysCompleteAnimation,
                  child: widget.children[i],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
