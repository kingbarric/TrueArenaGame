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
      'gameType': null,
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
      'live Huuds stay compact with room for people above the shell menu',
      (t) async {
    await open(
        t,
        (r) async => r.url.path.endsWith('/huud-spaces/live')
            ? json(List.generate(8, liveRoom))
            : json([]));
    final cards = [
      for (var i = 0; i < 4; i++) find.byKey(ValueKey('live-huud-live-$i'))
    ];
    for (final card in cards) {
      expect(card, findsOneWidget);
      expect(t.getRect(card).height, inInclusiveRange(105.9, 128.1));
      expect(t.getRect(card).bottom, lessThanOrEqualTo(844 - 34 - 130));
    }
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('live-enter-live-$i')).hitTestable(),
          findsOneWidget);
    }
    final people = find.byKey(const ValueKey('live-members-live-0'));
    expect(
        find.descendant(of: people, matching: find.text('+1')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('compact live rooms remain readable and scroll at enlarged text',
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
      await t.scrollUntilVisible(
          find.byKey(const ValueKey('live-enter-live-7')), 180,
          scrollable: find
              .descendant(
                  of: find.byType(RefreshIndicator).first,
                  matching: find.byType(Scrollable))
              .first);
      await t.pump();
      expect(find.byKey(const ValueKey('live-enter-live-7')).hitTestable(),
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
