import 'dart:convert';
import 'package:truearena/features/huudspace/huud_lounge.dart';

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
import 'package:truearena/features/huudspace/huud_kit.dart';
import 'package:truearena/features/huudspace/huud_space_models.dart';
import 'package:truearena/features/huudspace/huud_space_screen.dart';
import 'package:truearena/features/huudspace/huud_voice.dart';
import 'package:truearena/theme/neon_theme.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _member(String id, String name, {bool host = false}) =>
    {'userId': id, 'displayName': name, 'username': name.toLowerCase(), 'host': host, 'here': true};

Map<String, dynamic> _huud({bool host = true, bool? owns, String? championshipId}) => {
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
      'youOwn': owns ?? host,
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
  DateTime? startsAt,
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
      'startsAt': (startsAt ?? DateTime.now().add(const Duration(hours: 1))).toUtc().toIso8601String(),
      'minPlayers': 4,
    };

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    HuudLounge.debugScenePlaceholder = true;
    addTearDown(() => HuudLounge.debugScenePlaceholder = false);
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
    await tester.tap(find.byKey(const ValueKey('huud-tab-play')));
    await tester.pump(const Duration(milliseconds: 500));
    return calls;
  }

  String cupName(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const ValueKey('cup-name-field'))).controller!.text;

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
    // Name and start are filled in already; the name follows the game until the host types one.
    expect(cupName(tester), 'Chess Championship');
    expect(find.text('📅  Today'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cup-game-draughts')));
    await tester.pump();
    expect(cupName(tester), 'Draughts Championship');
    await tester.tap(find.byKey(const ValueKey('cup-size-4')));
    await tester.ensureVisible(find.byKey(const ValueKey('cup-timing-sequential')));
    await tester.tap(find.byKey(const ValueKey('cup-timing-sequential')));
    await tester.ensureVisible(find.byKey(const ValueKey('cup-grace-5')));
    await tester.tap(find.byKey(const ValueKey('cup-grace-5')));
    await tester.ensureVisible(find.byKey(const ValueKey('cup-start')));
    await tester.tap(find.byKey(const ValueKey('cup-start')));
    await settle(tester);

    final sent = calls.firstWhere((c) => c.startsWith('POST /api/v1/huud-spaces/h1/championship '));
    final body = jsonDecode(sent.substring(sent.indexOf('{'))) as Map<String, dynamic>;
    expect(body, containsPair('gameType', 'draughts'));
    expect(body, containsPair('size', 4));
    expect(body, containsPair('roundTiming', 'sequential'));
    expect(body, containsPair('spectatorsAllowed', true));
    expect(body, containsPair('graceMinutes', 5));
    expect(body, containsPair('name', 'Draughts Championship'));
    // About 15 minutes from now, on a five-minute mark.
    final startsAt = DateTime.parse(body['startsAt'] as String).toLocal();
    expect(startsAt.minute % 5, 0);
    expect(startsAt.difference(DateTime.now()).inMinutes, inInclusiveRange(14, 20));
  });

  testWidgets('the host names the championship', (tester) async {
    final calls = await pump(tester, (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1') return _json(_huud());
      if (r.url.path == '/api/v1/huud-spaces/h1/championship' && r.method == 'POST') {
        return _json(_cup(players: const []));
      }
      return http.Response('not found', 404);
    });

    await tester.tap(find.byKey(const ValueKey('huud-start-championship')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('cup-name-field')), 'Friday Night Chess');
    // A name of your own stays when you switch games.
    await tester.tap(find.byKey(const ValueKey('cup-game-draughts')));
    await tester.pump();
    expect(cupName(tester), 'Friday Night Chess');
    await tester.ensureVisible(find.byKey(const ValueKey('cup-start')));
    await tester.tap(find.byKey(const ValueKey('cup-start')));
    await settle(tester);

    expect(calls, contains(matches(RegExp(r'POST /api/v1/huud-spaces/h1/championship .*"name":"Friday Night Chess"'))));
  });

  testWidgets('a championship can have 32 or 64 players', (tester) async {
    final calls = await pump(tester, (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1') return _json(_huud());
      if (r.url.path == '/api/v1/huud-spaces/h1/championship' && r.method == 'POST') {
        return _json(_cup(players: const []));
      }
      return http.Response('not found', 404);
    });

    await tester.tap(find.byKey(const ValueKey('huud-start-championship')));
    await settle(tester);
    for (final size in [4, 8, 16, 32, 64]) {
      expect(find.byKey(ValueKey('cup-size-$size')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('cup-size-64')));
    await tester.ensureVisible(find.byKey(const ValueKey('cup-start')));
    await tester.tap(find.byKey(const ValueKey('cup-start')));
    await settle(tester);

    expect(calls, contains(matches(RegExp(r'POST /api/v1/huud-spaces/h1/championship .*"size":64'))));
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
        return _json(
            registered ? _cup(registered: true, players: [..._eight.skip(1).take(2), _player('me', 'Eric')]) : _cup());
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
    expect(find.text("You're in ✅"), findsOneWidget);
    expect(find.byKey(const ValueKey('cup-starts')), findsOneWidget);
    expect(find.textContaining('Starts '), findsOneWidget); // The scheduled time may fall tomorrow near midnight.
    expect(find.byKey(const ValueKey('cup-withdraw')), findsOneWidget);
  });

  testWidgets('the host can start early once four have registered; empty places become byes', (tester) async {
    var started = false;
    final five = _eight.take(5).toList();
    final calls = await pump(tester, (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1') return _json(_huud(championshipId: 'c1'));
      if (r.url.path == '/api/v1/huud-spaces/h1/championship/start') {
        started = true;
        return _json(_cup(status: 'playing', players: five, round: 1, roundName: 'Quarter Finals'));
      }
      if (r.url.path == '/api/v1/huud-spaces/h1/championship') {
        return _json(started
            ? _cup(status: 'playing', players: five, round: 1, roundName: 'Quarter Finals')
            : _cup(players: five));
      }
      return http.Response('not found', 404);
    });

    await tester.ensureVisible(find.byKey(const ValueKey('cup-start-now')));
    expect(find.text('Start now with 5 players'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cup-start-now')));
    await settle(tester);
    expect(find.textContaining('3 players get a bye'), findsOneWidget);
    await tester.tap(find.text('Start now').last);
    await settle(tester);
    expect(calls, contains('POST /api/v1/huud-spaces/h1/championship/start {}'));
  });

  testWidgets('three registered is not enough to start early', (tester) async {
    await pump(tester, (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1') return _json(_huud(championshipId: 'c1'));
      if (r.url.path == '/api/v1/huud-spaces/h1/championship') return _json(_cup(players: _eight.take(3).toList()));
      return http.Response('not found', 404);
    });
    await tester.ensureVisible(find.byKey(const ValueKey('cup-start-now')));
    expect(find.text('Start now · needs 4 players'), findsOneWidget);
    final button = tester.widget<HuudButton>(find.byKey(const ValueKey('cup-start-now')));
    expect(button.onPressed, isNull);
  });

  test('a new championship starts about 15 minutes from now, on a five-minute mark', () {
    expect(defaultCupStart(DateTime(2026, 10, 13, 19, 31)), DateTime(2026, 10, 13, 19, 50));
    expect(defaultCupStart(DateTime(2026, 10, 13, 19, 30)), DateTime(2026, 10, 13, 19, 45));
    expect(defaultCupStart(DateTime(2026, 10, 13, 23, 58)), DateTime(2026, 10, 14, 0, 15));
    expect(cupDay(DateTime(2026, 10, 14, 8), now: DateTime(2026, 10, 13, 22)), 'Tomorrow');
    expect(cupDay(DateTime(2026, 10, 18, 20), now: DateTime(2026, 10, 13, 22)), 'Sun 18 Oct');
    expect([4, 5, 8, 9, 33, 64].map(cupField), [4, 8, 8, 16, 64, 64]);
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
    expect(find.byKey(const ValueKey('cup-badge')), findsOneWidget);
    expect(find.text("sarah wins the champion's badge."), findsOneWidget);
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

  testWidgets("a temporary host cannot end Live from another owner's championship results", (tester) async {
    await pump(tester, (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1') {
        return _json(_huud(host: true, owns: false, championshipId: 'c1'));
      }
      if (r.url.path == '/api/v1/huud-spaces/h1/championship') {
        return _json(_cup(status: 'finished', champion: 'sarah', runnerUp: 'ada'));
      }
      return http.Response('not found', 404);
    });
    expect(find.byKey(const ValueKey('huud-end')), findsNothing);
    expect(find.byKey(const ValueKey('cup-end-live')), findsNothing);
    expect(find.byKey(const ValueKey('cup-hang-out')), findsOneWidget);
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
    final cup = HuudCup.fromJson(_cup(status: 'playing', players: _eight, matches: [
      _match('m1', 1, 'Quarter Finals', 1, 'me', 'ada'),
      _match('m2', 1, 'Quarter Finals', 2, 'john', 'sarah')
    ]));
    expect(cup.liveMatchWithVoice('huud-h1-m-m2')?.id, 'm2');
    expect(cup.liveMatchWithVoice('huud-h1'), isNull);
    expect(cupMatchTitle(cup, cup.matches.first, me: 'me'), 'You vs ada');
  });

  test('Live and Huud tab cards say a championship is on instead of the game', () {
    final live = LiveHuud.fromJson({
      'id': 'h1',
      'name': "Eric's Huud",
      'privacy': 'public',
      'memberCount': 9,
      'members': const [],
      'youAreIn': false,
      'gameType': null,
      'championship': {
        'name': 'Chess Championship',
        'gameType': 'chess',
        'status': 'playing',
        'roundName': 'Quarter Finals'
      },
    });
    expect(live.championship?.text, '🏆 Chess Championship · Quarter Finals');

    final mine = MyHuud.fromJson({
      'id': 'h1',
      'name': "Eric's Huud",
      'privacy': 'public',
      'live': true,
      'youOwn': true,
      'memberCount': 9,
      'liveCount': 9,
      'members': const [],
      'championship': {'name': 'Draughts Championship', 'gameType': 'draughts', 'status': 'registering'},
    });
    expect(
        huudStatusLine(
            live: true,
            liveCount: 9,
            memberCount: 9,
            game: 'Whot',
            gameStatus: 'playing',
            championship: mine.championship),
        'Live now · 9 in Huud · 🏆 Draughts Championship · sign up now');
    expect(const HuudCupLine(name: 'Chess Championship', gameType: 'chess', status: 'playing', roundName: 'Final').text,
        '🏆 Chess Championship · the Final');
    expect(const HuudCupLine(name: 'Chess Championship', gameType: 'chess', status: 'finished').text,
        '🏆 Chess Championship · finished');
    // No championship: the game line as before.
    expect(huudStatusLine(live: true, liveCount: 3, memberCount: 4, game: 'Whot', gameStatus: 'playing'),
        'Live now · 3 in Huud · Playing Whot');
  });

  testWidgets('in a Huud, a sideways swipe moves between People, Game and Chat', (tester) async {
    await pump(tester, (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1') return _json(_huud());
      return http.Response('not found', 404);
    });
    void on(String tab) =>
        expect(tester.getSemantics(find.byKey(ValueKey('huud-tab-$tab'))), isSemantics(isSelected: true));
    await tester.tap(find.byKey(const ValueKey('huud-tab-people')));
    await settle(tester);
    on('people');
    await tester.fling(find.byKey(const ValueKey('huud-tab-people')), const Offset(-300, 0), 1500);
    await settle(tester);
    on('play');
    await tester.fling(find.byKey(const ValueKey('huud-tab-play')), const Offset(-300, 0), 1500);
    await settle(tester);
    on('chat');
    await tester.fling(find.byKey(const ValueKey('huud-tab-chat')), const Offset(-300, 0), 1500);
    await settle(tester);
    on('chat');
    await tester.fling(find.byKey(const ValueKey('huud-tab-chat')), const Offset(300, 0), 1500);
    await settle(tester);
    on('play');
  });
}
