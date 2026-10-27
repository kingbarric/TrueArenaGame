import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The 2.5D look of the Traitors table: a tabletop seen from a chair, lit by
/// candles, with a camera that moves only for the big moments. Everything you
/// read or tap — names, votes, buttons — stays flat; only the wood, the light
/// and the camera have depth.

/// The matrix that lays a flat [size] onto [quad] — top-left, top-right,
/// bottom-right, bottom-left — in true perspective, so what's painted flat
/// (planks, grain, an envelope) foreshortens toward the far edge.
Matrix4 perspectiveOnto(Size size, List<Offset> quad) {
  final [p0, p1, p2, p3] = quad;
  final sx = p0.dx - p1.dx + p2.dx - p3.dx;
  final sy = p0.dy - p1.dy + p2.dy - p3.dy;
  double a, b, d, e, g = 0, h = 0;
  if (sx.abs() < 1e-9 && sy.abs() < 1e-9) {
    a = p1.dx - p0.dx;
    b = p2.dx - p1.dx;
    d = p1.dy - p0.dy;
    e = p2.dy - p1.dy;
  } else {
    final dx1 = p1.dx - p2.dx, dx2 = p3.dx - p2.dx;
    final dy1 = p1.dy - p2.dy, dy2 = p3.dy - p2.dy;
    final den = dx1 * dy2 - dx2 * dy1;
    g = (sx * dy2 - dx2 * sy) / den;
    h = (dx1 * sy - sx * dy1) / den;
    a = p1.dx - p0.dx + g * p1.dx;
    b = p3.dx - p0.dx + h * p3.dx;
    d = p1.dy - p0.dy + g * p1.dy;
    e = p3.dy - p0.dy + h * p3.dy;
  }
  // Column-major: the unit square onto the quad, after the flat size onto the unit square.
  return Matrix4(a, d, 0, g, b, e, 0, h, 0, 0, 1, 0, p0.dx, p0.dy, 0, 1)
      .multiplied(Matrix4.diagonal3Values(1 / size.width, 1 / size.height, 1));
}

/// Where [m] puts the flat point [p] — what the canvas does with it.
Offset projectThrough(Matrix4 m, Offset p) {
  final s = m.storage;
  final w = s[3] * p.dx + s[7] * p.dy + s[15];
  return Offset((s[0] * p.dx + s[4] * p.dy + s[12]) / w, (s[1] * p.dx + s[5] * p.dy + s[13]) / w);
}

/// Nearer seats look a little bigger: [y] down a space [height] tall, from
/// [far] at the top to [near] at the bottom.
double seatDepth(double y, double height, {double far = 0.9, double near = 1.06}) =>
    far + (near - far) * (height <= 0 ? 1 : (y / height).clamp(0.0, 1.0));

/// Soft shadows where each seat meets the floor.
class SeatShadows extends StatelessWidget {
  const SeatShadows({super.key, required this.feet});

  /// Each seat's foot point, with its depth scale.
  final List<(Offset, double)> feet;

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _SeatShadowPainter(feet)));
}

class _SeatShadowPainter extends CustomPainter {
  const _SeatShadowPainter(this.feet);
  final List<(Offset, double)> feet;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.32)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (final (at, scale) in feet) {
      canvas.drawOval(Rect.fromCenter(center: at, width: 40 * scale, height: 9 * scale), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SeatShadowPainter old) => old.feet.length != feet.length ||
      Iterable.generate(feet.length).any((i) => old.feet[i] != feet[i]);
}

/// A candle's flicker: a smoothed random walk, a dozen steps a second — enough
/// to look alive, light on the battery, and still when motion is reduced.
class _Flicker extends ChangeNotifier {
  final _rng = math.Random();
  double glow = 0.5, sway = 0;
  double _toGlow = 0.5, _toSway = 0;

  void step() {
    if (_rng.nextDouble() < 0.35) {
      _toGlow = 0.25 + _rng.nextDouble() * 0.75;
      _toSway = _rng.nextDouble() * 2 - 1;
    }
    glow += (_toGlow - glow) * 0.45;
    sway += (_toSway - sway) * 0.35;
    notifyListeners();
  }
}

/// Candlelight over a tabletop: a warm pool of light that flickers, the far
/// edge falling into shadow, and a few candles on the wood. [dim] (0–1) lowers
/// it for the night or a loss; [shape] keeps the light on the table.
class CandleLight extends StatefulWidget {
  const CandleLight({
    super.key,
    required this.shape,
    this.candles = const [],
    this.dim = 0,
    this.warmth = const Color(0xffffb760),
    this.candleScale = 1,
  });

  /// The tabletop's outline in this box.
  final Path Function(Size size) shape;

  /// Where the candles stand, as fractions of the box (0–1 across, 0–1 down).
  final List<Offset> candles;
  final double dim;
  final Color warmth;
  final double candleScale;

  @override
  State<CandleLight> createState() => _CandleLightState();
}

class _CandleLightState extends State<CandleLight> {
  final _flicker = _Flicker();
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only while it can be seen and motion is welcome.
    final live = TickerMode.valuesOf(context).enabled && !MediaQuery.disableAnimationsOf(context);
    if (live && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 80), (_) => _flicker.step());
    } else if (!live) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: TweenAnimationBuilder<double>(
            // A change of mood (dawn, a loss) fades the light rather than snapping it.
            tween: Tween(end: widget.dim.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            builder: (_, dim, __) => CustomPaint(
              key: const ValueKey('candle-light'),
              size: Size.infinite,
              painter: _CandlePainter(_flicker, widget.shape, widget.candles, dim, widget.warmth, widget.candleScale),
            ),
          ),
        ),
      );
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.flicker, this.shape, this.candles, this.dim, this.warmth, this.candleScale)
      : super(repaint: flicker);
  final _Flicker flicker;
  final Path Function(Size) shape;
  final List<Offset> candles;
  final double dim, candleScale;
  final Color warmth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final light = (1 - dim) * (0.85 + 0.15 * flicker.glow);
    canvas.save();
    canvas.clipPath(shape(size));
    // The far edge falls away into shadow — the table has depth.
    canvas.drawRect(rect, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Colors.black.withValues(alpha: 0.30 + 0.25 * dim), Colors.transparent],
      stops: const [0, 0.55],
    ).createShader(rect));
    // A warm pool of light from the candles, breathing with their flames.
    final pool = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.45),
        width: size.width * 1.2, height: size.height * 1.1);
    canvas.drawOval(pool, Paint()..shader = RadialGradient(colors: [
      warmth.withValues(alpha: 0.26 * light),
      warmth.withValues(alpha: 0.09 * light),
      Colors.transparent,
    ], stops: const [0, 0.55, 1]).createShader(pool));
    // Dimmed, the room's cold creeps in.
    if (dim > 0) canvas.drawRect(rect, Paint()..color = const Color(0xff0b1220).withValues(alpha: 0.35 * dim));
    canvas.restore();
    for (final (i, at) in candles.indexed) {
      _candle(canvas, Offset(at.dx * size.width, at.dy * size.height), light, i);
    }
  }

  void _candle(Canvas canvas, Offset base, double light, int i) {
    final s = candleScale;
    // Each flame moves a little on its own.
    final sway = flicker.sway * (i.isEven ? 1 : -0.7) * 1.6 * s;
    final flameH = (11 + 3 * flicker.glow) * s;
    canvas.drawOval(Rect.fromCenter(center: base, width: 16 * s, height: 5 * s),
        Paint()..color = Colors.black.withValues(alpha: 0.35));
    final body = Rect.fromLTWH(base.dx - 4 * s, base.dy - 18 * s, 8 * s, 18 * s);
    canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(2 * s)), Paint()..shader = const LinearGradient(
      colors: [Color(0xffe9d9bb), Color(0xfffff6e4), Color(0xffcdb48c)],
    ).createShader(body));
    final wick = Offset(base.dx, body.top);
    canvas.drawLine(wick, wick.translate(0, -2.5 * s), Paint()..color = const Color(0xff2a1a10)..strokeWidth = 1.2 * s);
    // The halo, then the flame: a teardrop leaning with the draught.
    final glow = 28 * s * (0.9 + 0.2 * flicker.glow);
    canvas.drawCircle(wick.translate(sway, -6 * s), glow, Paint()..shader = RadialGradient(colors: [
      warmth.withValues(alpha: 0.45 * light),
      Colors.transparent,
    ]).createShader(Rect.fromCircle(center: wick.translate(sway, -6 * s), radius: glow)));
    final tip = wick.translate(sway * 1.6, -flameH);
    final flame = Path()
      ..moveTo(wick.dx, wick.dy - 1 * s)
      ..quadraticBezierTo(wick.dx + 4.2 * s, wick.dy - flameH * 0.35, tip.dx, tip.dy)
      ..quadraticBezierTo(wick.dx - 4.2 * s, wick.dy - flameH * 0.35, wick.dx, wick.dy - 1 * s)
      ..close();
    canvas.drawPath(flame, Paint()..shader = LinearGradient(
      begin: Alignment.bottomCenter, end: Alignment.topCenter,
      colors: [const Color(0xffff7a1a).withValues(alpha: 0.5 + 0.5 * light), const Color(0xffffe08a), const Color(0xfffff8e6)],
    ).createShader(flame.getBounds()));
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.dim != dim || old.warmth != warmth || old.candles != candles || old.candleScale != candleScale;
}

/// The camera on the table: still most of the time, it leans in for the big
/// moments — a slow push toward the middle, a sweep toward whoever's leaving.
/// Motion-reduced, it never moves.
class TableCamera extends StatelessWidget {
  const TableCamera({
    super.key,
    required this.child,
    this.zoom = 1,
    this.focus = Alignment.center,
    this.duration = const Duration(milliseconds: 1400),
  });

  final Widget child;
  final double zoom;

  /// The point it leans toward, which stays put while everything else grows around it.
  final Alignment focus;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final z = still ? 1.0 : zoom;
    return ClipRect(
      child: AnimatedContainer(
        key: const ValueKey('table-camera'),
        duration: still ? Duration.zero : duration,
        curve: Curves.easeInOutCubic,
        transform: Matrix4.diagonal3Values(z, z, 1),
        transformAlignment: focus,
        child: child,
      ),
    );
  }
}

/// The sealed letter arriving: it slides up from the table, turning straight
/// and growing as it comes close enough to read. Motion-reduced, it's simply there.
class LetterArrival extends StatelessWidget {
  const LetterArrival({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: const ValueKey('letter-arrival'),
        tween: Tween(begin: 0, end: 1),
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 750),
        curve: Curves.easeOutBack,
        builder: (_, t, letter) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.translationValues(0, 60 * (1 - t), 0)
              ..multiply(Matrix4.rotationZ(-0.09 * (1 - t)))
              ..multiply(Matrix4.diagonal3Values(0.6 + 0.4 * t, 0.6 + 0.4 * t, 1)),
            child: letter,
          ),
        ),
        child: child,
      );
}
