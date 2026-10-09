import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/home/home_screen.dart';
import 'package:truearena/features/games/game_select_screen.dart';
import 'package:truearena/features/slayhuud/slay_hub_screen.dart';
import 'package:truearena/features/slayhuud/slay_game_menu.dart';
import 'package:truearena/features/modes/mode_select_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> transition(WidgetTester tester) async {
    // Home keeps a marquee animating under the pushed route, so wait for
    // this transition rather than requiring every app animation to stop.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  Future<void> launch(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
        client: MockClient((_) async => http.Response(
            '{"message":"Offline for this navigation test"}', 503,
            headers: {'content-type': 'application/json'})));
    await tester.pumpWidget(AppScope(
        state: AppState(api),
        child: MaterialApp(theme: NeonTheme.dark, home: home)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  for (final screen in [const HomeScreen(), const GameSelectScreen()]) {
    testWidgets(
        '${screen.runtimeType} opens SlayHuud instead of Traitors and can exit',
        (tester) async {
      await launch(tester, screen);
      await tester.ensureVisible(find.text('SlayHuud'));
      await tester.tap(find.text('SlayHuud'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SlayHubScreen), findsOneWidget);
      expect(find.byType(ModeSelectScreen), findsNothing);
      await tester.tap(find.byTooltip('Game settings'));
      await transition(tester);
      expect(find.text('How to play'), findsOneWidget);
      await tester.tap(find.text('Leave SlayHuud'));
      await transition(tester);
      expect(find.byType(SlayHubScreen), findsNothing);
      expect(find.byType(screen.runtimeType), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('gear menu opens readable rules and closes the sheet',
      (tester) async {
    await launch(tester,
        Scaffold(appBar: AppBar(actions: [SlayGameMenu(onExit: () {})])));
    await tester.tap(find.byTooltip('Game settings'));
    await transition(tester);
    await tester.tap(find.text('How to play'));
    await transition(tester);
    expect(find.text('How to play SlayHuud'), findsOneWidget);
    await tester.ensureVisible(find.text('Got it'));
    await tester.tap(find.text('Got it'));
    await transition(tester);
    expect(find.text('How to play SlayHuud'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('wardrobe credits are bundled and accessible from the gear menu',
      (tester) async {
    await launch(tester,
        Scaffold(appBar: AppBar(actions: [SlayGameMenu(onExit: () {})])));
    await tester.tap(find.byTooltip('Game settings'));
    await transition(tester);
    await tester.tap(find.text('Wardrobe credits'));
    await transition(tester);
    await tester.pumpAndSettle();
    expect(find.text('The artists behind your wardrobe'), findsOneWidget);
    expect(
        find.byWidgetPredicate((w) =>
            w is SelectableText &&
            w.data!.contains('punkduck') &&
            w.data!.contains('Elvaerwyn') &&
            w.data!.contains('CC BY 4.0')),
        findsOneWidget);
    await tester.tap(find.text('Done'));
    await transition(tester);
    expect(find.text('The artists behind your wardrobe'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
