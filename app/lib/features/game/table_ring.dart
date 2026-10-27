import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/neon_theme.dart';
import 'table_depth.dart';

/// Everyone around an oval table with something in the middle. Seats sit on
/// an ellipse squashed to fit the space, and shrink as the table fills, so a
/// full table of sixteen still shows every face without any overlapping.
class TableRing extends StatelessWidget {
  const TableRing({super.key, required this.players, required this.seat, required this.centre, this.tableTint,
    this.dim = 0});

  final List<String> players;

  /// One person's seat, drawn at the given avatar size.
  final Widget Function(String id, double avatarSize) seat;

  /// What sits in the middle of the table, given the room it has across.
  final Widget Function(double width) centre;

  /// Colours the table top — a reveal can darken or warm it.
  final Color? tableTint;

  /// How low the candles burn: 0 bright, 1 nearly out.
  final double dim;

  /// Where seat [i] of [count] sits, as a fraction of the way across and down — for a camera to lean toward it.
  static Alignment seatAlignment(int i, int count) {
    final angle = -math.pi / 2 + 2 * math.pi * i / math.max(1, count);
    return Alignment(0.8 * math.cos(angle), 0.8 * math.sin(angle));
  }

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
        // The table is a slab: its edge shows below the top, and it throws a shadow.
        const thickness = 9.0;
        final tableRect = Rect.fromLTWH(centre.dx - tableA, centre.dy - tableB, tableA * 2, tableB * 2);
        final seats = [
          for (final (i, id) in players.indexed)
            (id, Offset(centre.dx + a * math.cos(-math.pi / 2 + 2 * math.pi * i / count),
                centre.dy + b * math.sin(-math.pi / 2 + 2 * math.pi * i / count))),
        ];
        double depth(Offset at) => seatDepth(at.dy - (centre.dy - b), 2 * b);
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fromRect(
            rect: tableRect.translate(0, thickness),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              decoration: ShapeDecoration(
                shape: const OvalBorder(),
                color: Color.lerp(top, Colors.black, 0.55),
                shadows: const [BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 10))],
              ),
            ),
          ),
          Positioned.fromRect(
            rect: tableRect,
            child: AnimatedContainer(
              key: const ValueKey('reveal-table-top'),
              duration: const Duration(milliseconds: 600),
              decoration: ShapeDecoration(
                shape: OvalBorder(side: BorderSide(color: n.gold.withValues(alpha: 0.45), width: 1.6)),
                gradient: RadialGradient(colors: [top.withValues(alpha: 0.85), n.plate.withValues(alpha: 0.55)]),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: tableRect,
            child: CandleLight(
              shape: (size) => Path()..addOval(Offset.zero & size),
              candles: const [Offset(0.09, 0.53), Offset(0.91, 0.53)],
              dim: dim,
              candleScale: 1.0,
            ),
          ),
          Positioned.fromRect(
            rect: tableRect,
            child: Center(
              child: SizedBox(
                // The largest box that fits inside the oval.
                width: tableA * 2 * 0.72,
                height: tableB * 2 * 0.74,
                child: FittedBox(fit: BoxFit.scaleDown, child: this.centre(tableA * 2 * 0.72)),
              ),
            ),
          ),
          Positioned.fill(
            child: SeatShadows(feet: [for (final (_, at) in seats) (at.translate(0, seatH / 2 - 6), depth(at))]),
          ),
          for (final (id, at) in seats)
            Positioned(
              key: ValueKey('table-seat-$id'),
              left: at.dx - seatW / 2,
              top: at.dy - seatH / 2,
              width: seatW,
              height: seatH,
              // Nearer seats a touch bigger; a spotlit seat or a revealed role never spills out of its place.
              child: Transform.scale(
                scale: depth(at),
                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topCenter, child: seat(id, avatar)),
              ),
            ),
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
/// The table is seen from a chair: its top tilts away in perspective, candles
/// light it, and the far seats sit a little closer together and a little
/// smaller than the near ones. What's on the table stays flat and readable.
class DiscussionTable extends StatelessWidget {
  const DiscussionTable({super.key, required this.players, required this.seat,
    required this.child, this.links = const [], this.dim = 0});
  final List<String> players;
  final Widget Function(String, double) seat;
  final Widget child;

  /// Lines between seats, drawn over the tabletop and under the faces.
  final List<TableLink> links;

  /// How low the candles burn: 0 bright, 1 nearly out.
  final double dim;

  static const _seatW = 58.0;
  static const _seatH = 76.0;

  /// How much narrower the far row of seats sits than the near one.
  static const _farRow = 0.92;

  /// Where seat [i] of [count] sits — the perimeter, so the corners are used
  /// too — drawn in a little toward the middle the farther away it is.
  static Offset seatCentre(int i, int count, double w, double h) {
    final flat = _flatSeat(i, count, w, h);
    final squeeze = _farRow + (1 - _farRow) * (h <= 0 ? 1 : (flat.dy / h).clamp(0.0, 1.0));
    return Offset(w / 2 + (flat.dx - w / 2) * squeeze, flat.dy);
  }

  static Offset _flatSeat(int i, int count, double w, double h) {
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
    double depth(Offset at) => seatDepth(at.dy, h);
    const top = EdgeInsets.fromLTRB(_seatW + 2, _seatH + 2, _seatW + 2, _seatH + 2);
    // The wood and its light, then the lines, then what's on the table, then
    // the faces — so a line never runs over the table's words.
    return Stack(children: [
      Positioned.fill(
        left: top.left, right: top.right, top: top.top, bottom: top.bottom,
        child: const CustomPaint(
          key: ValueKey('discussion-wooden-table'),
          painter: _WoodTablePainter(),
        ),
      ),
      Positioned.fill(
        left: top.left, right: top.right, top: top.top, bottom: top.bottom,
        child: CandleLight(
          shape: _WoodTablePainter.surface,
          candles: const [Offset(0.13, 0.16), Offset(0.87, 0.16)],
          dim: dim,
          candleScale: 1.15,
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
        child: SeatShadows(feet: [for (final at in centres.values) (at.translate(0, _seatH / 2 - 4), depth(at))]),
      ),
      Positioned.fill(
        left: top.left, right: top.right, top: top.top, bottom: top.bottom,
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
      for (final id in players)
        Positioned(
          key: ValueKey('table-seat-$id'),
          left: centres[id]!.dx - _seatW / 2,
          top: centres[id]!.dy - _seatH / 2,
          width: _seatW, height: _seatH,
          child: Transform.scale(
            scale: depth(centres[id]!),
            child: FittedBox(fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter, child: seat(id, 40)),
          ),
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

/// Solid timber seen from a chair: the top narrows toward the far edge, its
/// planks and grain foreshortening with it, and the near edge shows the
/// slab's thickness.
class _WoodTablePainter extends CustomPainter {
  const _WoodTablePainter();

  /// How thick the slab looks at the near edge.
  static const _thickness = 10.0;

  /// How wide the far edge is, against the near one.
  static const _far = 0.86;

  static List<Offset> _corners(Size size) {
    final inset = size.width * (1 - _far) / 2;
    final near = size.height - _thickness;
    return [Offset(inset, 0), Offset(size.width - inset, 0), Offset(size.width, near), Offset(0, near)];
  }

  /// The tabletop's outline — where the candlelight falls.
  static Path surface(Size size) => Path()..addPolygon(_corners(size), true);

  @override
  void paint(Canvas canvas, Size size) {
    final corners = _corners(size);
    final near = size.height - _thickness;
    final w = size.width;
    // The whole slab throws its shadow on the floor.
    final silhouette = Path()..addPolygon([corners[0], corners[1], Offset(w - 3, size.height), Offset(3, size.height)], true);
    canvas.drawShadow(silhouette, Colors.black, 10, false);
    // The near edge: the timber's thickness, darker as it turns away from the light.
    final edge = Rect.fromLTRB(0, near - 1, w, size.height);
    canvas.drawPath(
      Path()..addPolygon([Offset(0, near - 1), Offset(w, near - 1), Offset(w - 3, size.height), Offset(3, size.height)], true),
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xff6b4325), Color(0xff2e1a0d)]).createShader(edge));
    // The top, painted flat and laid into perspective.
    final flat = Size(w, near);
    canvas.save();
    canvas.transform(perspectiveOnto(flat, corners).storage);
    final rect = Offset.zero & flat;
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(22));
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(
      colors: [Color(0xff59351f), Color(0xff885831), Color(0xff624027)],
      begin: Alignment.topLeft, end: Alignment.bottomRight,
    ).createShader(rect));
    // Solid timber planks and fine flowing grain, behind the controls.
    for (double y = 0; y < flat.height; y += 42) {
      canvas.drawLine(Offset(0, y), Offset(flat.width, y),
        Paint()..color = const Color(0xff382315)..strokeWidth = 2);
      for (var j = 1; j <= 3; j++) {
        final path = Path()..moveTo(0, y + j * 9);
        path.cubicTo(flat.width * .3, y + j * 9 - 5,
          flat.width * .65, y + j * 9 + 6, flat.width, y + j * 9);
        canvas.drawPath(path, Paint()..color = const Color(0xffb68350).withValues(alpha: .22)
          ..style = PaintingStyle.stroke..strokeWidth = .8);
      }
    }
    // A sealed clue envelope lies on the near corner, clear of the candles.
    canvas.save();
    canvas.translate(24, flat.height - 22);
    canvas.rotate(-.18);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-12, -7, 25, 17),
      const Radius.circular(2)), Paint()..color = const Color(0xffd9bb83));
    canvas.drawPath(Path()..moveTo(-12, -7)..lineTo(0, 3)..lineTo(13, -7),
      Paint()..color = const Color(0xff8a653e)..style = PaintingStyle.stroke..strokeWidth = 1);
    canvas.drawCircle(const Offset(0, 3), 3.5, Paint()..color = const Color(0xff8a2922));
    canvas.restore();
    // Etched compass / secret-society seal in the timber.
    final seal = Offset(flat.width - 27, flat.height - 27);
    final ink = Paint()..color = const Color(0xffe5bd79).withValues(alpha: .23)
      ..style = PaintingStyle.stroke..strokeWidth = 1.2;
    canvas.drawCircle(seal, 17, ink);
    canvas.drawCircle(seal, 13, ink);
    canvas.drawPath(Path()..moveTo(seal.dx, seal.dy - 12)
      ..lineTo(seal.dx + 10, seal.dy + 8)..lineTo(seal.dx - 10, seal.dy + 8)..close(), ink);
    canvas.restore();
    canvas.drawRRect(shape.deflate(2), Paint()..color = const Color(0xffb98951)
      ..style = PaintingStyle.stroke..strokeWidth = 3);
    canvas.restore();
    // Light catches the near lip of the table.
    canvas.drawLine(Offset(4, near - 1), Offset(w - 4, near - 1),
      Paint()..color = const Color(0xffd9a868).withValues(alpha: .55)..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(covariant _WoodTablePainter oldDelegate) => false;
}
