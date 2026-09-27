import 'package:flutter/material.dart';

/// Shared shell for every faded background motif on this page — the same
/// decorative role `_BlobField` plays on the welcome screen (texture behind
/// the content, not a real illustration asset). Drawn with `CustomPainter`
/// rather than bundled images, so there's no asset pipeline to manage and
/// every motif re-tints cleanly for light/dark theme.
class _Motif extends StatelessWidget {
  const _Motif({required this.painter, required this.size, required this.opacity, this.rotation = 0});

  final CustomPainter painter;
  final double size;
  final double opacity;
  final double rotation;

  @override
  Widget build(BuildContext context) {
    Widget child = SizedBox(width: size, height: size, child: CustomPaint(painter: painter));
    if (rotation != 0) child = Transform.rotate(angle: rotation, child: child);
    return ExcludeSemantics(child: Opacity(opacity: opacity, child: child));
  }
}

/// An African djembe drum with its mallet resting against it — the flagship
/// motif, used on Home and the sign-up screen.
class DrumMotif extends StatelessWidget {
  const DrumMotif({super.key, required this.color, this.size = 340, this.opacity = 0.16, this.rotation = 0});

  final Color color;
  final double size;
  final double opacity;
  final double rotation;

  @override
  Widget build(BuildContext context) =>
      _Motif(painter: _DrumPainter(color), size: size, opacity: opacity, rotation: rotation);
}

/// A single six-sided die, pips up — a small, playful counterpoint to the
/// drum and cup's warmer, more "gather round" shapes.
class DiceMotif extends StatelessWidget {
  const DiceMotif({super.key, required this.color, this.size = 160, this.opacity = 0.16, this.rotation = -0.18});

  final Color color;
  final double size;
  final double opacity;
  final double rotation;

  @override
  Widget build(BuildContext context) =>
      _Motif(painter: _DicePainter(color), size: size, opacity: opacity, rotation: rotation);
}

/// A carved African palm-wine cup (calabash-style tumbler) — the third of
/// the set, evoking the same "everyone's gathered, drums out, dice on the
/// table" scene as the other two.
class PalmWineCupMotif extends StatelessWidget {
  const PalmWineCupMotif({super.key, required this.color, this.size = 220, this.opacity = 0.16, this.rotation = 0});

  final Color color;
  final double size;
  final double opacity;
  final double rotation;

  @override
  Widget build(BuildContext context) =>
      _Motif(painter: _CupPainter(color), size: size, opacity: opacity, rotation: rotation);
}

/// The same drum/dice/cup set as Home/Welcome, but tinted with the theme's
/// own accents (gold/brand/jade) instead of a flat ink tone, and faded
/// further still (0.05-0.07 vs. their usual 0.16) — a game screen is read
/// and tapped constantly, so the texture has to sit further back than it
/// does on a screen someone just glances at once. Drop this in as the first
/// child of a `Stack` behind a game screen's real content.
class GameBackdropMotifs extends StatelessWidget {
  const GameBackdropMotifs({super.key, required this.gold, required this.brand, required this.jade});

  final Color gold;
  final Color brand;
  final Color jade;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Stack(children: [
        Positioned(left: -34, top: -10, child: DiceMotif(color: gold, size: 120, opacity: 0.06, rotation: -0.24)),
        Positioned(right: -26, top: 40, child: PalmWineCupMotif(color: brand, size: 150, opacity: 0.055, rotation: 0.12)),
        Positioned(
          left: -70,
          bottom: -30,
          child: DrumMotif(color: jade, size: 230, opacity: 0.06, rotation: 0.08),
        ),
      ]),
    );
  }
}

class _DrumPainter extends CustomPainter {
  _DrumPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final fill = Paint()..color = color..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.014
      ..strokeCap = StrokeCap.round;

    // ---- djembe body: a goblet shape (wide cupped top, narrow waist, small foot) ----
    final body = Path()
      ..moveTo(w * 0.20, h * 0.06)
      ..quadraticBezierTo(w * 0.14, h * 0.22, w * 0.30, h * 0.40)
      ..quadraticBezierTo(w * 0.40, h * 0.50, w * 0.38, h * 0.68)
      ..quadraticBezierTo(w * 0.36, h * 0.86, w * 0.30, h * 0.94)
      ..lineTo(w * 0.62, h * 0.94)
      ..quadraticBezierTo(w * 0.56, h * 0.86, w * 0.54, h * 0.68)
      ..quadraticBezierTo(w * 0.52, h * 0.50, w * 0.62, h * 0.40)
      ..quadraticBezierTo(w * 0.78, h * 0.22, w * 0.72, h * 0.06)
      ..close();
    canvas.drawPath(body, fill);

    // top drumhead rim (an ellipse "lid" over the cupped top)
    canvas.drawOval(Rect.fromLTWH(w * 0.17, h * 0.015, w * 0.58, h * 0.09), fill);

    // two tuning-rope bands across the shoulder of the drum
    for (final t in [0.32, 0.42]) {
      final path = Path()
        ..moveTo(w * (0.20 + t * 0.10), h * t)
        ..quadraticBezierTo(w * 0.5, h * (t + 0.05), w * (0.80 - t * 0.10), h * t);
      canvas.drawPath(path, stroke);
    }

    // ---- stick: a mallet resting diagonally against the drum ----
    canvas.save();
    canvas.translate(w * 0.86, h * 0.30);
    canvas.rotate(0.62); // lean it against the drum
    final handle = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w * 0.05, height: h * 0.62),
      Radius.circular(w * 0.03),
    );
    canvas.drawRRect(handle, fill);
    canvas.drawCircle(Offset(0, -h * 0.34), w * 0.055, fill); // mallet head
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DrumPainter oldDelegate) => oldDelegate.color != color;
}

class _DicePainter extends CustomPainter {
  _DicePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final fill = Paint()..color = color..style = PaintingStyle.fill;

    // the cube face — a rounded square, inset so the stroke-free silhouette
    // still reads clearly at low opacity
    final face = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, h * 0.08, w * 0.84, h * 0.84),
      Radius.circular(w * 0.16),
    );
    // punch the pips out of the face rather than drawing solid dots over it —
    // reads as a die face rather than a rounded square with spots stuck on
    final facePath = Path()..addRRect(face);
    final pipsPath = Path();
    void pip(double cx, double cy) => pipsPath.addOval(Rect.fromCircle(center: Offset(w * cx, h * cy), radius: w * 0.075));
    // five pips
    pip(0.28, 0.28);
    pip(0.72, 0.28);
    pip(0.50, 0.50);
    pip(0.28, 0.72);
    pip(0.72, 0.72);

    canvas.drawPath(Path.combine(PathOperation.difference, facePath, pipsPath), fill);
  }

  @override
  bool shouldRepaint(covariant _DicePainter oldDelegate) => oldDelegate.color != color;
}

class _CupPainter extends CustomPainter {
  _CupPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final fill = Paint()..color = color..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.02
      ..strokeCap = StrokeCap.round;

    // ---- calabash tumbler: a rounded-bottom bowl on a short foot, carved rim ----
    final body = Path()
      ..moveTo(w * 0.22, h * 0.30)
      ..quadraticBezierTo(w * 0.18, h * 0.62, w * 0.30, h * 0.80)
      ..quadraticBezierTo(w * 0.40, h * 0.92, w * 0.50, h * 0.92)
      ..quadraticBezierTo(w * 0.60, h * 0.92, w * 0.70, h * 0.80)
      ..quadraticBezierTo(w * 0.82, h * 0.62, w * 0.78, h * 0.30)
      ..close();
    canvas.drawPath(body, fill);

    // rim (a wide flat ellipse — the open top of the cup)
    canvas.drawOval(Rect.fromLTWH(w * 0.20, h * 0.24, w * 0.60, h * 0.13), fill);

    // a couple of carved rings around the belly, echoing traditional tooling
    for (final t in [0.52, 0.66]) {
      final ring = Path()
        ..moveTo(w * 0.26, h * t)
        ..quadraticBezierTo(w * 0.5, h * (t + 0.035), w * 0.74, h * t);
      canvas.drawPath(ring, stroke);
    }

    // small side handle
    final handle = Path()
      ..moveTo(w * 0.78, h * 0.42)
      ..quadraticBezierTo(w * 0.94, h * 0.48, w * 0.88, h * 0.64)
      ..quadraticBezierTo(w * 0.84, h * 0.70, w * 0.76, h * 0.66);
    canvas.drawPath(handle, stroke);
  }

  @override
  bool shouldRepaint(covariant _CupPainter oldDelegate) => oldDelegate.color != color;
}
