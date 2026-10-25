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
