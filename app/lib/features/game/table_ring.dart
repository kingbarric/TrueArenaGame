import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/neon_theme.dart';

/// Everyone around an oval table with something in the middle. Seats sit on
/// an ellipse squashed to fit the space, and shrink as the table fills, so a
/// full table of sixteen still shows every face without any overlapping.
class TableRing extends StatelessWidget {
  const TableRing({super.key, required this.players, required this.seat, required this.centre, this.tableTint});

  final List<String> players;

  /// One person's seat, drawn at the given avatar size.
  final Widget Function(String id, double avatarSize) seat;

  /// What sits in the middle of the table, given the room it has across.
  final Widget Function(double width) centre;

  /// Colours the table top — a reveal can darken or warm it.
  final Color? tableTint;


  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final n = context.neon;
        final space = box.biggest;
        final count = players.isEmpty ? 1 : players.length;
        final a0 = space.width / 2 - 34;
        final b0 = space.height / 2 - 40;
        final perimeter = math.pi * (3 * (a0 + b0) - math.sqrt(math.max(0, (3 * a0 + b0) * (a0 + 3 * b0))));
        final avatar = (perimeter / count - 22).clamp(28.0, 46.0);
        final seatW = avatar + 18;
        final seatH = avatar + 38;
        final a = math.max(40.0, space.width / 2 - seatW / 2 - 6);
        final b = math.max(40.0, space.height / 2 - seatH / 2 - 6);
        final centre = Offset(space.width / 2, space.height / 2);
        final tableA = math.max(56.0, a - seatW * 0.62);
        final tableB = math.max(44.0, b - seatH * 0.62);
        final top = tableTint ?? n.panel;
        return Stack(children: [
          Positioned(
            left: centre.dx - tableA,
            top: centre.dy - tableB,
            width: tableA * 2,
            height: tableB * 2,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              decoration: ShapeDecoration(
                shape: OvalBorder(side: BorderSide(color: n.gold.withValues(alpha: 0.45), width: 1.6)),
                gradient: RadialGradient(colors: [top.withValues(alpha: 0.85), n.plate.withValues(alpha: 0.55)]),
              ),
              child: Center(
                child: SizedBox(
                  // The largest box that fits inside the oval.
                  width: tableA * 2 * 0.72,
                  height: tableB * 2 * 0.74,
                  child: FittedBox(fit: BoxFit.scaleDown, child: this.centre(tableA * 2 * 0.72)),
                ),
              ),
            ),
          ),
          for (final (i, id) in players.indexed)
            Builder(builder: (context) {
              final angle = -math.pi / 2 + 2 * math.pi * i / count;
              final x = centre.dx + a * math.cos(angle);
              final y = centre.dy + b * math.sin(angle);
              return Positioned(
                key: ValueKey('table-seat-$id'),
                left: x - seatW / 2,
                top: y - seatH / 2,
                width: seatW,
                height: seatH,
                // A spotlit seat or a revealed role never spills out of its place.
                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topCenter, child: seat(id, avatar)),
              );
            }),
        ]);
      });
}

/// Discussion seats follow the outside edges, leaving the entire tabletop usable.
class DiscussionTable extends StatelessWidget {
  const DiscussionTable({super.key, required this.players, required this.seat,
    required this.child});
  final List<String> players;
  final Widget Function(String, double) seat;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    const seatW = 58.0;
    const seatH = 76.0;
    final w = box.maxWidth;
    final h = box.maxHeight;
    // Seats follow the perimeter so the corners also provide usable room.
    final rx = math.max(0.0, (w - seatW) / 2 - 2);
    final ry = math.max(0.0, (h - seatH) / 2 - 2);
    return Stack(children: [
      Positioned.fill(
        left: seatW + 2, right: seatW + 2,
        top: seatH + 2, bottom: seatH + 2,
        child: CustomPaint(
          key: const ValueKey('discussion-wooden-table'),
          painter: const _WoodTablePainter(),
          child: Padding(padding: const EdgeInsets.all(12), child: child),
        ),
      ),
      for (final (i, id) in players.indexed)
        Builder(builder: (context) {
          final horizontal = rx * 2;
          final vertical = ry * 2;
          final perimeter = 2 * (horizontal + vertical);
          var distance = (horizontal / 2 + perimeter * i / players.length) % perimeter;
          late final Offset position;
          if (distance <= horizontal) {
            position = Offset(seatW / 2 + 2 + distance, seatH / 2 + 2);
          } else if ((distance -= horizontal) <= vertical) {
            position = Offset(w - seatW / 2 - 2, seatH / 2 + 2 + distance);
          } else if ((distance -= vertical) <= horizontal) {
            position = Offset(w - seatW / 2 - 2 - distance, h - seatH / 2 - 2);
          } else {
            distance -= horizontal;
            position = Offset(seatW / 2 + 2, h - seatH / 2 - 2 - distance);
          }
          return Positioned(
            key: ValueKey('table-seat-$id'),
            left: position.dx - seatW / 2,
            top: position.dy - seatH / 2,
            width: seatW, height: seatH,
            child: FittedBox(fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter, child: seat(id, 40)),
          );
        }),
    ]);
  });
}

class _WoodTablePainter extends CustomPainter {
  const _WoodTablePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(26));
    canvas.drawShadow(Path()..addRRect(shape), Colors.black, 8, false);
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(
      colors: [Color(0xff59351f), Color(0xff885831), Color(0xff624027)],
      begin: Alignment.topLeft, end: Alignment.bottomRight,
    ).createShader(rect));
    // Solid timber planks and fine flowing grain, behind the controls.
    for (double y = 0; y < size.height; y += 42) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
        Paint()..color = const Color(0xff382315)..strokeWidth = 2);
      for (var j = 1; j <= 3; j++) {
        final path = Path()..moveTo(0, y + j * 9);
        path.cubicTo(size.width * .3, y + j * 9 - 5,
          size.width * .65, y + j * 9 + 6, size.width, y + j * 9);
        canvas.drawPath(path, Paint()..color = const Color(0xffb68350).withValues(alpha: .22)
          ..style = PaintingStyle.stroke..strokeWidth = .8);
      }
    }
    // A sealed clue envelope rests in the corner, clear of the controls.
    canvas.save();
    canvas.translate(20, 17);
    canvas.rotate(-.18);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-12, -7, 25, 17),
      const Radius.circular(2)), Paint()..color = const Color(0xffd9bb83));
    canvas.drawPath(Path()..moveTo(-12, -7)..lineTo(0, 3)..lineTo(13, -7),
      Paint()..color = const Color(0xff8a653e)..style = PaintingStyle.stroke..strokeWidth = 1);
    canvas.drawCircle(const Offset(0, 3), 3.5, Paint()..color = const Color(0xff8a2922));
    canvas.restore();
    // Etched compass / secret-society seal in the timber.
    final seal = Offset(size.width - 27, size.height - 27);
    final ink = Paint()..color = const Color(0xffe5bd79).withValues(alpha: .23)
      ..style = PaintingStyle.stroke..strokeWidth = 1.2;
    canvas.drawCircle(seal, 17, ink);
    canvas.drawCircle(seal, 13, ink);
    canvas.drawPath(Path()..moveTo(seal.dx, seal.dy - 12)
      ..lineTo(seal.dx + 10, seal.dy + 8)..lineTo(seal.dx - 10, seal.dy + 8)..close(), ink);
    canvas.restore();
    canvas.drawRRect(shape.deflate(2), Paint()..color = const Color(0xffb98951)
      ..style = PaintingStyle.stroke..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant _WoodTablePainter oldDelegate) => false;
}
