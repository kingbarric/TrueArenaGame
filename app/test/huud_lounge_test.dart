import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/features/huudspace/huud_lounge.dart';
import 'package:truearena/features/huudspace/huud_space_models.dart';

void main() {
  setUp(() => HuudLounge.debugScenePlaceholder = true);
  tearDown(() => HuudLounge.debugScenePlaceholder = false);
  final members = List.generate(
      16,
      (i) => HuudMember(
          userId: '$i',
          displayName: 'Person $i',
          username: 'person$i',
          here: true,
          host: i == 0));
  testWidgets(
      'people scrolling remains inside its panel, and only the actual speaker is marked',
      (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 320,
                    height: 400,
                    child: HuudLounge(
                        members: members.take(4).toList(),
                        speaking: const {'2'},
                        onPerson: (p) => tapped = p.userId))))));
    final panel = find.byKey(const ValueKey('huud-people-canvas'));
    final before = tester.getRect(panel);
    await tester.drag(find.byKey(const ValueKey('huud-lounge-scroll')),
        const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(tester.getRect(panel), before);
    expect(find.byKey(const ValueKey('huud-speaker-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-speaker-1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('huud-person-2')));
    expect(tapped, '2');
  });
  testWidgets(
      'every member remains accessible when there are more than twelve people',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 320,
                    height: 500,
                    child: HuudLounge(members: members, onPerson: (_) {}))))));
    expect(find.text('Room 1 of 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('huud-table-next')));
    await tester.pumpAndSettle();
    expect(find.text('Room 2 of 2'), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('huud-lounge-scroll')),
        const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('huud-person-15')), findsOneWidget);
  });
  testWidgets(
      'offline members stay out of room pages and can be opened from the away list',
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
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 320,
                height: 600,
                child: HuudLounge(
                    members: roster, onPerson: (p) => tapped = p.userId)))));
    expect(find.text('Room 1 of 2'), findsNothing);
    expect(find.text('12 here'), findsOneWidget);
    final footer = tester.getRect(find.byKey(const ValueKey('huud-away-members')));
    expect(find.text('Make yourself at home'), findsNothing);
    expect(find.text('Drag to look around · pinch to zoom · tap a name'), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('huud-lounge-scroll')),
        const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('huud-away-members')));
    await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('huud-away-away'))),
        alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('huud-away-away')));
    expect(tapped, 'away');
    expect(tester.getRect(find.byKey(const ValueKey('huud-away-members'))), footer);
    expect(find.text('Away from The Huud'), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-person-away')), findsNothing);
  });
}
