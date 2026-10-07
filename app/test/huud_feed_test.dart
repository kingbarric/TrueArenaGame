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

  Future<List<String>> pumpFeed(WidgetTester tester, Future<http.Response> Function(http.Request) extra) async {
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
      child: MaterialApp(theme: NeonTheme.dark, home: const HuudScreen()),
    ));
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('Your Huud comes first and pins a challenge with Accept / Not now', (tester) async {
    final calls = await pumpFeed(tester, (request) async {
      if (request.url.path == '/api/v1/huud/feed') {
        expect(request.url.queryParameters['tab'], 'friends');
        return _json([_challengeToMe(), _request()]);
      }
      if (request.url.path == '/api/v1/huud/posts/c1/decline') return http.Response('', 200);
      return http.Response('not found', 404);
    });

    expect(calls.first, 'GET /api/v1/huud/feed?tab=friends&filter=all');
    expect(find.text('Your Huud'), findsOneWidget);
    expect(find.text('For you'), findsOneWidget);
    // Your Huud sits left of For you.
    expect(tester.getCenter(find.text('Your Huud')).dx, lessThan(tester.getCenter(find.text('For you')).dx));

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

  testWidgets('posting sends the game, message and ranked flag', (tester) async {
    Map<String, dynamic>? posted;
    await pumpFeed(tester, (request) async {
      if (request.url.path == '/api/v1/huud/feed') return _json([]);
      if (request.method == 'POST' && request.url.path == '/api/v1/huud/posts') {
        posted = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({'message': 'not enough coins'}, 409);
      }
      return http.Response('not found', 404);
    });

    await tester.enterText(find.byKey(const ValueKey('huud-composer')), 'Winner stays on.');
    await tester.tap(find.text('Casual')); // draughts is rated → toggle to ranked
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('huud-post')));
    await tester.pumpAndSettle();

    expect(posted, {'gameType': 'draughts', 'message': 'Winner stays on.', 'ranked': true});
    expect(find.text('not enough coins'), findsOneWidget);
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
}
