import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/huud/huud_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> liveRoom(int i) => {
      'id': 'live-$i',
      'name': 'The Sunday Club $i',
      'privacy': 'public',
      'memberCount': 4,
      'host': {
        'userId': 'host-$i',
        'displayName': 'Beverly',
        'username': 'beverly',
        'host': true
      },
      'members': [
        for (var j = 0; j < 4; j++)
          {
            'userId': 'person-$j',
            'displayName': 'Person $j',
            'username': 'person$j',
            'here': true
          }
      ],
      'youAreIn': false,
      'gameType': i.isEven ? 'whot' : null,
      'gameStatus': i.isEven ? 'playing' : null,
      'background': i % 3 == 0 ? 'disco' : 'blank',
      'gamesPlayed': i,
      'moments': [
        {
          'kind': 'play',
          'who': {'userId': 'person-0', 'displayName': 'Person 0', 'username': 'person0'},
          'text': 'called General Market. Everyone picks one'
        },
        // Uneven cards: every other Huud has more going on.
        if (i.isEven)
          {
            'kind': 'joined',
            'who': {'userId': 'person-1', 'displayName': 'Person 1', 'username': 'person1'},
            'text': 'joined',
            'at': DateTime.now().toUtc().toIso8601String()
          },
      ],
    };

Future<void> open(
    WidgetTester t, Future<http.Response> Function(http.Request) routes,
    {bool live = true,
    Size size = const Size(390, 844),
    double scale = 1,
    ThemeData? theme}) async {
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  final api = ApiClient(client: MockClient(routes))..bearer = 'layout-test';
  final state = AppState(api)
    ..user = const UserView(id: 'me', displayName: 'Riley', isGuest: false)
    ..identity = Identity.account;
  await t.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(
          theme: theme ?? NeonTheme.dark,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 59, bottom: 34),
                  textScaler: TextScaler.linear(scale)),
              child: child!),
          home: HuudScreen(startOnLiveNow: live))));
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets(
      'live Huuds sit two to a row as uneven cards, the first row above the shell menu',
      (t) async {
    await open(
        t,
        (r) async => r.url.path.endsWith('/huud-spaces/live')
            ? json(List.generate(8, liveRoom))
            : json([]));
    final first = find.byKey(const ValueKey('live-huud-live-0'));
    final second = find.byKey(const ValueKey('live-huud-live-1'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    // Side by side, and not the same height.
    expect(t.getRect(second).left, greaterThan(t.getRect(first).right));
    expect(t.getRect(second).top, t.getRect(first).top);
    expect(t.getRect(first).height, isNot(t.getRect(second).height));
    for (final card in [first, second]) {
      expect(t.getRect(card).width, greaterThan(150));
      expect(t.getRect(card).bottom, lessThanOrEqualTo(844 - 34 - 130));
      // The card is the button.
      expect(card.hitTestable(), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('live-enter-live-0')), findsNothing);
    expect(
        find.textContaining('person0 called General Market',
            findRichText: true),
        findsWidgets);
    final people = find.byKey(const ValueKey('live-members-live-0'));
    expect(
        find.descendant(of: people, matching: find.text('+1')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'live cards go one to a row and scroll at enlarged text, in both themes',
      (t) async {
    for (final theme in [NeonTheme.dark, NeonTheme.light]) {
      await open(
          t,
          (r) async => r.url.path.endsWith('/huud-spaces/live')
              ? json(List.generate(8, liveRoom))
              : json([]),
          size: const Size(320, 740),
          scale: 1.8,
          theme: theme);
      expect(t.takeException(), isNull);
      final first = find.byKey(const ValueKey('live-huud-live-0'));
      final second = find.byKey(const ValueKey('live-huud-live-1'));
      expect(t.getRect(second).top, greaterThan(t.getRect(first).bottom));
      await t.scrollUntilVisible(
          find.byKey(const ValueKey('live-huud-live-7')), 180,
          scrollable: find
              .descendant(
                  of: find.byType(RefreshIndicator).first,
                  matching: find.byType(Scrollable))
              .first);
      await t.pump();
      expect(find.byKey(const ValueKey('live-huud-live-7')).hitTestable(),
          findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    }
  });
  testWidgets(
      'For you has the same plus flow; posting returns to friends-only Feeds',
      (t) async {
    final calls = <String>[];
    await open(t, (r) async {
      calls.add(
          '${r.method} ${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''}');
      return json(r.method == 'POST' ? {'kind': 'post'} : []);
    }, live: false);
    await t.tap(find.byKey(const ValueKey('huud-tab-for_you')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('feed-say')), findsNothing);
    await t.tap(find.byKey(const ValueKey('feed-create')));
    await t.pumpAndSettle();
    await t.tap(find.text('Post something'));
    await t.pumpAndSettle();
    await t.enterText(
        find.byKey(const ValueKey('feed-say')), 'See you in the Huud.');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('feed-say-post')));
    await t.pumpAndSettle();
    expect(calls, contains('POST /api/v1/huud/text-posts'));
    expect(t.getSemantics(find.byKey(const ValueKey('huud-tab-friends'))),
        isSemantics(isSelected: true));
    expect(find.byKey(const ValueKey('feed-say')), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('a failed post keeps the draft and can be retried once',
      (t) async {
    var posts = 0;
    final pending = Completer<http.Response>();
    await open(t, (r) async {
      if (r.method == 'POST') {
        posts++;
        return posts == 1
            ? json({'message': 'Try again shortly'}, 503)
            : pending.future;
      }
      return json([]);
    }, live: false);
    await t.tap(find.byKey(const ValueKey('feed-create')));
    await t.pumpAndSettle();
    await t.tap(find.text('Post something'));
    await t.pumpAndSettle();
    await t.enterText(
        find.byKey(const ValueKey('feed-say')), 'Keep this draft.');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('feed-say-post')));
    await t.pumpAndSettle();
    expect(find.text('Keep this draft.'), findsOneWidget);
    expect(find.text(userErrorMessage), findsOneWidget);
    expect(find.text('Try again shortly'), findsNothing);
    await t.tap(find.byKey(const ValueKey('feed-say-post')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('feed-say-post')));
    await t.pump();
    expect(posts, 2);
    pending.complete(json({'kind': 'post'}, 201));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('feed-say')), findsNothing);
    expect(t.takeException(), isNull);
  });
}
