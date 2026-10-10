import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The lived-in look shared by the board games: old rusty wood for frames,
/// a little grime on playing surfaces, and pieces drawn like real ones.
/// Everything is painted (no image assets) and deterministic per seed, so
/// nothing shimmers between frames.

/// A real-looking draughts man, drawn flat: a soft shadow, the disc's
/// edge showing underneath (so it has thickness), a bevelled top lit from
/// the top-left, ridged rings like a turned wooden piece, a sunk centre and
/// a shine. Always ringed with a pale halo so a dark piece never melts into
/// a dark square.
class RealPiecePainter extends CustomPainter {
  const RealPiecePainter({required this.top, required this.mid, required this.rim, required this.glowing});
  final Color top;
  final Color mid;
  final Color rim;
  final bool glowing;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2 - s * 0.03);
    final r = s * 0.44;

    // Shadow on the board.
    canvas.drawCircle(
        c + Offset(s * 0.03, s * 0.09),
        r,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.07));
    if (glowing) {
      canvas.drawCircle(
          c,
          r * 1.12,
          Paint()
            ..color = const Color(0xffe0a94a).withValues(alpha: 0.85)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.12));
    }
    // The edge of the disc, seen below the top face — its thickness.
    final edge = c + Offset(0, s * 0.065);
    canvas.drawCircle(edge, r, Paint()..color = Color.lerp(rim, Colors.black, 0.35)!);
    canvas.drawCircle(
        edge,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.02
          ..color = Colors.black.withValues(alpha: 0.45));
    // Pale halo for contrast against any square.
    canvas.drawCircle(
        c,
        r + s * 0.022,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.03
          ..color = glowing ? const Color(0xffffd879) : Colors.white.withValues(alpha: 0.7));
    // Top face.
    final face = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
              center: const Alignment(-0.35, -0.45),
              radius: 1.05,
              colors: [top, mid, Color.lerp(mid, rim, 0.55)!],
              stops: const [0, 0.6, 1]).createShader(face));
    // Bevel: lit top-left, shaded bottom-right.
    canvas.drawCircle(
        c,
        r - s * 0.025,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.05
          ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
            Colors.white.withValues(alpha: 0.45),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.4),
          ]).createShader(face));
    // Turned ridges.
    for (final (fraction, light) in const [(0.78, false), (0.72, true), (0.6, false), (0.55, true)]) {
      canvas.drawCircle(
          c,
          r * fraction,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.016
            ..color = light ? Colors.white.withValues(alpha: 0.22) : rim.withValues(alpha: 0.75));
    }
    // A slightly sunk centre.
    final inner = Rect.fromCircle(center: c, radius: r * 0.46);
    canvas.drawCircle(
        c,
        r * 0.46,
        Paint()
          ..shader = RadialGradient(
              center: const Alignment(0.3, 0.35),
              radius: 1,
              colors: [mid, Color.lerp(mid, Colors.black, 0.18)!]).createShader(inner));
    // Wear: a few tiny nicks on the face.
    final rnd = math.Random(mid.toARGB32());
    for (var i = 0; i < 5; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final d = r * (0.3 + rnd.nextDouble() * 0.6);
      canvas.drawCircle(c + Offset(math.cos(a) * d, math.sin(a) * d), s * (0.006 + rnd.nextDouble() * 0.01),
          Paint()..color = Colors.black.withValues(alpha: 0.18));
    }
    // Shine.
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 0.82),
        math.pi * 1.05,
        math.pi * 0.55,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.05
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.32));
  }

  @override
  bool shouldRepaint(covariant RealPiecePainter old) =>
      old.top != top || old.mid != mid || old.rim != rim || old.glowing != glowing;
}

/// Years of play on a square: dust specks, a faint stain or two, the odd
/// scuff, and darker corners. Light squares pick up brown dirt; dark ones
/// pale dust — never enough to blur black from white.
class GrimePainter extends CustomPainter {
  const GrimePainter(
      {required this.base,
      required this.dark,
      required this.seed,
      this.overlay = false,
      this.density = 1,
      this.corners = true});
  final Color base;
  final bool dark;
  final int seed;

  /// More for a whole board than for one square.
  final double density;

  /// Darker worn corners — right for a square, not for a whole board.
  final bool corners;

  /// Painted on top of another fill (so no base colour of its own).
  final bool overlay;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (!overlay) canvas.drawRect(rect, Paint()..color = base);
    final rnd = math.Random(seed * 7919 + 13);
    final dirt = dark ? const Color(0xffd8d2c4) : const Color(0xff5c4a2e);
    // A stain or two.
    final stains = (rnd.nextInt(3) * density).round();
    for (var i = 0; i < stains; i++) {
      final center = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final radius =
          (density <= 1 ? size.width : size.width / math.sqrt(density) * 2.5) * (0.18 + rnd.nextDouble() * 0.3);
      canvas.drawCircle(
          center,
          radius,
          Paint()
            ..shader = RadialGradient(colors: [
              dirt.withValues(alpha: dark ? 0.06 : 0.1),
              dirt.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: center, radius: radius)));
    }
    // Dust specks.
    final specks = ((10 + rnd.nextInt(14)) * density).round();
    for (var i = 0; i < specks; i++) {
      canvas.drawCircle(
          Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
          (density <= 1 ? size.width : size.width / math.sqrt(density)) * (0.006 + rnd.nextDouble() * 0.016),
          Paint()..color = dirt.withValues(alpha: 0.12 + rnd.nextDouble() * 0.22));
    }
    // A scuff now and then.
    final scuffs = density <= 1 ? (rnd.nextDouble() < 0.45 ? 1 : 0) : (density * 0.45).round();
    for (var i = 0; i < scuffs; i++) {
      final start = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final reach = density <= 1 ? size.width : size.width / math.sqrt(density);
      final end = start + Offset((rnd.nextDouble() - 0.5) * reach * 0.7, (rnd.nextDouble() - 0.5) * reach * 0.3);
      canvas.drawLine(
          start,
          end,
          Paint()
            ..strokeWidth = 0.8
            ..strokeCap = StrokeCap.round
            ..color = (dark ? Colors.white : Colors.black).withValues(alpha: 0.13));
    }
    // Darker, worn corners.
    if (corners)
      canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(radius: 0.9, colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: dark ? 0.18 : 0.1),
            ]).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant GrimePainter old) =>
      old.base != base || old.dark != dark || old.seed != seed || old.density != density;
}

/// The frame: old wood gone rusty-brown — heavy grain, dark knots, pale
/// scratches, rust bleeding from the nails in each corner, worn edges.
class RustyWoodPainter extends CustomPainter {
  const RustyWoodPainter({required this.top, required this.bottom});
  final Color top;
  final Color bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rnd = math.Random(4211);
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [top, bottom])
              .createShader(rect));
    // Grain.
    for (var i = 0; i < 70; i++) {
      final horizontal = rnd.nextBool();
      final along = horizontal ? size.width : size.height;
      final across = rnd.nextDouble() * (horizontal ? size.height : size.width);
      final path = Path();
      for (var k = 0; k <= 8; k++) {
        final t = along * k / 8;
        final wobble = (rnd.nextDouble() - 0.5) * 3;
        final p = horizontal ? Offset(t, across + wobble) : Offset(across + wobble, t);
        k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6 + rnd.nextDouble() * 1.4
            ..color = Colors.black.withValues(alpha: 0.08 + rnd.nextDouble() * 0.16));
    }
    // Knots.
    for (var i = 0; i < 6; i++) {
      final c = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final r = 2.5 + rnd.nextDouble() * 4;
      canvas.drawOval(Rect.fromCenter(center: c, width: r * 2.6, height: r * 1.4),
          Paint()..color = const Color(0xff2a1406).withValues(alpha: 0.55));
      canvas.drawOval(
          Rect.fromCenter(center: c, width: r * 4, height: r * 2.2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = Colors.black.withValues(alpha: 0.25));
    }
    // Rust stains.
    for (var i = 0; i < 9; i++) {
      final c = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final r = 8 + rnd.nextDouble() * 22;
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              const Color(0xffb5531a).withValues(alpha: 0.28),
              const Color(0xffb5531a).withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: c, radius: r)));
    }
    // Scratches.
    for (var i = 0; i < 22; i++) {
      final a = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final b = a + Offset((rnd.nextDouble() - 0.5) * 30, (rnd.nextDouble() - 0.5) * 10);
      canvas.drawLine(
          a,
          b,
          Paint()
            ..strokeWidth = 0.7
            ..color = const Color(0xfff0d0a0).withValues(alpha: 0.12 + rnd.nextDouble() * 0.12));
    }
    // Rusty nails in the corners, rust running from them.
    for (final corner in [
      const Offset(5, 5),
      Offset(size.width - 5, 5),
      Offset(5, size.height - 5),
      Offset(size.width - 5, size.height - 5),
    ]) {
      canvas.drawCircle(
          corner,
          7,
          Paint()
            ..shader = RadialGradient(colors: [
              const Color(0xff8a3b12).withValues(alpha: 0.6),
              const Color(0xff8a3b12).withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: corner, radius: 7)));
      canvas.drawCircle(
          corner,
          2.6,
          Paint()
            ..shader =
                const RadialGradient(center: Alignment(-0.4, -0.4), colors: [Color(0xffc98a52), Color(0xff6b2e0e)])
                    .createShader(Rect.fromCircle(center: corner, radius: 2.6)));
    }
    // Worn, lighter edges where hands have rubbed it.
    canvas.drawRect(
        rect.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xffe0b07a).withValues(alpha: 0.18));
  }

  @override
  bool shouldRepaint(covariant RustyWoodPainter old) => old.top != top || old.bottom != bottom;
}

/// A card-table cloth that's seen some games: worn, paler patches where
/// cards slide, a couple of faint cup rings, flecks of lint and fluff.
class WornFeltPainter extends CustomPainter {
  const WornFeltPainter({this.seed = 5});
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    // Worn, paler patches.
    for (var i = 0; i < 6; i++) {
      final c = Offset(size.width * (0.2 + rnd.nextDouble() * 0.6), size.height * (0.2 + rnd.nextDouble() * 0.6));
      final r = size.shortestSide * (0.12 + rnd.nextDouble() * 0.18);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              const Color(0xffd9f0c0).withValues(alpha: 0.07),
              const Color(0xffd9f0c0).withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: c, radius: r)));
    }
    // Darker stains.
    for (var i = 0; i < 5; i++) {
      final c = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final r = size.shortestSide * (0.05 + rnd.nextDouble() * 0.1);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              Colors.black.withValues(alpha: 0.12),
              Colors.black.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: c, radius: r)));
    }
    // A couple of faint cup rings.
    for (var i = 0; i < 2; i++) {
      final c = Offset(size.width * (0.1 + rnd.nextDouble() * 0.8), size.height * (0.1 + rnd.nextDouble() * 0.8));
      final r = 12 + rnd.nextDouble() * 8;
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = const Color(0xff2b1a0c).withValues(alpha: 0.13));
    }
    // Lint and fluff.
    for (var i = 0; i < 160; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final light = rnd.nextBool();
      if (rnd.nextDouble() < 0.25) {
        final q = p + Offset((rnd.nextDouble() - 0.5) * 7, (rnd.nextDouble() - 0.5) * 7);
        canvas.drawLine(
            p,
            q,
            Paint()
              ..strokeWidth = 0.7
              ..color = (light ? Colors.white : Colors.black).withValues(alpha: 0.1 + rnd.nextDouble() * 0.12));
      } else {
        canvas.drawCircle(p, 0.5 + rnd.nextDouble() * 1.1,
            Paint()..color = (light ? Colors.white : Colors.black).withValues(alpha: 0.08 + rnd.nextDouble() * 0.12));
      }
    }
  }

  @override
  bool shouldRepaint(covariant WornFeltPainter old) => old.seed != seed;
}

/// A well-used playing card: the paper slightly yellowed toward the edges,
/// a few specks, a soft crease and rubbed corners. Faint — the card stays
/// easy to read.
class WornPaperPainter extends CustomPainter {
  const WornPaperPainter({required this.seed, this.back = false});
  final int seed;

  /// The patterned back (darker) rather than the paper face.
  final bool back;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rnd = math.Random(seed * 31 + 7);
    // Yellowing toward the edges.
    canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(radius: 0.95, colors: [
            Colors.transparent,
            (back ? Colors.black : const Color(0xff8a6a2c)).withValues(alpha: back ? 0.22 : 0.16),
          ]).createShader(rect));
    // Specks.
    for (var i = 0; i < 9; i++) {
      canvas.drawCircle(
          Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
          0.4 + rnd.nextDouble() * 0.9,
          Paint()
            ..color =
                (back ? Colors.white : const Color(0xff5c4422)).withValues(alpha: 0.12 + rnd.nextDouble() * 0.15));
    }
    // A soft crease.
    if (rnd.nextDouble() < 0.6) {
      final y = size.height * (0.25 + rnd.nextDouble() * 0.5);
      canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y + (rnd.nextDouble() - 0.5) * 8),
          Paint()
            ..strokeWidth = 0.8
            ..color = Colors.white.withValues(alpha: back ? 0.1 : 0.35));
      canvas.drawLine(
          Offset(0, y + 1),
          Offset(size.width, y + 1 + (rnd.nextDouble() - 0.5) * 8),
          Paint()
            ..strokeWidth = 0.6
            ..color = Colors.black.withValues(alpha: 0.08));
    }
    // Rubbed corners.
    for (final corner in [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height)
    ]) {
      canvas.drawCircle(
          corner,
          size.shortestSide * 0.22,
          Paint()
            ..shader = RadialGradient(colors: [
              (back ? Colors.white : const Color(0xff7a5a28)).withValues(alpha: back ? 0.08 : 0.14),
              Colors.transparent,
            ]).createShader(Rect.fromCircle(center: corner, radius: size.shortestSide * 0.22)));
    }
  }

  @override
  bool shouldRepaint(covariant WornPaperPainter old) => old.seed != seed || old.back != back;
}
