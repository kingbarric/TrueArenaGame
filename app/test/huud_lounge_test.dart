import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/features/huudspace/huud_lounge.dart';
import 'package:truearena/features/huudspace/huud_space_models.dart';

void main() {
  setUp(() {
    HuudLounge.debugScenePlaceholder = true;
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  tearDown(() => HuudLounge.debugScenePlaceholder = false);
  final members = List.generate(
      16,
      (i) => HuudMember(
          userId: '$i',
          displayName: 'Person $i',
          username: 'person$i',
          here: true,
          host: i == 0));

  Future<void> pumpRoom(WidgetTester tester, List<HuudMember> roster,
          {ValueChanged<HuudMember>? onPerson,
          Set<String> speaking = const {}}) =>
      tester.pumpWidget(MaterialApp(
          theme: NeonTheme.light,
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: 320,
                      height: 500,
                      child: HuudLounge(
                          members: roster,
                          speaking: speaking,
                          onPerson: onPerson ?? (_) {}))))));

  testWidgets('the scene fits its panel without a scrolling online roster',
      (tester) async {
    await pumpRoom(tester, members.take(4).toList(), speaking: {'2'});
    final panel =
        tester.getRect(find.byKey(const ValueKey('huud-people-canvas')));
    final scene =
        tester.getRect(find.byKey(const ValueKey('huud-scene-viewport')));
    final footer =
        tester.getRect(find.byKey(const ValueKey('huud-away-members')));
    expect(panel.contains(scene.topLeft), isTrue);
    expect(scene.bottom, lessThanOrEqualTo(footer.top));
    expect(footer.bottom, lessThanOrEqualTo(panel.bottom));
    expect(find.byType(Scrollable), findsNothing);
    expect(
        find.bySemanticsLabel(
            RegExp('person0, Host; person1; person2, Talking now; person3')),
        findsOneWidget);
    expect(find.text('Make yourself at home'), findsNothing);
    expect(find.text('Drag to look around · pinch to zoom · tap a name'),
        findsOneWidget);
  });

  testWidgets('more than twelve present members can be reached by room paging',
      (tester) async {
    await pumpRoom(tester, members);
    expect(find.text('Room 1 of 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('huud-table-next')));
    await tester.pumpAndSettle();
    expect(find.text('Room 2 of 2'), findsOneWidget);
    expect(
        find.bySemanticsLabel(RegExp('person12; person13; person14; person15')),
        findsOneWidget);
  });

  testWidgets('away members open in a dropdown without changing the room size',
      (tester) async {
    String? tapped;
    final roster = [
      ...members.take(12),
      const HuudMember(
          userId: 'away',
          displayName: 'Away Person',
          username: 'away_person',
          here: false)
    ];
    await pumpRoom(tester, roster, onPerson: (p) => tapped = p.userId);
    expect(find.text('Room 1 of 2'), findsNothing);
    expect(find.text('12 here'), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-away-away')), findsNothing);
    final scene =
        tester.getRect(find.byKey(const ValueKey('huud-scene-viewport')));
    await tester.tap(find.byKey(const ValueKey('huud-away-toggle')));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('huud-scene-viewport'))),
        scene);
    await tester.tap(find.byKey(const ValueKey('huud-away-away')));
    await tester.pumpAndSettle();
    expect(tapped, 'away');
    expect(find.byKey(const ValueKey('huud-away-scroll')), findsNothing);
  });

  testWidgets(
      'away dropdown shows at most five rows and scrolls a large roster',
      (tester) async {
    String? tapped;
    final away = List.generate(
        100,
        (i) => HuudMember(
            userId: 'away-$i',
            displayName: 'Away $i',
            username: 'away_$i',
            here: false));
    await pumpRoom(tester, [...members.take(2), ...away],
        onPerson: (p) => tapped = p.userId);
    final toggle = find.byKey(const ValueKey('huud-away-toggle'));
    expect(find.text('100'), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-away-scroll')), findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('huud-away-scroll'));
    expect(tester.getSize(list).height, 240);
    expect(find.byKey(const ValueKey('huud-away-away-4')).hitTestable(),
        findsOneWidget);
    expect(find.byKey(const ValueKey('huud-away-away-5')).hitTestable(),
        findsNothing);
    final panel =
        tester.getRect(find.byKey(const ValueKey('huud-people-canvas')));
    final scene =
        tester.getRect(find.byKey(const ValueKey('huud-scene-viewport')));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('huud-away-away-99')), 220,
        scrollable:
            find.descendant(of: list, matching: find.byType(Scrollable)));
    await tester.tap(find.byKey(const ValueKey('huud-away-away-99')));
    await tester.pumpAndSettle();
    expect(tapped, 'away-99');
    expect(tester.getRect(find.byKey(const ValueKey('huud-people-canvas'))),
        panel);
    expect(tester.getRect(find.byKey(const ValueKey('huud-scene-viewport'))),
        scene);
    expect(list, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grid reaches everyone and switches back to the same 3D room',
      (tester) async {
    String? tapped;
    await pumpRoom(tester, members,
        onPerson: (p) => tapped = p.userId, speaking: {'1'});
    await tester.tap(find.byKey(const ValueKey('huud-table-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grid'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('huud-scene-viewport')), findsNothing);
    expect(find.text('Talking now'), findsOneWidget);
    final grid = find.byKey(const ValueKey('huud-people-grid'));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('huud-grid-15')), 200,
        scrollable:
            find.descendant(of: grid, matching: find.byType(Scrollable)));
    await tester.ensureVisible(find.byKey(const ValueKey('huud-grid-15')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('huud-grid-15')));
    await tester.pumpAndSettle();
    expect(tapped, '15');
    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    expect(find.text('Room 2 of 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-scene-viewport')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty away dropdown explains that everyone is here',
      (tester) async {
    await pumpRoom(tester, members);
    await tester.tap(find.byKey(const ValueKey('huud-away-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Everyone is here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
