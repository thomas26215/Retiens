import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/subject.dart';
import 'motion.dart';

/// Affiche [builder] par-dessus toute l'app pendant [duration], sans bloquer
/// les touches, puis le retire.
void _showOverlay(
  BuildContext context,
  Duration duration,
  Widget Function(Animation<double> t) builder,
) {
  if (!motionAllowed(context)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: _OverlayAnimation(
        duration: duration,
        onDone: () => entry.remove(),
        builder: builder,
      ),
    ),
  );
  overlay.insert(entry);
}

class _OverlayAnimation extends StatefulWidget {
  const _OverlayAnimation({
    required this.duration,
    required this.onDone,
    required this.builder,
  });

  final Duration duration;
  final VoidCallback onDone;
  final Widget Function(Animation<double> t) builder;

  @override
  State<_OverlayAnimation> createState() => _OverlayAnimationState();
}

class _OverlayAnimationState extends State<_OverlayAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onDone();
        })
        ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_c);
}

/// Centre d'un widget à l'écran (pour faire partir une animation de là).
Offset? centerOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(box.size.center(Offset.zero));
}

// --- Confettis ---------------------------------------------------------------

/// Pluie de confettis tirés depuis le haut de l'écran.
void showConfetti(BuildContext context, {int count = 140}) {
  final colors = [
    for (final c in subjectPalette) Color(c),
    const Color(0xFFFFFFFF),
  ];
  final rnd = math.Random();
  final pieces = List.generate(count, (i) {
    final angle = -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 0.9;
    final speed = 520 + rnd.nextDouble() * 760;
    return _Piece(
      start: Offset(0.2 + rnd.nextDouble() * 0.6, 0.32 + rnd.nextDouble() * 0.06),
      velocity: Offset(math.cos(angle), math.sin(angle)) * speed,
      color: colors[rnd.nextInt(colors.length)],
      size: 6 + rnd.nextDouble() * 6,
      spin: (rnd.nextDouble() - 0.5) * 14,
      wobble: rnd.nextDouble() * math.pi * 2,
      round: rnd.nextDouble() < 0.3,
      delay: rnd.nextDouble() * 0.12,
    );
  });
  _showOverlay(
    context,
    const Duration(milliseconds: 2800),
    (t) => CustomPaint(
      size: Size.infinite,
      painter: _ConfettiPainter(t, pieces),
    ),
  );
}

class _Piece {
  const _Piece({
    required this.start,
    required this.velocity,
    required this.color,
    required this.size,
    required this.spin,
    required this.wobble,
    required this.round,
    required this.delay,
  });

  final Offset start;
  final Offset velocity;
  final Color color;
  final double size;
  final double spin;
  final double wobble;
  final bool round;
  final double delay;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.pieces) : super(repaint: t);

  final Animation<double> t;
  final List<_Piece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    const total = 2.8; // secondes
    final paint = Paint();
    for (final p in pieces) {
      final s = (t.value * total - p.delay * total).clamp(0.0, total);
      if (s <= 0) continue;
      // Frottement de l'air puis gravité : montée rapide, chute en douceur.
      final drag = (1 - math.exp(-2.2 * s)) / 2.2;
      final x = p.start.dx * size.width + p.velocity.dx * drag +
          math.sin(p.wobble + s * 5) * 14;
      final y = p.start.dy * size.height + p.velocity.dy * drag + 260 * s * s;
      final fade = (1 - (t.value - 0.7) / 0.3).clamp(0.0, 1.0);
      paint.color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * s);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size * 0.45, paint);
      } else {
        // Le ruban tourne sur lui-même : sa largeur apparente varie.
        final w = p.size * (0.35 + 0.65 * math.cos(p.wobble + s * 9).abs());
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: w, height: p.size * 0.55),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}

// --- Éclat de notation -------------------------------------------------------

/// Éclat autour de [center] : icône qui jaillit, onde, étincelles et petit
/// texte qui s'envole (« +6 j », « Demain »…).
void showBurst(
  BuildContext context, {
  required Offset center,
  required IconData icon,
  required Color color,
  String? label,
  int sparks = 12,
}) {
  final rnd = math.Random();
  final dirs = List.generate(sparks, (i) {
    final a = i / sparks * math.pi * 2 + rnd.nextDouble() * 0.4;
    return (a, 46 + rnd.nextDouble() * 34, 3 + rnd.nextDouble() * 3.5);
  });
  final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
      );
  _showOverlay(
    context,
    const Duration(milliseconds: 1000),
    (t) => AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final v = t.value;
        final pop = Curves.elasticOut.transform((v / 0.55).clamp(0.0, 1.0));
        final fade = (1 - ((v - 0.6) / 0.4)).clamp(0.0, 1.0);
        final rise = Curves.easeOutCubic.transform(v) * 46;
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _BurstPainter(v, center, color, dirs),
              ),
            ),
            Positioned(
              left: center.dx - 40,
              top: center.dy - 26 - rise,
              width: 80,
              child: Opacity(
                opacity: fade,
                child: Column(
                  children: [
                    Transform.scale(
                      scale: 0.3 + 0.9 * pop,
                      child: Icon(icon, color: color, size: 40),
                    ),
                    if (label != null)
                      Text(label, style: textStyle, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.v, this.center, this.color, this.dirs);

  final double v;
  final Offset center;
  final Color color;
  final List<(double, double, double)> dirs;

  @override
  void paint(Canvas canvas, Size size) {
    // Onde qui s'élargit et s'efface.
    final ring = Curves.easeOutCubic.transform((v / 0.6).clamp(0.0, 1.0));
    canvas.drawCircle(
      center,
      12 + 58 * ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1 - ring) + 0.5
        ..color = color.withValues(alpha: 0.55 * (1 - ring)),
    );
    // Étincelles projetées puis freinées.
    final s = Curves.easeOutQuart.transform((v / 0.7).clamp(0.0, 1.0));
    final fade = (1 - v / 0.8).clamp(0.0, 1.0);
    final paint = Paint()..color = color.withValues(alpha: fade);
    for (final (a, dist, r) in dirs) {
      final p = center + Offset(math.cos(a), math.sin(a)) * (14 + dist * s);
      canvas.drawCircle(p, r * (1 - 0.6 * s), paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.v != v;
}

// --- Bannière ---------------------------------------------------------------

/// Bannière qui jaillit en haut de l'écran puis s'efface (journée terminée,
/// série, souvenir solide…).
void showBanner(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? subtitle,
  Color? color,
  Duration delay = Duration.zero,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final accent = color ?? scheme.primary;
  const total = Duration(milliseconds: 2600);
  final start = delay.inMilliseconds / (delay + total).inMilliseconds;
  _showOverlay(
    context,
    delay + total,
    (t) => AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final v = ((t.value - start) / (1 - start)).clamp(0.0, 1.0);
        if (v == 0) return const SizedBox.shrink();
        final inT = Curves.elasticOut.transform((v / 0.3).clamp(0.0, 1.0));
        final out = Curves.easeIn.transform(((v - 0.8) / 0.2).clamp(0.0, 1.0));
        return SafeArea(
          child: Align(
            alignment: const Alignment(0, -0.82),
            child: Opacity(
              opacity: (1 - out) * (v / 0.08).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, -30 * out),
                child: Transform.scale(
                  scale: 0.6 + 0.4 * inT,
                  child: Material(
                    elevation: 8,
                    shadowColor: Colors.black38,
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 22, 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Transform.rotate(
                              angle: (1 - inT) * -0.6,
                              child: Icon(icon, color: accent, size: 26),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: theme.textTheme.titleMedium),
                                if (subtitle != null)
                                  Text(
                                    subtitle,
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
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
