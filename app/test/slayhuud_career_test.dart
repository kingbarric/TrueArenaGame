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
import 'package:truearena/features/slayhuud/slay_career_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  final catalog = Map<String, dynamic>.from(
      jsonDecode(File('assets/slay_renderer/catalog.json').readAsStringSync()));
  final content = Map<String, dynamic>.from(
      jsonDecode(File('assets/slay_renderer/career.json').readAsStringSync()));
  final now = DateTime.utc(2026, 10, 10);
  final look = <String, dynamic>{
    'body': 'male',
    'skinTone': '#623a27',
    'facePreset': 'classic',
    'pose': 'signature',
    'background': 'studio',
    'items': {'outfit': 'male-essential', 'shoes': 'shoe-0'}
  };
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  test('career content matches backend and has twenty distinct events', () {
    expect(
        content,
        jsonDecode(File('../backend/ta-api/src/main/resources/slay/career.json')
            .readAsStringSync()));
    expect((content['challenges'] as List).map((c) => c['id']).toSet(),
        hasLength(20));
  });
  test(
      'best score rewards improvements without farming, daily resets independently',
      () {
    final c = SlayPreviewCareer(content, catalog);
    final bare = {
      ...look,
      'items': {'outfit': 'male-essential'}
    };
    expect(c.score('hello-style', bare, now)['coinsEarned'], 125);
    expect(c.score('hello-style', bare, now)['coinsEarned'], 0);
    expect(c.score('hello-style', look, now)['coinsEarned'], 50);
    expect(c.home(now)['totalStars'], 5);
    expect(c.home(now)['xp'], 140);
    expect(() => c.score('rooftop-launch', look, now), throwsStateError);
    c.score('daily', look, now);
    expect(c.score('daily', look, now)['coinsEarned'], 0);
    expect(c.home(now.add(const Duration(days: 1)))['daily']['personalBest'],
        isNull);
    expect(c.home(now.add(const Duration(days: 1)))['streak'], 1);
  });
  test(
      'first chapter unlocks the next title and daily stars never inflate career stars',
      () {
    final c = SlayPreviewCareer(content, catalog);
    for (final id in [
      'hello-style',
      'coffee-date',
      'weekend-edit',
      'studio-finale'
    ]) c.score(id, look, now);
    expect(c.home(now)['rank']['name'], 'Rising Star');
    final stars = c.home(now)['totalStars'];
    c.score('daily', look, now);
    expect(c.home(now)['totalStars'], stars);
    expect(c.home(now)['events'][4]['unlocked'], true);
  });
  Future<void> launch(WidgetTester t, {double scale = 1}) async {
    t.view.physicalSize = const Size(360, 760);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = SlayPreviewCareer(content, catalog);
    final api = ApiClient(
        client: MockClient((r) async => http.Response(
            jsonEncode(
                r.url.path.endsWith('/career') ? c.home(now) : {'owned': []}),
            200,
            headers: {'content-type': 'application/json'})));
    await t.pumpWidget(AppScope(
        state: AppState(api),
        child: MaterialApp(
            theme: NeonTheme.dark,
            builder: (ctx, child) => MediaQuery(
                data: MediaQuery.of(ctx)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: SlayCareerScreen(catalog: catalog, owned: const {}))));
    await t.pumpAndSettle();
  }

  testWidgets('career tabs show the path, locked explanation and daily brief',
      (t) async {
    await launch(t);
    expect(find.text('Unknown'), findsOneWidget);
    await t.tap(find.text('Journey'));
    await t.pumpAndSettle();
    expect(find.text('Starter Studio'), findsOneWidget);
    await t.scrollUntilVisible(
        find.byKey(const ValueKey('brief-street-shot-career')), 250);
    await t.tap(find.byKey(const ValueKey('brief-street-shot-career')));
    await t.pumpAndSettle();
    expect(find.textContaining('is up ahead!'), findsOneWidget);
    await t.tap(find.text('Show my journey'));
    await t.pumpAndSettle();
    await t.tap(find.byType(NavigationDestination).at(2));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('View brief →'), 150);
    await t.pumpAndSettle();
    await t.tap(find.text('View brief →'));
    await t.pumpAndSettle();
    expect(find.text('Your checklist'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Let’s style!'), 100,
        scrollable: find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
    expect(find.text('Let’s style!').hitTestable(), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('career and briefs remain navigable at enlarged text', (t) async {
    await launch(t, scale: 1.5);
    await t.scrollUntilVisible(
        find.byKey(const ValueKey('brief-hello-style-career')), 180);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('brief-hello-style-career')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Let’s style!'), 120,
        scrollable: find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
    expect(find.text('Let’s style!').hitTestable(), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
