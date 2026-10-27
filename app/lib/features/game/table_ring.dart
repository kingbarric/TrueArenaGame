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

/// A line drawn across the table between two seats — an alibi, the Black Spot's trail.
class TableLink {
  const TableLink(this.from, this.to, this.color, {this.dashed = false, this.width = 2});
  final String from, to;
  final Color color;
  final bool dashed;
  final double width;
}

/// Discussion seats follow the outside edges, leaving the entire tabletop usable.
class DiscussionTable extends StatelessWidget {
  const DiscussionTable({super.key, required this.players, required this.seat,
    required this.child, this.links = const []});
  final List<String> players;
  final Widget Function(String, double) seat;
  final Widget child;

  /// Lines between seats, drawn over the tabletop and under the faces.
  final List<TableLink> links;

  static const _seatW = 58.0;
  static const _seatH = 76.0;

  /// Where seat [i] of [count] sits — the perimeter, so the corners are used too.
  static Offset seatCentre(int i, int count, double w, double h) {
    final rx = math.max(0.0, (w - _seatW) / 2 - 2);
    final ry = math.max(0.0, (h - _seatH) / 2 - 2);
    final horizontal = rx * 2;
    final vertical = ry * 2;
    final perimeter = 2 * (horizontal + vertical);
    var distance = (horizontal / 2 + perimeter * i / count) % perimeter;
    if (distance <= horizontal) return Offset(_seatW / 2 + 2 + distance, _seatH / 2 + 2);
    if ((distance -= horizontal) <= vertical) return Offset(w - _seatW / 2 - 2, _seatH / 2 + 2 + distance);
    if ((distance -= vertical) <= horizontal) return Offset(w - _seatW / 2 - 2 - distance, h - _seatH / 2 - 2);
    distance -= horizontal;
    return Offset(_seatW / 2 + 2, h - _seatH / 2 - 2 - distance);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final w = box.maxWidth;
    final h = box.maxHeight;
    final centres = {
      for (final (i, id) in players.indexed) id: seatCentre(i, players.length, w, h),
    };
    // The wood, then the lines, then what's on the table, then the faces —
    // so a line never runs over the table's words.
    return Stack(children: [
      const Positioned.fill(
        left: _seatW + 2, right: _seatW + 2,
        top: _seatH + 2, bottom: _seatH + 2,
        child: CustomPaint(
          key: ValueKey('discussion-wooden-table'),
          painter: _WoodTablePainter(),
        ),
      ),
      if (links.isNotEmpty)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              key: const ValueKey('discussion-table-links'),
              painter: _LinkPainter(links, centres),
            ),
          ),
        ),
      Positioned.fill(
        left: _seatW + 2, right: _seatW + 2,
        top: _seatH + 2, bottom: _seatH + 2,
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
      for (final id in players)
        Positioned(
          key: ValueKey('table-seat-$id'),
          left: centres[id]!.dx - _seatW / 2,
          top: centres[id]!.dy - _seatH / 2,
          width: _seatW, height: _seatH,
          child: FittedBox(fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter, child: seat(id, 40)),
        ),
    ]);
  });
}

/// Seat-to-seat lines, aimed at the faces (a little above each seat's centre).
class _LinkPainter extends CustomPainter {
  const _LinkPainter(this.links, this.centres);
  final List<TableLink> links;
  final Map<String, Offset> centres;

  @override
  void paint(Canvas canvas, Size size) {
    for (final link in links) {
      final a = centres[link.from], b = centres[link.to];
      if (a == null || b == null) continue;
      final from = a.translate(0, -12), to = b.translate(0, -12);
      final paint = Paint()
        ..color = link.color
        ..strokeWidth = link.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      // A gentle bow toward the middle of the table, so crossing lines stay readable.
      final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
      final toCentre = Offset(size.width / 2, size.height / 2) - mid;
      final bend = mid + toCentre * 0.18;
      final path = Path()..moveTo(from.dx, from.dy)..quadraticBezierTo(bend.dx, bend.dy, to.dx, to.dy);
      if (!link.dashed) {
        canvas.drawPath(path, paint);
      } else {
        for (final metric in path.computeMetrics()) {
          for (double d = 0; d < metric.length; d += 10) {
            canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), paint);
          }
        }
      }
      canvas.drawCircle(to, link.width + 1.5, Paint()..color = link.color);
    }
  }

  @override
  bool shouldRepaint(covariant _LinkPainter old) => old.links != links || old.centres != centres;
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
