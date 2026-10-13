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
import 'package:truearena/features/slayhuud/slay_stage.dart';
import 'package:truearena/features/slayhuud/slay_models.dart';
import 'package:truearena/features/slayhuud/slay_studio_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  final catalog = Map<String, dynamic>.from(
      jsonDecode(File('assets/slay_renderer/catalog.json').readAsStringSync()));
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SlayStage.debugPlaceholder = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => SlayStage.debugPlaceholder = false);
  Future<void> open(WidgetTester t,
      {String? competition,
      String body = 'female',
      Set<String> owned = const {}}) async {
    final api = ApiClient(
        client: MockClient((_) async =>
            http.Response(jsonEncode({'balance': 600, 'recent': []}), 200)));
    await t.pumpWidget(AppScope(
        state: AppState(api),
        child: MaterialApp(
            theme: NeonTheme.dark,
            home: SlayStudioScreen(
                catalog: catalog,
                theme: Map<String, dynamic>.from((catalog['themes'] as List)
                    .firstWhere((t) => t['id'] == 'first-date')),
                owned: owned,
                competitionId: competition,
                initialBody: body))));
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets(
      'freestyle requires a character choice and enters the studio with the selected avatar',
      (t) async {
    await open(t);
    expect(find.text('Who’s your star?'), findsOneWidget);
    expect(find.text('Your studio'), findsNothing);
    for (int i = 0; i < 4; i++) {
      await t.tap(find.bySemanticsLabel('Next star'));
      await t.pump();
    }
    expect(find.text('Ella'), findsOneWidget);
    await t.tap(find.text('This is my star'));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Who’s your star?'), findsNothing);
    expect(find.text('Your studio'), findsOneWidget);
    expect(find.byKey(const ValueKey('slay-stage-ella')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('restoring a saved outfit retains the newly selected character',
      (t) async {
    const items = {
      'tops': 'female-top-tee',
      'trousers': 'female-s0-ribbon-shorts'
    };
    SharedPreferences.setMockInitialValues({
      'slay-draft-null-female': jsonEncode(SlayLook.initial('female')
          .copy(avatarId: 'female', items: items)
          .toJson())
    });
    await open(t, owned: items.values.toSet());
    for (int i = 0; i < 4; i++) {
      await t.tap(find.bySemanticsLabel('Next star'));
      await t.pump();
    }
    await t.tap(find.text('This is my star'));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.text('My last look'));
    await t.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('slay-stage-ella')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('competition character picker respects the joined body',
      (t) async {
    await open(t, competition: 'match', body: 'male');
    expect(find.text('Alexander'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Next star'));
    await t.pump();
    expect(find.text('Ethan'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Next star'));
    await t.pump();
    expect(find.text('Alexander'), findsOneWidget);
  });
}
