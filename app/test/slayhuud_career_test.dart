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
import 'package:truearena/features/slayhuud/slay_stage.dart';
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
  test(
      'the career keeps one character, unlocks stage pieces and explains locks',
      () {
    final c = SlayPreviewCareer(content, catalog);
    expect(c.home(now)['character'], isNull);
    final home = c.start('female', 'girl02');
    expect(home['character']['avatarId'], 'girl02');
    expect(() => c.start('male', null), throwsStateError);
    final items = Set<String>.from(home['character']['items']);
    expect(items, containsAll(['female-essential', 'shoe-1']));
    expect(items, isNot(contains('female-night')));
    expect(home['character']['locks']['female-night'], 'Opens at Nightlife');
    expect(home['character']['locks']['female-skirts-collection-6'],
        'Earn 4★ in Starter Studio');
    final first = c.score(
        'hello-style',
        {
          ...look,
          'body': 'female',
          'items': {'outfit': 'female-essential', 'shoes': 'shoe-1'}
        },
        now);
    expect((first['unlocked'] as List).map((u) => u['id']),
        ['female-skirts-collection-6', 'female-shoe-slippers']);
    expect(first['ranking']['friendsRank'], isNotNull);
  });

  Future<SlayPreviewCareer> launch(WidgetTester t,
      {double scale = 1, bool started = true}) async {
    t.view.physicalSize = const Size(360, 760);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    SlayStage.debugPlaceholder = true;
    addTearDown(() => SlayStage.debugPlaceholder = false);
    final c = SlayPreviewCareer(content, catalog);
    if (started) c.start('male', null);
    final api = ApiClient(client: MockClient((r) async {
      final path = r.url.path;
      final body = r.body.isEmpty ? const {} : jsonDecode(r.body);
      final result = path.endsWith('/career')
          ? c.home(now)
          : path.endsWith('/career/start')
              ? c.start(body['body'], body['avatarId'])
              : path.endsWith('/leaderboard')
                  ? c.leaderboard('daily', now)
                  : {'owned': []};
      return http.Response(jsonEncode(result), 200,
          headers: {'content-type': 'application/json'});
    }));
    await t.pumpWidget(AppScope(
        state: AppState(api),
        child: MaterialApp(
            theme: NeonTheme.dark,
            builder: (ctx, child) => MediaQuery(
                data: MediaQuery.of(ctx)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: SlayCareerScreen(catalog: catalog, owned: const {}))));
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    return c;
  }

  testWidgets('a new career starts by choosing a star, once', (t) async {
    final c = await launch(t, started: false);
    expect(find.text('Who’s your star?'), findsOneWidget);
    expect(find.byKey(const ValueKey('slay-stage-female')), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Next star'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('slay-stage-male')), findsOneWidget);
    await t.tap(find.text('This is my star'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.text('That’s my star!'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(c.character, {'body': 'male', 'avatarId': 'male'});
    expect(find.text('My Career'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'home shows next event, daily slay and the stage road; invites never ask her or him',
      (t) async {
    await launch(t);
    expect(find.text('NEXT UP'), findsOneWidget);
    expect(find.text('☀️ DAILY SLAY'), findsOneWidget);
    await t.scrollUntilVisible(find.text('City Style'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Become Rising Star'), findsOneWidget);
    await t.scrollUntilVisible(find.text('NEXT UP'), -300,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('NEXT UP'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.text('💌 YOU’RE INVITED'), findsOneWidget);
    expect(find.text('Her'), findsNothing);
    expect(find.text('Him'), findsNothing);
    expect(find.textContaining('Shoes'), findsWidgets);
    await t.scrollUntilVisible(find.text('Let’s slay!'), 120,
        scrollable: find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
    expect(find.text('Let’s slay!').hitTestable(), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('career and invites remain navigable at enlarged text',
      (t) async {
    await launch(t, scale: 1.5);
    await t.tap(find.text('NEXT UP'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.scrollUntilVisible(find.text('Let’s slay!'), 120,
        scrollable: find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable)));
    expect(find.text('Let’s slay!').hitTestable(), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
