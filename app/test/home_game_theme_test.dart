import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/home/home_screen.dart';
import 'package:truearena/features/goosi/goosi_lobby_screen.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/neon.dart';

void main() {
  testWidgets('home artwork fills themed tiles with one-line game names',
      (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'tier': {
                  'tier': 'Rookie',
                  'lifetimeCoins': 0,
                  'nextTier': 'Rising Star',
                  'coinsToNextTier': 10,
                  'tierProgress': 0,
                }
              }),
              200,
              headers: {'content-type': 'application/json'},
            )));
    final state = AppState(api);

    Future<void> show(ThemeData theme) async {
      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(theme: theme, home: const HomeScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    }

    for (final theme in [NeonTheme.dark, NeonTheme.light]) {
      await show(theme);
      expect(find.byType(NeonCard), findsNothing);
      for (final entry in {
        'truearena': 'traitors.png',
        'bluff': 'word_bluff.png',
        'draughts': 'draft.png',
        'whot': 'whot.png',
        'ludo': 'ludo.png',
        'goosi': 'goosi.png',
      }.entries) {
        final tile = find.byKey(ValueKey('home-game-${entry.key}'));
        final imageFinder = find.descendant(
          of: tile,
          matching: find.byType(Image),
        );
        final image = tester.widget<Image>(imageFinder);
        expect((image.image as AssetImage).assetName,
            'assets/images/game_icons/${entry.value}');
        expect(tester.getSize(imageFinder).width,
            greaterThan(tester.getSize(tile).width * 0.85));
      }
      for (final name in [
        'Traitors',
        'Word Bluff',
        'Draft',
        'Whot',
        'Ludo',
        'Macala'
      ]) {
        expect(tester.widget<Text>(find.text(name)).maxLines, 1);
      }
      expect(tester.getBottomLeft(find.text('Join a huud')).dy,
          lessThan(tester.view.physicalSize.height - 96));
    }

    for (final theme in [NeonTheme.nebulaDark, NeonTheme.nebulaLight]) {
      await show(theme);
      expect(find.byType(NeonCard), findsNWidgets(6));
      final tile = tester.widget<AnimatedContainer>(find
          .descendant(
            of: find.byType(NeonCard).first,
            matching: find.byType(AnimatedContainer),
          )
          .first);
      expect((tile.decoration as BoxDecoration).borderRadius, isNotNull);
    }

    for (final theme in [NeonTheme.supercarDark, NeonTheme.supercarLight]) {
      await show(theme);
      expect(find.byType(NeonCard), findsNWidgets(6));
      final tile = tester.widget<AnimatedContainer>(find
          .descendant(
            of: find.byType(NeonCard).first,
            matching: find.byType(AnimatedContainer),
          )
          .first);
      expect((tile.decoration as ShapeDecoration).shape,
          isA<BeveledRectangleBorder>());
    }

    tester.view.physicalSize = const Size(375, 667);
    await show(NeonTheme.dark);
    expect(find.byKey(const ValueKey('home-game-whot')), findsOneWidget);
  });

  testWidgets('Macala home tile opens the Macala lobby', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'tier': {
                  'tier': 'Rookie',
                  'lifetimeCoins': 0,
                  'nextTier': 'Rising Star',
                  'coinsToNextTier': 10,
                  'tierProgress': 0,
                }
              }),
              200,
              headers: {'content-type': 'application/json'},
            )));

    await tester.pumpWidget(AppScope(
      state: AppState(api),
      child: MaterialApp(theme: NeonTheme.dark, home: const HomeScreen()),
    ));
    await tester.pump();
    final oware = find.byKey(const ValueKey('home-game-goosi'));
    await tester.ensureVisible(oware);
    await tester.tap(oware);
    // Not pumpAndSettle: GoosiLobbyScreen's WatchingEye keeps a pulsing
    // AnimationController running forever, which would hang pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(GoosiLobbyScreen), findsOneWidget);
    expect(find.text('Choose Macala mode'), findsOneWidget);
    expect(find.text('Relay Four'), findsOneWidget);
    expect(find.text('Oware Abapa'), findsOneWidget);
    await tester.tap(find.text('Relay Four'));
    await tester.pump();
    expect(find.text('Macala'), findsWidgets);
  });
}
