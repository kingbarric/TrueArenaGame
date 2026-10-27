import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/features/game/table_depth.dart';
import 'package:truearena/features/game/table_ring.dart';
import 'package:truearena/features/game/traitors_reveal.dart';
import 'package:truearena/theme/neon_theme.dart';

/// The 2.5D table: the wood in perspective, nearer seats bigger, the camera
/// moving only for the big moments — and never when motion is reduced.
void main() {
  Widget host(Widget child, {bool still = false, Size size = const Size(400, 560)}) => MaterialApp(
        theme: NeonTheme.dark,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: Scaffold(body: Center(child: SizedBox.fromSize(size: size, child: child))),
          ),
        ),
      );

  Matrix4 camera(WidgetTester tester) =>
      tester.widget<AnimatedContainer>(find.byKey(const ValueKey('table-camera'))).transform!;

  test('the flat tabletop lands exactly on its perspective outline', () {
    const flat = Size(300, 200);
    const quad = [Offset(20, 0), Offset(280, 0), Offset(300, 190), Offset(0, 190)];
    final m = perspectiveOnto(flat, quad);
    final corners = [Offset.zero, const Offset(300, 0), const Offset(300, 200), const Offset(0, 200)];
    for (final (i, corner) in corners.indexed) {
      final at = projectThrough(m, corner);
      expect(at.dx, moreOrLessEquals(quad[i].dx, epsilon: 1e-6));
      expect(at.dy, moreOrLessEquals(quad[i].dy, epsilon: 1e-6));
    }
    // Foreshortened: the middle of the flat top sits past the middle of the outline, toward the far edge.
    expect(projectThrough(m, const Offset(150, 100)).dy, lessThan(95));
  });

  test('the far row of seats is drawn in toward the middle', () {
    // Twelve round a 400×500 table: seat 11 is far-left, seat 7 near-left.
    final farLeft = DiscussionTable.seatCentre(11, 12, 400, 500);
    final nearLeft = DiscussionTable.seatCentre(7, 12, 400, 500);
    expect(farLeft.dy, lessThan(nearLeft.dy));
    expect(farLeft.dx, greaterThan(nearLeft.dx + 5));
  });

  testWidgets('nearer seats look bigger, and every seat stands on a shadow', (tester) async {
    final players = [for (var i = 0; i < 12; i++) 'p$i'];
    await tester.pumpWidget(host(DiscussionTable(
      players: players,
      seat: (id, size) => SizedBox(key: ValueKey('face-$id'), width: size, height: size),
      child: const Text('Round table'),
    )));
    await tester.pump(const Duration(milliseconds: 300));
    final far = tester.getRect(find.byKey(const ValueKey('face-p0')));
    final near = tester.getRect(find.byKey(const ValueKey('face-p6')));
    expect(far.top, lessThan(near.top));
    expect(near.width, greaterThan(far.width * 1.1));
    expect(find.byType(SeatShadows), findsOneWidget);
    expect(find.byKey(const ValueKey('candle-light')), findsOneWidget);
    expect(find.text('Round table'), findsOneWidget);
  });

  testWidgets('the camera pushes in through the drumroll, then leans toward whoever is leaving', (tester) async {
    await tester.pumpWidget(host(EliminationReveal(
      players: const ['a', 'b', 'c', 'd'],
      subjects: const [RevealSubject(id: 'c', name: 'Chidi', role: 'faithful')],
      nobody: false,
      heading: 'Who was taken in the night?',
      seat: (id, size, spotlight) => SizedBox(width: size, height: size),
      nameSeconds: 1,
      roleSeconds: 1,
      dawn: true,
    )));
    await tester.pump();
    expect(camera(tester).getMaxScaleOnAxis(), moreOrLessEquals(1.04));
    // The morning: the candles burn low until the news lands.
    expect(tester.widget<TableRing>(find.byType(TableRing)).dim, 0.55);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Chidi'), findsOneWidget);
    expect(camera(tester).getMaxScaleOnAxis(), moreOrLessEquals(1.08));
    final focus = tester.widget<AnimatedContainer>(find.byKey(const ValueKey('table-camera'))).transformAlignment;
    // Chidi sits at the bottom of a table of four: the camera leans down toward them.
    expect((focus as Alignment).y, greaterThan(0.3));
    expect(tester.widget<TableRing>(find.byType(TableRing)).dim, 0.15);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 20));
    // A Faithful lost: the light goes down with them.
    expect(tester.widget<TableRing>(find.byType(TableRing)).dim, 0.6);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('with motion reduced the camera never moves', (tester) async {
    await tester.pumpWidget(host(still: true, EliminationReveal(
      players: const ['a', 'b', 'c', 'd'],
      subjects: const [RevealSubject(id: 'c', name: 'Chidi', role: 'traitor')],
      nobody: false,
      heading: 'The table has spoken…',
      seat: (id, size, spotlight) => SizedBox(width: size, height: size),
      nameSeconds: 1,
      roleSeconds: 1,
    )));
    await tester.pump();
    expect(camera(tester).getMaxScaleOnAxis(), 1.0);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Chidi'), findsOneWidget);
    expect(camera(tester).getMaxScaleOnAxis(), 1.0);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the sealed letter slides up and settles, readable and upright', (tester) async {
    await tester.pumpWidget(host(const LetterArrival(child: Text('A letter for you'))));
    await tester.pump(const Duration(milliseconds: 60));
    final arriving = tester.getRect(find.text('A letter for you'));
    await tester.pump(const Duration(seconds: 1));
    final settled = tester.getRect(find.text('A letter for you'));
    expect(arriving.width, lessThan(settled.width));
    expect(arriving.center.dy, greaterThan(settled.center.dy));

    await tester.pumpWidget(host(still: true, const LetterArrival(key: ValueKey('again'), child: Text('Right away'))));
    await tester.pump();
    final opacity = tester.widget<Opacity>(find.ancestor(of: find.text('Right away'), matching: find.byType(Opacity)).first);
    expect(opacity.opacity, 1.0);
  });
}
