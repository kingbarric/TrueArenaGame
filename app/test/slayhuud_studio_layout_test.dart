import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/dev/slay_preview_career.dart';
import 'package:truearena/features/slayhuud/slay_stage.dart';
import 'package:truearena/features/slayhuud/slay_studio_screen.dart';
import 'package:truearena/features/slayhuud/slay_theme.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  final catalog = Map<String, dynamic>.from(
      jsonDecode(File('assets/slay_renderer/catalog.json').readAsStringSync()));
  final content = Map<String, dynamic>.from(
      jsonDecode(File('assets/slay_renderer/career.json').readAsStringSync()));
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SlayStage.debugPlaceholder = true;
  });
  tearDown(() => SlayStage.debugPlaceholder = false);

  for (final (body, size) in [
    ('female', const Size(393, 852)), // iPhone 17
    ('male', const Size(375, 667)), // small phone
  ]) {
    testWidgets(
        'career studio on a ${size.height.toInt()}pt phone keeps two wardrobe rows and never overflows ($body)',
        (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final career = SlayPreviewCareer(content, catalog)..start(body, null);
      final home = career.home(DateTime.utc(2026, 10, 10));
      final event = Map<String, dynamic>.from((home['events'] as List).first);
      await t.pumpWidget(AppScope(
          state: AppState(ApiClient(
              client: MockClient((_) async => http.Response('{}', 200,
                  headers: {'content-type': 'application/json'})))),
          child: MaterialApp(
              theme: NeonTheme.dark,
              home: SlayStudioScreen(
                  catalog: catalog,
                  theme: Map<String, dynamic>.from(event['theme']),
                  owned: const {},
                  careerEventId: event['id'],
                  careerCharacter: Map<String, dynamic>.from(home['character']),
                  initialBackground: 'studio'))));
      await t.pump(const Duration(seconds: 1));
      final tabRow = find.ancestor(
          of: find.byWidgetPredicate((w) => w is SlayTab && !w.pill).first,
          matching: find.byType(ListView));
      var visited = 0;
      for (final label in ['Looks', 'Dresses', 'Tops', 'Shirts', 'Trousers', 'Skirts',
          'Hair', 'Eyes', 'Shoes', 'Earrings', 'Bags', 'Lipstick', 'Watches', 'Details']) {
        final tab = find.descendant(
            of: tabRow,
            matching: find.byWidgetPredicate((w) => w is SlayTab && w.label.endsWith(' $label')));
        // Walk the tab row back to the start, then forward until the tab shows.
        await t.drag(tabRow, const Offset(2000, 0));
        await t.pump(const Duration(milliseconds: 200));
        for (int step = 0; step < 12 && tab.evaluate().isEmpty; step++) {
          await t.drag(tabRow, const Offset(-150, 0));
          await t.pump(const Duration(milliseconds: 200));
        }
        if (tab.evaluate().isEmpty) continue; // not offered to this body
        await t.tap(tab);
        await t.pump(const Duration(milliseconds: 400));
        visited++;
        expect(t.takeException(), isNull, reason: label);
        expect(t.getRect(find.byType(GridView)).height, greaterThanOrEqualTo(190),
            reason: '$label wardrobe height');
      }
      expect(visited, greaterThan(5));
    });
  }
}
