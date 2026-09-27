import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/compact_list_row.dart';
import 'package:truearena/widgets/neon.dart';
import 'package:truearena/widgets/playground_nav_pill.dart';

void main() {
  testWidgets('themes change card, button, list, and navigation shapes',
      (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    Future<void> show(ThemeData theme) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(children: [
            const NeonCard(child: Text('Card')),
            NeonButton('Play', onPressed: () {}),
            const CompactListRow(title: Text('List item')),
            PlaygroundNavPill(
              activeIndex: 0,
              items: [PlaygroundNavItem(
                icon: Icons.sports_esports_rounded,
                onTap: () {},
              )],
            ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Decoration cardDecoration() =>
        (tester.widget<AnimatedContainer>(find.descendant(
          of: find.byType(NeonCard),
          matching: find.byType(AnimatedContainer),
        ).first)).decoration!;
    Decoration listDecoration() =>
        (tester.widget<Container>(find.descendant(
          of: find.byType(CompactListRow),
          matching: find.byType(Container),
        ).first)).decoration!;

    await show(NeonTheme.dark);
    expect(cardDecoration(), isA<BoxDecoration>());
    expect(listDecoration(), isA<BoxDecoration>());

    await show(NeonTheme.nebulaDark);
    final nebulaCard = cardDecoration() as BoxDecoration;
    expect(nebulaCard.borderRadius, BorderRadius.circular(24));
    expect(nebulaCard.boxShadow, isNotEmpty);
    expect(listDecoration(), isA<BoxDecoration>());

    await show(NeonTheme.supercarDark);
    expect((cardDecoration() as ShapeDecoration).shape,
        isA<BeveledRectangleBorder>());
    expect((listDecoration() as ShapeDecoration).shape,
        isA<BeveledRectangleBorder>());
    final button = tester.widget<AnimatedContainer>(find.descendant(
      of: find.byType(NeonButton),
      matching: find.byType(AnimatedContainer),
    ).first);
    expect((button.decoration as ShapeDecoration).shape,
        isA<BeveledRectangleBorder>());
    final nav = tester.widget<Container>(find.descendant(
      of: find.byType(PlaygroundNavPill),
      matching: find.byType(Container),
    ).first);
    expect((nav.decoration as ShapeDecoration).shape,
        isA<BeveledRectangleBorder>());
  });
}
