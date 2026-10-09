import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:truearena/features/slayhuud/slay_theme.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget game(Widget child, {double textScale = 1}) => MaterialApp(
      theme: NeonTheme.dark,
      home: Builder(
          builder: (context) => Theme(
              data: slayTheme(context),
              child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: Scaffold(body: child)))));

  testWidgets('coin unlock asks Yes or No and prevents unaffordable purchases',
      (tester) async {
    bool? choice;
    await tester.pumpWidget(game(Builder(
        builder: (c) => SlayButton(
            onPressed: () async {
              choice = await showSlayUnlock(c, 'Lace Skirt', 40, 100);
            },
            child: const Text('Locked skirt')))));
    await tester.tap(find.text('Locked skirt'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock Lace Skirt?'), findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(choice, isFalse);
    await tester.tap(find.text('Locked skirt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes · 40 coins'));
    await tester.pumpAndSettle();
    expect(choice, isTrue);
    await tester.pumpWidget(game(Builder(
        builder: (c) => SlayButton(
            onPressed: () => showSlayUnlock(c, 'Lace Skirt', 40, 10),
            child: const Text('Try')))));
    await tester.tap(find.text('Try'));
    await tester.pumpAndSettle();
    final yes = find.ancestor(
        of: find.text('Yes · 40 coins'), matching: find.byType(FilledButton));
    expect(tester.widget<FilledButton>(yes).onPressed, isNull);
    expect(find.textContaining('Earn more coins'), findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
  });

  testWidgets('raised submit button stays disabled until ready',
      (tester) async {
    var submitted = 0;
    await tester.pumpWidget(game(const SlayButton.icon(
        onPressed: null,
        icon: Icon(Icons.auto_awesome),
        label: Text('Submit'))));
    await tester.tap(find.text('Submit'));
    expect(submitted, 0);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.pumpWidget(game(SlayButton.icon(
        onPressed: () => submitted++,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Submit'))));
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(submitted, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'compact wardrobe keeps keyboard activation and selected semantics',
      (tester) async {
    var selected = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(game(Center(
        child: SizedBox(
            width: 90,
            height: 112,
            child: SlayWardrobeTile(
                name: 'Premiere Night',
                selected: true,
                owned: true,
                onTap: () => selected++)))));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.bySemanticsLabel('Premiere Night, wearing'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('small wardrobe supports large text in ${brightness.name}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme =
          brightness == Brightness.dark ? NeonTheme.dark : NeonTheme.light;
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Builder(
              builder: (context) => Theme(
                  data: slayTheme(context),
                  child: MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: const TextScaler.linear(2)),
                      child: Scaffold(
                          body: GridView.count(
                              crossAxisCount: 3,
                              childAspectRatio: 90 / 142,
                              padding: const EdgeInsets.all(16),
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              children: [
                            for (var i = 0; i < 6; i++)
                              SlayWardrobeTile(
                                  name: 'Green Flapper Dress',
                                  selected: i == 0,
                                  owned: i < 3,
                                  coins: 144,
                                  onTap: () {})
                          ])))))));
      expect(tester.takeException(), isNull);
    });
  }
}
