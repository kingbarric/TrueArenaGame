import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/huudspace/create_huud_sheet.dart';
import 'package:truearena/features/huudspace/huud_home_screen.dart';
import 'package:truearena/features/huudspace/huud_space_models.dart';
import 'package:truearena/features/huudspace/huud_space_screen.dart';
import 'package:truearena/features/huudspace/live_now_panel.dart';
import 'package:truearena/theme/neon_theme.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _member(String id, String name, {bool host = false, bool here = true}) =>
    {'userId': id, 'displayName': name, 'username': name.toLowerCase(), 'host': host, 'here': here};

Map<String, dynamic> _huud({
  bool host = true,
  bool inIt = true,
  Map<String, dynamic>? game,
  List<Map<String, dynamic>>? members,
}) =>
    {
      'id': 'h1',
      'code': inIt ? 'KTB7QX' : null,
      'name': "Eric's Huud",
      'privacy': 'friends',
      'status': 'active',
      'host': host ? _member('me', 'Eric', host: true) : _member('ada', 'Ada', host: true),
      'members': members ??
          [
            host ? _member('me', 'Eric', host: true) : _member('ada', 'Ada', host: true),
            host ? _member('ada', 'Ada') : _member('me', 'Eric'),
            _member('chidi', 'Chidi'),
          ],
      'currentGame': game,
      'youAreIn': inIt,
      'youAreHost': host,
      'voiceRoom': 'huud-h1',
    };

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<List<String>> pump(WidgetTester tester, Widget home, Future<http.Response> Function(http.Request) routes,
      {bool guest = false, bool settle = true}) async {
    final calls = <String>[];
    final mock = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}${request.body.isEmpty ? '' : ' ${request.body}'}');
      return routes(request);
    });
    final api = ApiClient(client: mock)..bearer = 'token';
    final state = AppState(api)
      ..user = UserView(id: 'me', displayName: 'Eric Barima', username: 'eric', isGuest: guest)
      ..identity = guest ? Identity.guest : Identity.account;
    await tester.binding.setSurfaceSize(const Size(390, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppScope(state: state, child: MaterialApp(theme: NeonTheme.light, home: home)));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // The Live dot pulses for ever, so there's no "settled".
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
    }
    return calls;
  }

  testWidgets('making a Huud asks only for a name and who can join — Friends is picked for you', (tester) async {
    final calls = await pump(
      tester,
      const Scaffold(body: CreateHuudSheet()),
      (r) async => r.url.path == '/api/v1/huud-spaces' ? _json(_huud()) : http.Response('not found', 404),
    );

    expect(find.text('Give it a name'), findsOneWidget);
    expect(find.text('Who can join?'), findsOneWidget);
    expect(find.textContaining('escription'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, "Eric's Huud");

    // Friends · Private · Public, in that order, Friends already chosen.
    final friends = find.byKey(const ValueKey('huud-privacy-friends'));
    final private = find.byKey(const ValueKey('huud-privacy-private'));
    final public = find.byKey(const ValueKey('huud-privacy-public'));
    expect(tester.getCenter(friends).dy, lessThan(tester.getCenter(private).dy));
    expect(tester.getCenter(private).dy, lessThan(tester.getCenter(public).dy));
    expect(tester.getSemantics(friends), isSemantics(isSelected: true));

    await tester.tap(find.byKey(const ValueKey('huud-create')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/v1/huud-spaces {"name":"Eric\'s Huud","privacy":"friends"}'));
  });

  testWidgets('choosing Public says to be kind and sends public', (tester) async {
    final calls = await pump(
      tester,
      const Scaffold(body: CreateHuudSheet()),
      (r) async => _json(_huud()),
    );
    await tester.tap(find.byKey(const ValueKey('huud-privacy-public')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Be kind'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Game Night');
    await tester.tap(find.byKey(const ValueKey('huud-create')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/v1/huud-spaces {"name":"Game Night","privacy":"public"}'));
  });

  testWidgets('the Huud tab shows Make a Huud, a code box and past Huuds with who was there', (tester) async {
    final calls = await pump(tester, const HuudHomeScreen(), (r) async {
      if (r.url.path == '/api/v1/huud-spaces/history') {
        return _json([
          {
            'id': 'old1',
            'name': 'Saturday Whot',
            'privacy': 'friends',
            'status': 'ended',
            'youCreated': true,
            'youAreHost': false,
            'host': _member('me', 'Eric', host: true),
            'participants': [_member('me', 'Eric', host: true), _member('ada', 'Ada'), _member('chidi', 'Chidi')],
            'games': ['whot', 'draughts'],
            'gamesPlayed': 3,
            'createdAt': DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String(),
          },
        ]);
      }
      return http.Response('not found', 404);
    });

    expect(calls.first, 'GET /api/v1/huud-spaces/history');
    expect(find.byKey(const ValueKey('huud-make')), findsOneWidget);
    expect(find.text('Got a code?'), findsOneWidget);
    expect(find.text('Saturday Whot'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('3 games played'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('huud-history-old1')));
    await tester.pumpAndSettle();
    expect(find.text('Who was there (3)'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Chidi'), findsOneWidget);
    expect(find.text('Eric (you)'), findsOneWidget);
    expect(find.text('Made by you'), findsOneWidget);
  });

  testWidgets('filters split Huuds you made from Huuds you joined', (tester) async {
    Map<String, dynamic> past(String id, String name, bool mine) => {
          'id': id,
          'name': name,
          'privacy': 'friends',
          'status': 'ended',
          'youCreated': mine,
          'youAreHost': false,
          'participants': [_member('me', 'Eric')],
          'games': <String>[],
          'gamesPlayed': 0,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        };
    await pump(tester, const HuudHomeScreen(),
        (r) async => _json([past('a', 'Mine', true), past('b', 'Theirs', false)]));

    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Theirs'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('huud-filter-joined')));
    await tester.pumpAndSettle();
    expect(find.text('Mine'), findsNothing);
    expect(find.text('Theirs'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('huud-filter-mine')));
    await tester.pumpAndSettle();
    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Theirs'), findsNothing);
  });

  testWidgets('a live Huud you are in sits on top with Go in, and hosting hides Make a Huud', (tester) async {
    await pump(tester, const HuudHomeScreen(), (r) async {
      if (r.url.path == '/api/v1/huud-spaces/history') {
        return _json([
          {
            'id': 'h1',
            'name': "Eric's Huud",
            'privacy': 'friends',
            'status': 'active',
            'youCreated': true,
            'youAreHost': true,
            'participants': [_member('me', 'Eric', host: true), _member('ada', 'Ada')],
            'games': <String>[],
            'gamesPlayed': 0,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        ]);
      }
      return _json(_huud());
    });
    expect(find.byKey(const ValueKey('huud-go-in-h1')), findsOneWidget);
    expect(find.text('2 people'), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-make')), findsNothing);
  });

  testWidgets('typing a code joins that Huud', (tester) async {
    final calls = await pump(tester, const HuudHomeScreen(), (r) async {
      if (r.url.path == '/api/v1/huud-spaces/history') return _json([]);
      if (r.url.path == '/api/v1/huud-spaces/join') return _json(_huud(host: false));
      return _json(_huud(host: false));
    });
    await tester.enterText(find.byKey(const ValueKey('huud-code-input')), 'ktb7qx');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('huud-code-join')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/v1/huud-spaces/join {"code":"KTB7QX"}'));
    expect(find.byKey(const ValueKey('huud-title')), findsOneWidget);
  });

  testWidgets('inside: the host sees the code and picks a game from the grid', (tester) async {
    final calls = await pump(tester, const HuudSpaceScreen(id: 'h1'), (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1/game') {
        return _json({
          'id': 'room1',
          'code': 'AB12CD',
          'hostId': 'me',
          'status': 'lobby',
          'gameType': 'whot',
          'stakeCoins': 0,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'members': <dynamic>[],
          'ranked': false,
        });
      }
      return _json(_huud());
    });

    expect(find.text('KTB7QX'), findsOneWidget);
    expect(find.text("👑 You're the host"), findsOneWidget);
    expect(find.text('3 people in here'), findsOneWidget);
    expect(find.text('Pick a game to play'), findsOneWidget);
    for (final g in ['whot', 'draughts', 'chess', 'ludo']) {
      expect(find.byKey(ValueKey('huud-pick-$g')), findsOneWidget);
    }
    // Talk, Invite, People, Leave — each a picture and a word.
    for (final word in ['Talk', 'Invite', 'People', 'Leave']) {
      expect(find.text(word), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('huud-pick-whot')));
    await tester.pump();
    expect(calls, contains('POST /api/v1/huud-spaces/h1/game {"gameType":"whot"}'));
  });

  testWidgets('inside: a member waits for the host, then can join the game the host picked', (tester) async {
    var game = false;
    await pump(tester, const HuudSpaceScreen(id: 'h1'), (r) async => _json(_huud(
        host: false,
        game: game ? {'roomId': 'room1', 'code': 'AB12CD', 'gameType': 'draughts', 'status': 'waiting', 'players': 1} : null)));

    expect(find.text('No game yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-pick-whot')), findsNothing);
    expect(find.byKey(const ValueKey('huud-settings')), findsNothing);
    expect(find.byKey(const ValueKey('huud-end')), findsNothing);

    game = true;
    // The screen refreshes itself every few seconds.
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('Get ready for Draughts'), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-open-game')), findsOneWidget);
  });

  testWidgets('a host leaving is told who takes over before anything happens', (tester) async {
    final calls = await pump(tester, const HuudSpaceScreen(id: 'h1'), (r) async => _json(_huud()));
    await tester.tap(find.byKey(const ValueKey('huud-leave')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ada will become the host'), findsOneWidget);
    await tester.tap(find.text('No, stay'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.contains('/leave')), isEmpty);
  });

  testWidgets('the People tab shows the host crown and who is here', (tester) async {
    await pump(tester, const HuudSpaceScreen(id: 'h1'), (r) async => _json(_huud(members: [
          _member('me', 'Eric', host: true),
          _member('ada', 'Ada'),
          _member('chidi', 'Chidi', here: false),
        ])));
    await tester.tap(find.byKey(const ValueKey('huud-tab-people')));
    await tester.pumpAndSettle();
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
    expect(find.text('Here now'), findsOneWidget);
    expect(find.text('Away'), findsOneWidget);
    expect(find.textContaining('tap someone to take them out'), findsOneWidget);
  });

  testWidgets('looking in from Live: no code, one big Join button', (tester) async {
    final calls = await pump(tester, const HuudSpaceScreen(id: 'h1'), (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1/join') return _json(_huud(host: false));
      return _json(_huud(host: false, inIt: false));
    });
    expect(find.text('KTB7QX'), findsNothing);
    expect(find.byKey(const ValueKey('huud-leave')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('huud-join')));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.startsWith('POST /api/v1/huud-spaces/h1/join')), hasLength(1));
    expect(find.text('KTB7QX'), findsOneWidget);
  });

  testWidgets('Live now lists live Huuds with what they are playing, and games to watch', (tester) async {
    await pump(tester, const Scaffold(body: LiveNowPanel()), (r) async {
      if (r.url.path == '/api/v1/huud-spaces/live') {
        return _json([
          {
            'id': 'h2',
            'name': "Ada's Huud",
            'privacy': 'public',
            'host': _member('ada', 'Ada', host: true),
            'memberCount': 4,
            'members': [_member('ada', 'Ada', host: true), _member('chidi', 'Chidi')],
            'gameType': 'whot',
            'gameStatus': 'playing',
            'youAreIn': false,
          },
        ]);
      }
      if (r.url.path == '/api/v1/rooms/discoverable') {
        return _json([
          {'roomId': 'r9', 'code': 'QQQQQQ', 'gameType': 'chess', 'hostName': 'Tobi', 'connectedCount': 2},
        ]);
      }
      return http.Response('not found', 404);
    }, settle: false);
    expect(find.text("Ada's Huud"), findsOneWidget);
    expect(find.text('Playing Whot'), findsOneWidget);
    expect(find.text('4 in here'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-enter-h2')), findsOneWidget);
    expect(find.text("Tobi's Chess"), findsOneWidget);
  });

  testWidgets('Live now with nobody on offers to make a Huud', (tester) async {
    await pump(tester, const Scaffold(body: LiveNowPanel()), (r) async => _json([]));
    expect(find.text("Nobody's live right now"), findsOneWidget);
    expect(find.byKey(const ValueKey('live-make-huud')), findsOneWidget);
  });

  test('privacy reads in kid-sized words and dates read like people talk', () {
    expect(HuudPrivacy.values.map((p) => p.label), ['Friends', 'Private', 'Public']);
    expect(HuudPrivacyInfo.parse(null), HuudPrivacy.friends);
    final now = DateTime(2026, 10, 9, 12);
    expect(huudWhen(DateTime(2026, 10, 9, 8), now: now), 'Today');
    expect(huudWhen(DateTime(2026, 10, 8, 23), now: now), 'Yesterday');
    expect(huudWhen(DateTime(2026, 10, 5), now: now), '4 days ago');
    expect(huudWhen(DateTime(2026, 9, 1), now: now), '1 Sep');
  });
}
