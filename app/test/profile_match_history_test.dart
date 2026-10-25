import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/profile/match_history_box.dart';
import 'package:truearena/theme/neon_theme.dart';

Map<String, dynamic> match(int i, [String opponent = 'Alex']) => {
      'matchId': '$i',
      'gameType': i.isEven ? 'chess' : 'whot',
      'outcome': 'won',
      'completedAt':
          DateTime.now().subtract(Duration(days: i)).toUtc().toIso8601String(),
      'opponents': [
        {
          'userId': 'opponent',
          'username': opponent.toLowerCase(),
          'displayName': opponent
        }
      ],
    };
http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Future<void> open(
    WidgetTester t, Future<http.Response> Function(http.Request) routes,
    {double scale = 1, double width = 390}) async {
  await t.binding.setSurfaceSize(Size(width, 1100));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final state =
      AppState(ApiClient(client: MockClient(routes))..bearer = 'history-test');
  await t.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(
          theme: NeonTheme.dark,
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: const Scaffold(
              body: SingleChildScrollView(child: MatchHistoryBox())))));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets(
      'history is boxed, bounded to ten games, with game icons on the right',
      (t) async {
    await open(t, (r) async {
      expect(r.url.queryParameters['limit'], '10');
      return json(List.generate(15, match));
    });
    expect(find.byKey(const ValueKey('profile-history-box')), findsOneWidget);
    final list = find.byKey(const ValueKey('profile-history-list'));
    expect(t.getSize(list).height, lessThanOrEqualTo(420));
    final icon = find.byKey(const ValueKey('match-game-0'));
    expect(t.getCenter(icon).dx,
        greaterThan(t.getCenter(find.text('vs alex').first).dx));
    await t.scrollUntilVisible(
        find.byKey(const ValueKey('profile-match-9')), 180,
        scrollable:
            find.descendant(of: list, matching: find.byType(Scrollable)));
    expect(find.byKey(const ValueKey('profile-match-9')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-match-10')), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'opponent, game and local-day filters are sent together and can be cleared',
      (t) async {
    final queries = <Map<String, String>>[];
    await open(t, (r) async {
      queries.add(r.url.queryParameters);
      return json([]);
    });
    await t.enterText(
        find.byKey(const ValueKey('history-opponent')), 'Alex & Jo');
    await t.pump(const Duration(milliseconds: 350));
    await t.pump();
    expect(queries.last['opponent'], 'Alex & Jo');
    await t.tap(find.byKey(const ValueKey('history-game-all')));
    await t.pumpAndSettle();
    await t.tap(find.text('Whot').last);
    await t.pumpAndSettle();
    expect(queries.last['gameType'], 'whot');
    await t.tap(find.byKey(const ValueKey('history-date')));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    final today = DateTime.now();
    expect(queries.last['from'],
        DateTime(today.year, today.month, today.day).toUtc().toIso8601String());
    expect(
        queries.last['until'],
        DateTime(today.year, today.month, today.day + 1)
            .toUtc()
            .toIso8601String());
    expect(queries.last['opponent'], 'Alex & Jo');
    await t.tap(find.byKey(const ValueKey('history-clear')));
    await t.pumpAndSettle();
    expect(queries.last, {'limit': '10'});
    expect(t.takeException(), isNull);
  });
  testWidgets('an older search cannot overwrite the latest result', (t) async {
    final old = Completer<http.Response>();
    await open(t, (r) async {
      if (r.url.queryParameters['opponent'] == 'old') return old.future;
      return json([match(1, r.url.queryParameters['opponent'] ?? 'Initial')]);
    });
    await t.enterText(find.byKey(const ValueKey('history-opponent')), 'old');
    await t.pump(const Duration(milliseconds: 350));
    await t.enterText(find.byKey(const ValueKey('history-opponent')), 'new');
    await t.pump(const Duration(milliseconds: 350));
    await t.pump();
    expect(find.text('vs new'), findsOneWidget);
    old.complete(json([match(2, 'Old')]));
    await t.pump();
    expect(find.text('vs old'), findsNothing);
    expect(find.text('vs new'), findsOneWidget);
  });
  testWidgets('failed history can retry and the controls fit enlarged text',
      (t) async {
    var calls = 0;
    await open(t, (r) async => ++calls == 1 ? json({}, 503) : json([match(1)]),
        width: 320, scale: 1.8);
    expect(find.text('Try again'), findsOneWidget);
    await t.ensureVisible(find.text('Try again'));
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('vs alex'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
