import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/huudspace/traitors_mode_sheet.dart';
import 'package:truearena/features/modes/mode_select_screen.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/mode_art.dart';

/// A stub /config/presets response with two builtin modes.
final _presets = [
  {
    'id': '1',
    'scope': 'builtin',
    'slug': 'classic_conspiracy',
    'name': 'Classic Conspiracy',
    'tag': 'Default',
    'description': 'Pure deduction.',
    'config': {
      'endgameVeil': 'final_4',
      'table': {'minPlayers': 6, 'maxPlayers': 10, 'traitorCurve': [
        [6, 2]
      ]},
      'twists': <String, dynamic>{},
    },
  },
  {
    'id': '2',
    'scope': 'builtin',
    'slug': 'blood_moon',
    'name': 'Blood Moon',
    'tag': null,
    'description': 'Double murder after round 2.',
    'config': {
      'endgameVeil': 'final_5',
      'table': {'minPlayers': 8, 'maxPlayers': 14, 'traitorCurve': [
        [8, 3]
      ]},
      'twists': <String, dynamic>{},
    },
  },
];

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders the preset cards from GET /config/presets', (tester) async {
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('/api/v1/config/presets')) {
        return http.Response(jsonEncode(_presets), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('[]', 200);
    });
    final state = AppState(ApiClient(client: mock));

    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(
        theme: NeonTheme.light,
        home: const ModeSelectScreen(),
      ),
    ));
    await tester.pump(); // kick the post-frame load
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Classic Conspiracy'), findsOneWidget);
    expect(find.text('Blood Moon'), findsOneWidget);
    expect(find.text('DEFAULT'), findsOneWidget); // the tag pill
    expect(find.text('Custom Game'), findsOneWidget);
    expect(find.text('Open the huud'), findsOneWidget); // launch bar for the selected preset
    // Each mode's own picture fills its card; Custom Game has none.
    expect(find.byKey(const ValueKey('mode-art-assets/images/traitors_modes/classic_conspiracy.jpg')), findsOneWidget);
    expect(find.byKey(const ValueKey('mode-art-assets/images/traitors_modes/blood_moon.jpg')), findsOneWidget);
    expect(find.byType(ModeArtBackdrop), findsNWidgets(2));
  });

  testWidgets("a Huud's Which Traitors? cards each carry their mode's picture", (tester) async {
    final mock = MockClient((req) async => http.Response(jsonEncode(_presets), 200,
        headers: {'content-type': 'application/json'}));
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient(client: mock)),
      child: MaterialApp(
        theme: NeonTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(onPressed: () => askTraitorsMode(context), child: const Text('Traitors')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Traitors'));
    await tester.pumpAndSettle();
    expect(find.text('Which Traitors?'), findsOneWidget);
    expect(find.byKey(const ValueKey('mode-art-assets/images/traitors_modes/classic_conspiracy.jpg')), findsOneWidget);
    expect(find.byKey(const ValueKey('mode-art-assets/images/traitors_modes/blood_moon.jpg')), findsOneWidget);
    // Still picks the mode as before.
    await tester.tap(find.byKey(const ValueKey('traitors-mode-blood_moon')));
    await tester.pumpAndSettle();
    expect(find.text('Which Traitors?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('every built-in Traitors mode has its picture in the app', () {
    for (final slug in ['blood_moon', 'midnight_heist', 'final_gambit', 'classic_conspiracy', 'the_last_alibi']) {
      final asset = traitorsModeArt[slug];
      expect(asset, isNotNull, reason: slug);
      expect(File(asset!).existsSync(), isTrue, reason: asset);
    }
  });
}
