import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/hangout_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/huudspace/huud_championship.dart';
import 'package:truearena/features/huudspace/huud_space_screen.dart';
import 'package:truearena/features/huudspace/huud_voice.dart';
import 'package:truearena/theme/neon_theme.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _member(String id, String name, {bool host = false}) =>
    {'userId': id, 'displayName': name, 'username': name.toLowerCase(), 'host': host, 'here': true};

Map<String, dynamic> _huud({bool host = true, String? championshipId}) => {
      'id': 'h1',
      'code': 'KTB7QX',
      'name': "Eric's Huud",
      'privacy': 'public',
      'status': 'active',
      'youCanSpeak': host,
      'requests': const [],
      'host': host ? _member('me', 'Eric', host: true) : _member('ada', 'Ada', host: true),
      'members': [
        host ? _member('me', 'Eric', host: true) : _member('ada', 'Ada', host: true),
        host ? _member('ada', 'Ada') : _member('me', 'Eric'),
        _member('chidi', 'Chidi'),
      ],
      'youAreIn': true,
      'youAreHost': host,
      'voiceRoom': 'huud-h1',
      'live': true,
      'youOwn': host,
      'memberCount': 3,
      'liveCount': 3,
      'championshipId': championshipId,
    };

Map<String, dynamic> _player(String id, String name, {bool out = false}) =>
    {'userId': id, 'name': name, 'username': name.toLowerCase(), 'out': out};

Map<String, dynamic> _match(String id, int round, String roundName, int position, String? a, String? b,
        {String status = 'active', String? winner, int watching = 0}) =>
    {
      'id': id,
      'round': round,
      'roundName': roundName,
      'position': position,
      'playerA': a,
      'playerB': b,
      'winnerId': winner,
      'status': status,
      'roomId': status == 'active' ? 'room-$id' : null,
      'voiceRoom': status == 'active' ? 'huud-h1-m-$id' : null,
      'gameNumber': 1,
      'watching': watching,
      'aReconnectMs': 180000,
      'bReconnectMs': 180000,
    };

final _eight = [
  _player('me', 'Eric'),
  _player('ada', 'Ada'),
  _player('john', 'John'),
  _player('sarah', 'Sarah'),
  _player('mike', 'Mike'),
  _player('tobi', 'Tobi'),
  _player('chris', 'Chris'),
  _player('jane', 'Jane'),
];

Map<String, dynamic> _cup({
  String status = 'registering',
  List<Map<String, dynamic>>? players,
  List<Map<String, dynamic>> matches = const [],
  bool registered = false,
  int round = 0,
  String? roundName,
  String? champion,
  String? runnerUp,
  String? yourMatch,
}) =>
    {
      'id': 'c1',
      'huudSpaceId': 'h1',
      'name': 'Chess Championship',
      'gameType': 'chess',
      'size': 8,
      'status': status,
      'roundTiming': 'simultaneous',
      'spectatorsAllowed': true,
      'graceSeconds': 180,
      'currentRound': round,
      'rounds': 3,
      'roundName': roundName,
      'players': players ?? [_player('ada', 'Ada'), _player('john', 'John')],
      'youAreRegistered': registered,
      'matches': matches,
      'championId': champion,
      'runnerUpId': runnerUp,
      'yourMatchId': yourMatch,
      'lobbyVoiceRoom': 'huud-h1',
    };

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    HuudVoice.instance.reset();
    HangoutState.instance.clear();
  });

  Future<List<String>> pump(WidgetTester tester, Future<http.Response> Function(http.Request) routes) async {
    final calls = <String>[];
    final mock = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}${request.body.isEmpty ? '' : ' ${request.body}'}');
      if (request.url.path == '/api/v1/friends') return _json(const []);
      if (request.url.path.endsWith('/messages')) return _json(const []);
      return routes(request);
    });
    final api = ApiClient(client: mock)..bearer = 'token';
    final state = AppState(api)
      ..user = const UserView(id: 'me', displayName: 'Eric Barima', username: 'eric', isGuest: false)
      ..identity = Identity.account;
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        AppScope(state: state, child: MaterialApp(theme: NeonTheme.light, home: const HuudSpaceScreen(id: 'h1'))));
    // The Live dot pulses for ever, so there's no "settled".
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    return calls;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('the host starts a championship from the Play tab and picks its settings', (tester) async {
    final calls = await pump(tester, (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1') return _json(_huud());
      if (r.url.path == '/api/v1/huud-spaces/h1/championship' && r.method == 'POST') {
        return _json(_cup(players: const []));
      }
      return http.Response('not found', 404);
    });

    // A normal game can still be picked, and a championship is offered on top.
    expect(find.byKey(const ValueKey('huud-pick-whot')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('huud-start-championship')));
    await settle(tester);

    expect(find.text('Start a championship'), findsWidgets);
    expect(find.textContaining('Knockout · one game a match'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cup-game-draughts')));
    await tester.tap(find.byKey(const ValueKey('cup-size-4')));
    await tester.ensureVisible(find.byKey(const ValueKey('cup-timing-sequential')));
    await tester.tap(find.byKey(const ValueKey('cup-timing-sequential')));
    await tester.ensureVisible(find.byKey(const ValueKey('cup-grace-5')));
    await tester.tap(find.byKey(const ValueKey('cup-grace-5')));
    await tester.ensureVisible(find.byKey(const ValueKey('cup-start')));
    await tester.tap(find.byKey(const ValueKey('cup-start')));
    await settle(tester);

    expect(
        calls,
        contains('POST /api/v1/huud-spaces/h1/championship '
            '{"gameType":"draughts","size":4,"roundTiming":"sequential","spectatorsAllowed":true,"graceMinutes":5}'));
  });

  testWidgets('a member registers for the championship and sees how many places are left', (tester) async {
    var registered = false;
    final calls = await pump(tester, (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1') return _json(_huud(host: false, championshipId: 'c1'));
      if (r.url.path == '/api/v1/huud-spaces/h1/championship/register') {
        registered = true;
        return _json(_cup(registered: true, players: [..._eight.take(2), _player('me', 'Eric')]));
      }
      if (r.url.path == '/api/v1/huud-spaces/h1/championship') {
        return _json(registered
            ? _cup(registered: true, players: [..._eight.skip(1).take(2), _player('me', 'Eric')])
            : _cup());
      }
      return http.Response('not found', 404);
    });

    expect(find.text('Chess Championship'), findsOneWidget);
    expect(find.text('Registration · 2 / 8 players'), findsOneWidget);
    // While the championship is on, the Huud doesn't offer other games.
    expect(find.byKey(const ValueKey('huud-start-championship')), findsNothing);
    expect(find.byKey(const ValueKey('cup-call-off')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cup-register')));
    await settle(tester);
    expect(calls, contains('POST /api/v1/huud-spaces/h1/championship/register {}'));
    expect(find.textContaining("You're in ✅ — waiting for 5 more"), findsOneWidget);
    expect(find.byKey(const ValueKey('cup-withdraw')), findsOneWidget);
  });

  testWidgets('quarter finals show every live match with who is watching, your own on top', (tester) async {
    final quarters = [
      _match('m1', 1, 'Quarter Finals', 1, 'me', 'ada', watching: 14),
      _match('m2', 1, 'Quarter Finals', 2, 'john', 'sarah', watching: 8),
      _match('m3', 1, 'Quarter Finals', 3, 'mike', 'tobi', watching: 11),
      _match('m4', 1, 'Quarter Finals', 4, 'chris', 'jane', watching: 5),
      _match('s1', 2, 'Semi Finals', 1, null, null, status: 'pending'),
      _match('s2', 2, 'Semi Finals', 2, null, null, status: 'pending'),
      _match('f1', 3, 'Final', 1, null, null, status: 'pending'),
    ];
    await pump(tester, (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1') return _json(_huud(host: false, championshipId: 'c1'));
      if (r.url.path == '/api/v1/huud-spaces/h1/championship') {
        return _json(_cup(
            status: 'playing',
            players: _eight,
            registered: true,
            matches: quarters,
            round: 1,
            roundName: 'Quarter Finals',
            yourMatch: 'm1'));
      }
      return http.Response('not found', 404);
    });

    expect(find.text('Quarter Finals'), findsWidgets);
    expect(find.byKey(const ValueKey('cup-your-match')), findsOneWidget);
    expect(find.text('You vs ada'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('cup-play')), findsOneWidget);
    expect(find.text('john vs sarah'), findsWidgets);
    expect(find.text('14 watching'), findsOneWidget);
    expect(find.text('5 watching'), findsOneWidget);
    expect(find.text("You're in the Championship Lobby"), findsOneWidget);
    expect(find.byKey(const ValueKey('cup-bracket')), findsOneWidget);
    expect(find.text('Watch'), findsNWidgets(3));
  });

  testWidgets('after the final the champion and runner-up show, and the host can go back to hanging out',
      (tester) async {
    var closed = false;
    final calls = await pump(tester, (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1' && r.method == 'GET') {
        return _json(_huud(championshipId: closed ? null : 'c1'));
      }
      if (r.url.path == '/api/v1/huud-spaces/h1/championship' && r.method == 'DELETE') {
        closed = true;
        return _json(_huud());
      }
      if (r.url.path == '/api/v1/huud-spaces/h1/championship') {
        return _json(_cup(
            status: 'finished',
            players: [_player('sarah', 'Sarah'), _player('ada', 'Ada', out: true)],
            matches: [_match('f1', 1, 'Final', 1, 'ada', 'sarah', status: 'completed', winner: 'sarah')],
            round: 1,
            roundName: 'Final',
            champion: 'sarah',
            runnerUp: 'ada'));
      }
      return http.Response('not found', 404);
    });

    expect(find.text('sarah is the champion!'), findsOneWidget);
    expect(find.text('🥈 Runner-up: ada'), findsOneWidget);
    expect(find.byKey(const ValueKey('cup-new')), findsOneWidget);
    expect(find.byKey(const ValueKey('cup-end-live')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('cup-hang-out')));
    await tester.tap(find.byKey(const ValueKey('cup-hang-out')));
    await settle(tester);
    expect(calls, contains('DELETE /api/v1/huud-spaces/h1/championship'));
    // Back to a normal Huud: pick a game again.
    expect(find.byKey(const ValueKey('huud-pick-whot')), findsOneWidget);
  });

  test('a match voice room still belongs to its Huud', () {
    HangoutState.instance
      ..open(const SizedBox.shrink(), 'huud-11111111-2222-3333-4444-555555555555-m-abc', 'Cup')
      ..onOpen = () {};
    expect(HuudVoice.instance.huudId, '11111111-2222-3333-4444-555555555555');
    expect(HuudVoice.instance.isInHuud('11111111-2222-3333-4444-555555555555'), isTrue);
    expect(HuudVoice.instance.isInHuud('99999999-2222-3333-4444-555555555555'), isFalse);
  });

  test('the bracket model finds the match whose voice you hear', () {
    final cup = HuudCup.fromJson(_cup(
        status: 'playing',
        players: _eight,
        matches: [_match('m1', 1, 'Quarter Finals', 1, 'me', 'ada'), _match('m2', 1, 'Quarter Finals', 2, 'john', 'sarah')]));
    expect(cup.liveMatchWithVoice('huud-h1-m-m2')?.id, 'm2');
    expect(cup.liveMatchWithVoice('huud-h1'), isNull);
    expect(cupMatchTitle(cup, cup.matches.first, me: 'me'), 'You vs ada');
  });
}
