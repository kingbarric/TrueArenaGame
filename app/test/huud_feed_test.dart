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
import 'package:truearena/features/huud/huud_models.dart';
import 'package:truearena/features/huud/huud_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _person(String id, String name, {bool friend = true}) =>
    {'userId': id, 'displayName': name, 'username': name.toLowerCase(), 'friend': friend};

final _now = DateTime.now().toUtc();

Map<String, dynamic> _challengeToMe() => {
      'kind': 'challenge',
      'id': 'post:c1',
      'at': _now.subtract(const Duration(minutes: 2)).toIso8601String(),
      'actor': _person('tobi', 'Tobi'),
      'gameType': 'whot',
      'game': {
        'postId': 'c1',
        'roomId': 'room-c1',
        'roomCode': 'ABCDEF',
        'ranked': false,
        'seatsTaken': 1,
        'seats': 2,
        'players': [_person('tobi', 'Tobi')],
        'expiresAt': _now.add(const Duration(minutes: 8)).toIso8601String(),
        'joined': false,
        'mine': false,
        'target': _person('me', 'Eric'),
        'lastOutcome': 'won',
      },
    };

Map<String, dynamic> _request() => {
      'kind': 'game_request',
      'id': 'post:r1',
      'at': _now.subtract(const Duration(minutes: 5)).toIso8601String(),
      'actor': _person('amaka', 'Amaka'),
      'gameType': 'draughts',
      'message': 'Ranked Draughts, anyone? Winner stays on.',
      'game': {
        'postId': 'r1',
        'roomId': 'room-r1',
        'roomCode': 'QWERTY',
        'ranked': true,
        'seatsTaken': 1,
        'seats': 2,
        'players': [_person('amaka', 'Amaka')],
        'expiresAt': _now.add(const Duration(minutes: 8)).toIso8601String(),
        'joined': false,
        'mine': false,
      },
    };

Map<String, dynamic> _win() => {
      'kind': 'win',
      'id': 'win:m1',
      'at': _now.subtract(const Duration(hours: 1)).toIso8601String(),
      'actor': _person('chidi', 'Chidi Nwosu', friend: false),
      'gameType': 'draughts',
      'win': {
        'matchId': 'm1',
        'ranked': true,
        'streak': 8,
        'recent': List.filled(8, 'won'),
        'rating': 1824.0,
        'weekDelta': 46.0,
        'beaten': ['Femi'],
      },
    };

Map<String, dynamic> _tournament() => {
      'kind': 'tournament',
      'id': 'tournament:t1',
      'at': _now.subtract(const Duration(hours: 3)).toIso8601String(),
      'actor': _person('host', 'PlayHuud', friend: false),
      'gameType': 'draughts',
      'tournament': {
        'championshipId': 't1',
        'code': 'NGDRAFTS',
        'name': 'Nigeria Draughts Championship',
        'size': 64,
        'joined': 32,
        'scheduledAt': _now.add(const Duration(days: 3)).toIso8601String(),
        'status': 'lobby',
        'viewerJoined': false,
      },
    };

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<List<String>> pumpFeed(WidgetTester tester, Future<http.Response> Function(http.Request) extra,
      {bool settle = true}) async {
    final calls = <String>[];
    final mock = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}${request.url.hasQuery ? '?${request.url.query}' : ''}');
      final path = request.url.path;
      if (path == '/api/v1/friends') return _json([_person('amaka', 'Amaka'), _person('tobi', 'Tobi')]);
      if (path == '/api/v1/competitive/games') return _json(['draughts']);
      return extra(request);
    });
    final state = AppState(ApiClient(client: mock))
      ..user = const UserView(id: 'me', displayName: 'Eric', username: 'eric')
      ..identity = Identity.account;
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(theme: NeonTheme.dark, home: const HuudScreen(startOnLiveNow: false)),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
    return calls;
  }

  testWidgets('Friends comes before For you and pins a challenge with Accept / Not now', (tester) async {
    final calls = await pumpFeed(tester, (request) async {
      if (request.url.path == '/api/v1/huud/feed') {
        expect(request.url.queryParameters['tab'], 'friends');
        return _json([_challengeToMe(), _request()]);
      }
      if (request.url.path == '/api/v1/huud/posts/c1/decline') return http.Response('', 200);
      return http.Response('not found', 404);
    });

    expect(calls.first, 'GET /api/v1/huud/feed?tab=friends&filter=all');
    final friendsTab = find.byKey(const ValueKey('huud-tab-friends'));
    final forYouTab = find.byKey(const ValueKey('huud-tab-for_you'));
    expect(find.descendant(of: friendsTab, matching: find.textContaining('Friends')), findsOneWidget);
    expect(find.descendant(of: forYouTab, matching: find.textContaining('For you')), findsOneWidget);
    // Friends sits left of For you, with Live now in front of both.
    expect(tester.getCenter(friendsTab).dx, lessThan(tester.getCenter(forYouTab).dx));
    expect(tester.getCenter(find.byKey(const ValueKey('huud-tab-live'))).dx,
        lessThan(tester.getCenter(friendsTab).dx));

    expect(find.textContaining('a Whot rematch'), findsOneWidget);
    expect(find.textContaining('You won the last one.'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);

    expect(find.text('Ranked Draughts, anyone? Winner stays on.'), findsOneWidget);
    expect(find.text('Join game'), findsOneWidget);
    expect(find.textContaining('min left'), findsWidgets);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/v1/huud/posts/c1/decline'));
  });

  testWidgets('For you shows verified wins and open tournaments; chips filter the feed', (tester) async {
    final calls = await pumpFeed(tester, (request) async {
      if (request.url.path == '/api/v1/huud/feed') {
        final tab = request.url.queryParameters['tab'];
        final filter = request.url.queryParameters['filter'];
        if (tab == 'friends') return _json([]);
        if (filter == 'wins') return _json([_win()]);
        return _json([_win(), _tournament()]);
      }
      return http.Response('not found', 404);
    });

    expect(find.textContaining('Nothing from your huud yet'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('huud-tab-for_you')));
    await tester.pumpAndSettle();
    expect(calls, contains('GET /api/v1/huud/feed?tab=for_you&filter=all'));

    expect(find.textContaining('8 Draughts games in a row'), findsOneWidget);
    expect(find.text('1,824'), findsOneWidget);
    expect(find.text('+46'), findsOneWidget);
    expect(find.text('Verified from match history'), findsOneWidget);
    expect(find.text('Nigeria Draughts Championship'), findsOneWidget);
    expect(find.textContaining('32/64 registered'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('huud-filter-wins')));
    await tester.pumpAndSettle();
    expect(calls, contains('GET /api/v1/huud/feed?tab=for_you&filter=wins'));
    expect(find.text('Nigeria Draughts Championship'), findsNothing);
  });

  testWidgets('the feed has no game-request box — it points to making a Huud instead', (tester) async {
    await pumpFeed(tester, (request) async => _json([]));
    expect(find.byKey(const ValueKey('huud-composer')), findsNothing);
    expect(find.text('What do you want to play?'), findsNothing);
    expect(find.byKey(const ValueKey('feed-make-huud')), findsOneWidget);
  });

  testWidgets('a shared Huud shows its line, the game and seats, and Join Huud', (tester) async {
    final calls = await pumpFeed(tester, (request) async {
      if (request.url.path == '/api/v1/huud/feed') {
        return _json([
          {
            'kind': 'huud',
            'id': 'huud:h1',
            'at': _now.subtract(const Duration(minutes: 1)).toIso8601String(),
            'actor': _person('eric', 'Eric'),
            'gameType': 'whot',
            'message': 'Who wants to play Whot?',
            'huud': {
              'huudSpaceId': 'h1',
              'name': "Eric's Huud",
              'privacy': 'friends',
              'people': 3,
              'players': 2,
              'seats': 4,
              'access': 'join',
              'gameStatus': 'waiting',
            },
          },
        ]);
      }
      if (request.url.path == '/api/v1/huud-spaces/h1/join') return http.Response('{}', 500);
      return http.Response('not found', 404);
    }, settle: false);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('“Who wants to play Whot?”'), findsOneWidget);
    expect(find.text("Eric's Huud"), findsOneWidget);
    expect(find.text('Whot · 2/4 playing'), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-huud-open-h1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('feed-huud-open-h1')), matching: find.text('Join Huud')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('feed-huud-open-h1')));
    await tester.pump();
    expect(calls, contains('POST /api/v1/huud-spaces/h1/join'));
  });

  Map<String, dynamic> requestNo(int i, {int taken = 1, int seats = 4, bool? filled, Duration left = const Duration(minutes: 8)}) => {
        'kind': 'game_request',
        'id': 'post:r$i',
        'at': _now.subtract(Duration(minutes: i)).toIso8601String(),
        'actor': _person('p$i', 'Player $i'),
        'gameType': 'whot',
        'message': 'Table number $i',
        'game': {
          'postId': 'r$i',
          'roomId': 'room-r$i',
          'roomCode': 'CODE$i',
          'ranked': false,
          'seatsTaken': taken,
          'seats': seats,
          'players': [for (var k = 0; k < taken; k++) _person('p$i-$k', 'Seat $k')],
          'expiresAt': _now.add(left).toIso8601String(),
          'joined': false,
          'mine': false,
          if (filled != null) 'filled': filled,
        },
      };

  testWidgets('a full page builds only the cards on screen, and scrolls to the last one', (tester) async {
    await pumpFeed(tester, (request) async {
      if (request.url.path == '/api/v1/huud/feed') return _json([for (var i = 0; i < 40; i++) requestNo(i)]);
      return http.Response('not found', 404);
    });

    final built = find.textContaining('Table number', skipOffstage: false).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(40), reason: 'every card was built up front — the feed lost its lazy list');

    await tester.scrollUntilVisible(find.text('Table number 39'), 600,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Table number 39'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('game art is decoded at the size it is shown, not the 1250px source', (tester) async {
    await pumpFeed(tester, (request) async {
      if (request.url.path == '/api/v1/huud/feed') return _json([requestNo(1)]);
      return http.Response('not found', 404);
    });
    final art = tester.widgetList<Image>(find.byType(Image)).where((i) => i.image is ResizeImage).toList();
    expect(art, isNotEmpty);
    for (final image in art) {
      expect((image.image as ResizeImage).width, lessThanOrEqualTo(48 * 3));
    }
  });

  testWidgets('a filled game stays on the feed, says Filled and cannot be joined', (tester) async {
    final calls = await pumpFeed(tester, (request) async {
      if (request.url.path == '/api/v1/huud/feed') {
        return _json([requestNo(1, taken: 4, seats: 4, filled: true), requestNo(2, taken: 1, seats: 6, filled: true)]);
      }
      return http.Response('not found', 404);
    });

    expect(find.byKey(const ValueKey('huud-filled')), findsNWidgets(2));
    expect(find.text('Join game'), findsNothing);
    expect(find.textContaining('min left'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('huud-filled')).first);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.contains('/rooms/join')), isEmpty);
  });

  test('an older server without the filled flag still reads a full table as filled', () {
    final full = HuudItem.fromJson(requestNo(1, taken: 4, seats: 4));
    final open = HuudItem.fromJson(requestNo(2, taken: 1, seats: 4));
    expect(full.game!.filled, isTrue);
    expect(open.game!.filled, isFalse);
  });

  testWidgets('a slow answer for the tab you left never replaces the tab you are on', (tester) async {
    final friends = Completer<http.Response>();
    await pumpFeed(tester, (request) async {
      if (request.url.path == '/api/v1/huud/feed') {
        if (request.url.queryParameters['tab'] == 'friends') return friends.future;
        return _json([_win()]);
      }
      return http.Response('not found', 404);
    }, settle: false);

    await tester.tap(find.byKey(const ValueKey('huud-tab-for_you')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('8 Draughts games in a row'), findsOneWidget);

    friends.complete(_json([_request()]));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('8 Draughts games in a row'), findsOneWidget);
    expect(find.text('Ranked Draughts, anyone? Winner stays on.'), findsNothing);

    // …and that answer is waiting, already loaded, when you go back.
    await tester.tap(find.byKey(const ValueKey('huud-tab-friends')));
    await tester.pump();
    expect(find.text('Ranked Draughts, anyone? Winner stays on.'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('search results for an older query never replace a newer one', (tester) async {
    final slow = Completer<http.Response>();
    await pumpFeed(tester, (request) async {
      if (request.url.path == '/api/v1/huud/feed') return _json([]);
      if (request.url.path == '/api/v1/friends/search') {
        final q = request.url.queryParameters['q'];
        if (q == 'a') return slow.future;
        return _json([
          {'userId': 'amaka', 'displayName': 'Amaka O.', 'username': 'amaka', 'isFriend': true, 'requestPending': false}
        ]);
      }
      return http.Response('not found', 404);
    });

    final field = find.byType(TextField).first;
    await tester.enterText(field, 'a');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(field, 'am');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('Amaka O.'), findsOneWidget);

    slow.complete(_json([
      {'userId': 'ada', 'displayName': 'Ada Stale', 'username': 'ada', 'isFriend': false, 'requestPending': false}
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Ada Stale'), findsNothing);
    expect(find.text('Amaka O.'), findsOneWidget);
  });

  testWidgets('the countdown re-renders without refetching, and expired cards drop out', (tester) async {
    final calls = await pumpFeed(tester, (request) async {
      if (request.url.path == '/api/v1/huud/feed') {
        return _json([requestNo(1, left: const Duration(seconds: 20)), requestNo(2)]);
      }
      return http.Response('not found', 404);
    });
    expect(find.text('Table number 1'), findsOneWidget);
    final feedCalls = calls.where((c) => c.contains('/huud/feed')).length;

    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 31));

    expect(find.text('Table number 1'), findsNothing);
    expect(find.text('Table number 2'), findsOneWidget);
    expect(calls.where((c) => c.contains('/huud/feed')).length, feedCalls);
  });

  testWidgets('a failed load shows Retry, and Retry recovers', (tester) async {
    var fail = true;
    await pumpFeed(tester, (request) async {
      if (request.url.path == '/api/v1/huud/feed') {
        if (fail) return _json({'message': 'feed is down'}, 503);
        return _json([_request()]);
      }
      return http.Response('not found', 404);
    });
    expect(find.text('feed is down'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('feed is down'), findsNothing);
    expect(find.text('Ranked Draughts, anyone? Winner stays on.'), findsOneWidget);
  });

  test('cards survive a sparse payload', () {
    final item = HuudItem.fromJson({
      'kind': 'win',
      'id': 'win:x',
      'at': _now.toIso8601String(),
      'actor': {'userId': 'u1'},
      'win': {'matchId': 'm'},
    });
    expect(item.actor.name, '');
    expect(item.win!.recent, isEmpty);
    expect(item.win!.streak, 0);
    expect(item.gameName, '');
  });

  test('time and number helpers', () {
    final now = DateTime.utc(2026, 10, 7, 12);
    expect(huudAgo(now.subtract(const Duration(minutes: 2)), now: now), '2m');
    expect(huudAgo(now.subtract(const Duration(hours: 3)), now: now), '3h');
    expect(huudTimeLeft(now.add(const Duration(minutes: 8, seconds: 30)), now: now), '8 min left');
    expect(huudTimeLeft(now.subtract(const Duration(seconds: 1)), now: now), isNull);
    expect(huudGrouped(1612), '1,612');
    expect(huudGrouped(1824.4), '1,824');
    expect(huudGrouped(999), '999');
    expect(huudArtworkId('wordbluff'), 'bluff');
  });

  testWidgets('friends can post a short text, and others\' posts can be reported', (tester) async {
    final calls = await pumpFeed(tester, (request) async {
      if (request.url.path == '/api/v1/huud/feed') {
        return _json([
          {
            'kind': 'post',
            'id': 'text:p1',
            'at': _now.subtract(const Duration(minutes: 3)).toIso8601String(),
            'actor': _person('tobi', 'Tobi'),
            'gameType': null,
            'message': 'Ludo at 6?',
          },
        ]);
      }
      if (request.url.path == '/api/v1/huud/text-posts') return _json({'kind': 'post'}, 201);
      return http.Response('', 200);
    });
    expect(find.byKey(const ValueKey('feed-say')), findsOneWidget);
    expect(find.text('👫 Only your friends see it'), findsOneWidget);
    expect(find.text('Ludo at 6?'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('feed-say')), 'Who wants to play later?');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('feed-say-post')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/v1/huud/text-posts'));

    await tester.tap(find.byKey(const ValueKey('feed-post-menu-text:p1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('safety-report')), findsOneWidget);
  });

}
