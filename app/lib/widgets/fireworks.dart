import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Celebratory fireworks for a win screen.
///
/// Drawn on a canvas rather than assembled from widgets: a few hundred
/// sparks each frame is nothing for a painter and impossible for the widget
/// tree. Every particle's position is computed from its age — launch
/// velocity, gravity and drag — so there's no simulation state to keep in
/// step and a dropped frame can't drift the animation.
///
/// Purely decorative, and it says so: it takes no taps, and it stands still
/// for anyone who has asked the system to reduce motion.
class Fireworks extends StatefulWidget {
  const Fireworks({super.key, this.colors = const [], this.burstInterval = const Duration(milliseconds: 620)});

  /// Shell colours to draw from. Defaults to a warm celebratory set.
  final List<Color> colors;

  /// Roughly how often a new shell goes up.
  final Duration burstInterval;

  @override
  State<Fireworks> createState() => _FireworksState();
}

class _FireworksState extends State<Fireworks> with SingleTickerProviderStateMixin {
  /// Drives repaints without rebuilding the widget tree.
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  final List<_Burst> _bursts = [];
  final math.Random _rng = math.Random();

  late final Ticker _ticker = createTicker(_onTick);
  double _nextBurstAt = 0;

  static const _defaultColors = [
    Color(0xffffc857), // gold
    Color(0xffff6b93), // rose
    Color(0xff7fcfa0), // jade
    Color(0xfffff2cc), // near-white sparkle
    Color(0xff9ad0ff), // cool blue
  ];

  List<Color> get _palette => widget.colors.isEmpty ? _defaultColors : widget.colors;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (t >= _nextBurstAt) {
      _spawn(t);
      // Vary the gap so the shells don't fall into a metronome.
      final base = widget.burstInterval.inMilliseconds / 1000;
      _nextBurstAt = t + base * (0.55 + _rng.nextDouble() * 0.9);
    }
    _bursts.removeWhere((b) => t - b.birth > b.life);
    _time.value = t;
  }

  void _spawn(double now) {
    // Kept in fractions of the canvas so the burst lands sensibly whatever
    // size it's given.
    final origin = Offset(0.12 + _rng.nextDouble() * 0.76, 0.16 + _rng.nextDouble() * 0.42);
    final colour = _palette[_rng.nextInt(_palette.length)];
    final count = 34 + _rng.nextInt(26);
    final speed = 0.24 + _rng.nextDouble() * 0.16;
    // A slight squash makes a burst read as a sphere seen edge-on rather
    // than a flat ring.
    final squash = 0.78 + _rng.nextDouble() * 0.3;

    final particles = List<_Spark>.generate(count, (i) {
      // Even angular spread with a little jitter — evenly spaced alone looks
      // mechanical, fully random leaves gaps.
      final angle = (i / count) * math.pi * 2 + _rng.nextDouble() * 0.22;
      final v = speed * (0.55 + _rng.nextDouble() * 0.45);
      return _Spark(
        dx: math.cos(angle) * v,
        dy: math.sin(angle) * v * squash,
        size: 1.4 + _rng.nextDouble() * 1.8,
      );
    });

    _bursts.add(_Burst(
      birth: now,
      life: 1.5 + _rng.nextDouble() * 0.7,
      origin: origin,
      colour: colour,
      sparks: particles,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Someone who has asked for less motion gets a still night sky rather
    // than a display they can't turn off.
    if (MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.expand();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _FireworksPainter(time: _time, bursts: _bursts),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Spark {
  const _Spark({required this.dx, required this.dy, required this.size});

  /// Launch velocity, in canvas fractions per second.
  final double dx;
  final double dy;
  final double size;
}

class _Burst {
  const _Burst({
    required this.birth,
    required this.life,
    required this.origin,
    required this.colour,
    required this.sparks,
  });

  final double birth;
  final double life;
  final Offset origin;
  final Color colour;
  final List<_Spark> sparks;
}

class _FireworksPainter extends CustomPainter {
  _FireworksPainter({required this.time, required this.bursts}) : super(repaint: time);

  final ValueNotifier<double> time;
  final List<_Burst> bursts;

  /// Downward pull, in canvas fractions per second squared.
  static const double _gravity = 0.32;

  /// How quickly a spark loses its launch speed.
  static const double _drag = 1.9;

  @override
  void paint(Canvas canvas, Size size) {
    final now = time.value;
    final paint = Paint()..blendMode = BlendMode.plus; // sparks add light where they overlap

    for (final burst in bursts) {
      final age = now - burst.birth;
      if (age < 0) continue;
      final progress = (age / burst.life).clamp(0.0, 1.0);

      // Fades late rather than immediately, then drops off fast — a shell
      // hangs before it dies.
      final fade = progress < 0.55 ? 1.0 : 1.0 - ((progress - 0.55) / 0.45);
      if (fade <= 0) continue;

      // Integrated velocity under linear drag, so sparks slow as they fly.
      final travel = (1 - math.exp(-_drag * age)) / _drag;
      final fall = 0.5 * _gravity * age * age;

      for (final spark in burst.sparks) {
        final x = (burst.origin.dx + spark.dx * travel) * size.width;
        final y = (burst.origin.dy + spark.dy * travel + fall) * size.height;
        if (y > size.height + 8) continue;

        final alpha = (fade * (0.55 + 0.45 * (1 - progress))).clamp(0.0, 1.0);
        paint.color = burst.colour.withValues(alpha: alpha);

        // A short trail pointing back the way it came reads as motion far
        // better than a round dot does.
        final trail = Offset(spark.dx, spark.dy) * (0.045 * size.width * (1 - progress));
        paint.strokeWidth = spark.size * (1 - progress * 0.45);
        paint.strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(x, y), Offset(x - trail.dx, y - trail.dy), paint);
      }

      // The flash at the heart of a fresh burst.
      if (progress < 0.16) {
        final glow = (1 - progress / 0.16);
        canvas.drawCircle(
          Offset(burst.origin.dx * size.width, burst.origin.dy * size.height),
          10 + 26 * glow,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = burst.colour.withValues(alpha: 0.22 * glow)
            ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 14),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FireworksPainter oldDelegate) => true;
}
