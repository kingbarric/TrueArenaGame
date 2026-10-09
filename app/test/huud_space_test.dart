import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/lobby/joined_room_screen.dart';
import 'package:truearena/features/huudspace/create_huud_sheet.dart';
import 'package:truearena/features/huudspace/huud_home_screen.dart';
import 'package:truearena/features/huudspace/huud_space_models.dart';
import 'package:truearena/features/huudspace/huud_space_screen.dart';
import 'package:truearena/features/huudspace/huud_voice.dart';
import 'package:truearena/core/hangout_state.dart';
import 'package:truearena/features/huudspace/live_now_panel.dart';
import 'package:truearena/features/huudspace/safety_sheet.dart';
import 'package:truearena/features/huudspace/huud_swipe_screen.dart';
import 'package:truearena/widgets/talking_row.dart';
import 'package:truearena/widgets/gift_splash.dart';
import 'package:truearena/features/huudspace/huud_kit.dart';
import 'dart:async';
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
  String privacy = 'friends',
  String? joinRequest,
  String? playRequest,
  List<Map<String, dynamic>> requests = const [],
  bool live = true,
  bool? owns,
  bool muted = false,
}) {
  final people = members ??
      [
        host ? _member('me', 'Eric', host: true) : _member('ada', 'Ada', host: true),
        host ? _member('ada', 'Ada') : _member('me', 'Eric'),
        _member('chidi', 'Chidi'),
      ];
  return {
    'id': 'h1',
    'code': inIt ? 'KTB7QX' : null,
    'name': "Eric's Huud",
    'privacy': privacy,
    'status': 'active',
    'youCanSpeak': host,
    'joinRequest': joinRequest,
    'playRequest': playRequest,
    'requests': requests,
    'host': host ? _member('me', 'Eric', host: true) : _member('ada', 'Ada', host: true),
    'members': people,
    'currentGame': game,
    'youAreIn': inIt,
    'youAreHost': host,
    'voiceRoom': 'huud-h1',
    'live': live,
    'youOwn': owns ?? host,
    'muted': muted,
    'memberCount': people.length,
    'liveCount': live ? people.where((m) => m['here'] == true).length : 0,
  };
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    HuudVoice.instance.reset();
    HangoutState.instance.clear();
  });

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

  Map<String, dynamic> mine(String id, String name,
          {bool live = false, bool owns = true, bool muted = false, String? game, int members = 3, int here = 0}) =>
      {
        'id': id,
        'name': name,
        'privacy': 'friends',
        'live': live,
        'youOwn': owns,
        'youAreHost': owns && live,
        'host': owns ? _member('me', 'Eric', host: true) : _member('ada', 'Ada', host: true),
        'memberCount': members,
        'liveCount': here,
        'members': [_member('me', 'Eric', host: owns), _member('ada', 'Ada', host: !owns)],
        'gameType': game,
        'gameStatus': game == null ? null : 'playing',
        'muted': muted,
      };

  testWidgets('no Huud yet: Make your Huud and a code box', (tester) async {
    final calls = await pump(tester, const HuudHomeScreen(), (r) async => _json([]));
    expect(calls.first, 'GET /api/v1/huud-spaces/mine');
    expect(find.byKey(const ValueKey('huud-make')), findsOneWidget);
    expect(find.text('Got a code?'), findsOneWidget);
  });

  testWidgets('your Huud stays when offline: Go Live asks who to tell, then goes Live', (tester) async {
    final calls = await pump(tester, const HuudHomeScreen(), (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1/live') return _json(_huud());
      if (r.url.path == '/api/v1/huud-spaces/mine') {
        return _json([
          mine('h1', "Eric's Huud"),
          mine('h2', "Ada's Huud", owns: false, live: true, here: 4, members: 8, game: 'whot'),
          mine('h3', 'Chess Club', owns: false, muted: true, members: 5),
        ]);
      }
      return _json(_huud());
    }, settle: false);
    expect(find.byKey(const ValueKey('huud-make')), findsNothing);
    expect(find.text('Offline · 3 members'), findsOneWidget);
    expect(find.byKey(const ValueKey('member-huud-h2')), findsOneWidget);
    expect(find.text('Live now · 4 in Huud · Playing Whot'), findsOneWidget);
    expect(find.text('Offline · 5 members'), findsOneWidget);
    expect(find.text('🔕'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('huud-go-live-h1')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Who should we tell?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('golive-online')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('golive-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls, contains('POST /api/v1/huud-spaces/h1/live {"notify":"online"}'));
  });

  testWidgets('a Live Huud of yours has Go in', (tester) async {
    await pump(tester, const HuudHomeScreen(), (r) async => _json([mine('h1', "Eric's Huud", live: true, here: 2)]),
        settle: false);
    expect(find.byKey(const ValueKey('huud-go-in-h1')), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-go-live-h1')), findsNothing);
  });

  testWidgets('typing a code joins that Huud', (tester) async {
    final calls = await pump(tester, const HuudHomeScreen(), (r) async {
      if (r.url.path == '/api/v1/huud-spaces/mine') return _json([]);
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
    expect(find.text('3 in Huud · 3 members'), findsOneWidget);
    expect(find.text('Pick a game to play'), findsOneWidget);
    for (final g in ['whot', 'draughts', 'chess', 'ludo']) {
      expect(find.byKey(ValueKey('huud-pick-$g')), findsOneWidget);
    }
    // Talk and Invite — each a picture and a word. It's your Huud, so no Leave.
    // The mic starts muted; voice is joined on its own (no call screen).
    for (final word in ['Muted', 'Invite']) {
      expect(find.text(word), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('huud-leave')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('huud-pick-whot')));
    await tester.pump();
    expect(calls, contains('POST /api/v1/huud-spaces/h1/game {"gameType":"whot"}'));
  });

  testWidgets('inside: a member waits for the host, then can join the game the host picked', (tester) async {
    var game = false;
    await pump(
        tester,
        const HuudSpaceScreen(id: 'h1'),
        (r) async => _json(_huud(
            host: false,
            game: game
                ? {
                    'roomId': 'room1',
                    'code': 'AB12CD',
                    'gameType': 'draughts',
                    'status': 'waiting',
                    'players': 1,
                    'seats': 2,
                    'playerIds': ['ada'],
                  }
                : null)));

    expect(find.text('No game yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-pick-whot')), findsNothing);
    expect(find.byKey(const ValueKey('huud-settings')), findsNothing);
    expect(find.byKey(const ValueKey('huud-end')), findsNothing);

    game = true;
    // The screen refreshes itself every few seconds.
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('Get ready for Draughts'), findsOneWidget);
    expect(find.text('1 / 2 seats taken'), findsOneWidget);
    // Being in the Huud isn't a seat: members ask.
    expect(find.byKey(const ValueKey('huud-open-game')), findsNothing);
    expect(find.byKey(const ValueKey('huud-ask-play')), findsOneWidget);
  });

  testWidgets('leaving a Huud is leaving it for good — you are told before anything happens', (tester) async {
    final calls = await pump(tester, const HuudSpaceScreen(id: 'h1'), (r) async => _json(_huud(host: false)));
    await tester.tap(find.byKey(const ValueKey('huud-leave')));
    await tester.pumpAndSettle();
    expect(find.textContaining('stop getting notifications'), findsOneWidget);
    await tester.tap(find.text('No, stay'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.contains('/leave')), isEmpty);
  });

  testWidgets('End Live keeps the Huud: chat and people stay, the owner can Go Live again', (tester) async {
    var live = true;
    final calls = await pump(tester, const HuudSpaceScreen(id: 'h1'), (r) async {
      if (r.method == 'DELETE' && r.url.path == '/api/v1/huud-spaces/h1/live') live = false;
      if (r.url.path.endsWith('/messages')) return _json([]);
      return _json(_huud(live: live));
    });
    expect(find.text('End Live'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('huud-end')));
    await tester.pumpAndSettle();
    expect(find.textContaining('members, chat and code are kept'), findsOneWidget);
    await tester.tap(find.text('End Live').last);
    await tester.pumpAndSettle();
    expect(calls, contains('DELETE /api/v1/huud-spaces/h1/live'));
    expect(find.byKey(const ValueKey('huud-offline-owner')), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-go-live')), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-tab-play')), findsNothing);
    expect(find.byKey(const ValueKey('huud-tab-chat')), findsOneWidget);
    expect(find.text('KTB7QX'), findsOneWidget);
  });

  testWidgets('a member of an offline Huud is told they will hear, and can mute it with the bell', (tester) async {
    var muted = false;
    final calls = await pump(tester, const HuudSpaceScreen(id: 'h1'), (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1/mute') muted = true;
      if (r.url.path.endsWith('/messages')) return _json([]);
      return _json(_huud(host: false, live: false, muted: muted));
    });
    expect(find.byKey(const ValueKey('huud-offline-member')), findsOneWidget);
    expect(find.textContaining("You'll get a notification when ada goes Live"), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-go-live')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('huud-mute')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/v1/huud-spaces/h1/mute {"muted":true}'));
    expect(find.textContaining("You've muted it"), findsOneWidget);
  });

  testWidgets('the owner can delete the Huud from settings, after saying yes', (tester) async {
    final calls = await pump(tester, const HuudSpaceScreen(id: 'h1'), (r) async {
      if (r.method == 'DELETE' && r.url.path == '/api/v1/huud-spaces/h1') return http.Response('', 204);
      return _json(_huud());
    }, settle: false);
    await tester.tap(find.byKey(const ValueKey('huud-settings')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.ensureVisible(find.byKey(const ValueKey('settings-delete')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('settings-delete')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining("You can't undo this"), findsOneWidget);
    await tester.tap(find.text('Delete forever'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(calls, contains('DELETE /api/v1/huud-spaces/h1'));
  });

  testWidgets('the People tab shows the host crown and who is here', (tester) async {
    await pump(
        tester,
        const HuudSpaceScreen(id: 'h1'),
        (r) async => _json(_huud(members: [
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
    expect(find.textContaining('tap someone to let them talk'), findsOneWidget);
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

  testWidgets('a private Huud: Ask to join, then a friendly wait', (tester) async {
    var asked = false;
    final calls = await pump(tester, const HuudSpaceScreen(id: 'h1'), (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1/join') {
        asked = true;
        return _json(_huud(host: false, inIt: false, privacy: 'private', joinRequest: 'pending'));
      }
      return _json(_huud(host: false, inIt: false, privacy: 'private', joinRequest: asked ? 'pending' : null));
    });
    expect(find.text('Ask to join'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('huud-join')));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.startsWith('POST /api/v1/huud-spaces/h1/join')), hasLength(1));
    expect(find.byKey(const ValueKey('huud-waiting')), findsOneWidget);
    expect(find.text('Waiting for the host'), findsOneWidget);
  });

  testWidgets('the host sees who is asking and answers with big Yes / No buttons', (tester) async {
    final calls = await pump(
        tester,
        const HuudSpaceScreen(id: 'h1'),
        (r) async => _json(_huud(requests: [
              {'from': _member('tobi', 'Tobi'), 'kind': 'join'},
              {'from': _member('ada', 'Ada'), 'kind': 'play'},
              {'from': _member('chidi', 'Chidi'), 'kind': 'mic'},
            ])));
    expect(find.text('✋ 3 people are asking'), findsOneWidget);
    expect(find.text('🚪 wants to come in'), findsOneWidget);
    expect(find.text('🎮 wants to play'), findsOneWidget);
    expect(find.text('🎙️ wants to talk'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('answer-play-ada-yes')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/v1/huud-spaces/h1/requests/ada/play {"accept":true}'));
    await tester.tap(find.byKey(const ValueKey('answer-join-tobi-no')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/v1/huud-spaces/h1/requests/tobi/join {"accept":false}'));
  });

  testWidgets('a member asks to play and listens until the host hands over the mic', (tester) async {
    var asked = false;
    final calls = await pump(tester, const HuudSpaceScreen(id: 'h1'), (r) async {
      if (r.url.path == '/api/v1/huud-spaces/h1/play') asked = true;
      return _json(_huud(
        host: false,
        playRequest: asked ? 'pending' : null,
        game: {'roomId': 'room1', 'code': 'AB12CD', 'gameType': 'whot', 'status': 'waiting', 'players': 1, 'seats': 4},
      ));
    });
    // In a Live Huud you're connected to its voice straight away, muted.
    expect(calls, contains('POST /api/v1/calls/rooms/huud-h1/token {}'));
    expect(find.text('Muted'), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-ask-mic')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('huud-ask-play')));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.startsWith('POST /api/v1/huud-spaces/h1/play')), hasLength(1));
    expect(find.textContaining('You asked to play'), findsOneWidget);
  });

  testWidgets('Huud chat: messages, sending, and new ones arriving live', (tester) async {
    final calls = <String>[];
    final mock = MockClient((r) async {
      calls.add('${r.method} ${r.url.path}${r.body.isEmpty ? '' : ' ${r.body}'}');
      if (r.url.path == '/api/v1/huud-spaces/h1/messages' && r.method == 'GET') {
        return _json([
          {
            'id': 1,
            'from': _member('ada', 'Ada Obi'),
            'body': 'Rematch!',
            'at': DateTime.now().toUtc().toIso8601String()
          },
        ]);
      }
      if (r.url.path == '/api/v1/huud-spaces/h1/messages') {
        return _json(
            {'id': 2, 'from': _member('me', 'Eric'), 'body': 'Yes!', 'at': DateTime.now().toUtc().toIso8601String()});
      }
      return _json(_huud());
    });
    final state = AppState(ApiClient(client: mock)..bearer = 'token')
      ..user = const UserView(id: 'me', displayName: 'Eric Barima', username: 'eric')
      ..identity = Identity.account;
    await tester.binding.setSurfaceSize(const Size(390, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        AppScope(state: state, child: MaterialApp(theme: NeonTheme.light, home: const HuudSpaceScreen(id: 'h1'))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('huud-tab-chat')));
    await tester.pumpAndSettle();
    expect(find.text('Rematch!'), findsOneWidget);
    expect(find.text('ada obi'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-time-1')), findsOneWidget);
    expect(find.text('just now'), findsWidgets);

    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'Yes!');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/v1/huud-spaces/h1/messages {"body":"Yes!"}'));
    expect(find.text('Yes!'), findsOneWidget);
  });

  testWidgets('reporting someone picks a reason and blocks them too by default', (tester) async {
    final calls = await pump(tester, Scaffold(body: Builder(builder: (context) {
      return Center(
        child: TextButton(
          onPressed: () => showSafetySheet(context, userId: 'tobi', name: 'Tobi Ade', huudSpaceId: 'h1', messageId: 7),
          child: const Text('open'),
        ),
      );
    })), (r) async => http.Response('', 200));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('safety-report')));
    await tester.pumpAndSettle();
    expect(find.text('What happened?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('safety-reason-mean')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('safety-send')));
    await tester.pumpAndSettle();
    expect(calls,
        contains('POST /api/v1/players/tobi/report {"reason":"mean","huudSpaceId":"h1","messageId":7,"block":true}'));
  });

  testWidgets('making a Huud can pick a first game and share it with a line', (tester) async {
    final calls =
        await pump(tester, const Scaffold(body: CreateHuudSheet(gameType: 'whot')), (r) async => _json(_huud()));
    expect(tester.getSemantics(find.byKey(const ValueKey('huud-first-game-whot'))), isSemantics(isSelected: true));
    await tester.tap(find.byKey(const ValueKey('huud-share-switch')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('huud-share-message')), 'Who wants to play Whot?');
    await tester.tap(find.byKey(const ValueKey('huud-create')));
    await tester.pumpAndSettle();
    expect(
        calls,
        contains('POST /api/v1/huud-spaces {"name":"Eric\'s Huud","privacy":"friends","gameType":"whot",'
            '"share":true,"message":"Who wants to play Whot?"}'));
  });

  test('the call bar says who is talking in plain words', () {
    expect(TalkingRow.said([]), '');
    expect(TalkingRow.said(['Ada']), 'Ada is talking');
    expect(TalkingRow.said(['Ada', 'Tobi']), 'Ada and Tobi are talking');
    expect(TalkingRow.said(['Ada', 'Tobi', 'Chidi', 'Zara']), 'Ada, Tobi and 2 more are talking');
  });

  testWidgets('watching: Play and People but no Chat; a game on can be watched, one waiting needs joining',
      (tester) async {
    var playing = false;
    final calls = await pump(
        tester,
        const HuudSpaceScreen(id: 'h1'),
        (r) async => _json({
              ..._huud(host: false, inIt: false, privacy: 'public'),
              'watching': 3,
              'currentGame': {
                'roomId': 'room1',
                'code': null,
                'gameType': 'whot',
                'status': playing ? 'playing' : 'waiting',
                'players': 2,
                'seats': 4,
              },
            }));
    expect(find.byKey(const ValueKey('huud-join')), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-tab-play')), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-tab-people')), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-tab-chat')), findsNothing);
    expect(find.text('3 watching'), findsOneWidget);
    expect(find.text('Join the Huud to ask to play'), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-ask-play')), findsNothing);
    expect(calls.where((c) => c.startsWith('POST /api/v1/huud-spaces/h1/watch')), isNotEmpty);

    playing = true;
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('huud-watch')), findsOneWidget);
  });

  testWidgets('after a game the host can rematch with the same players', (tester) async {
    final calls = await pump(
        tester,
        const HuudSpaceScreen(id: 'h1'),
        (r) async => r.url.path.endsWith('/game')
            ? _json({
                'id': 'room2',
                'code': 'ZZ12CD',
                'hostId': 'me',
                'status': 'lobby',
                'gameType': 'ludo',
                'stakeCoins': 0,
                'createdAt': DateTime.now().toUtc().toIso8601String(),
                'members': <dynamic>[],
                'ranked': false,
              })
            : _json(_huud(game: {
                'roomId': 'room1',
                'code': 'AB12CD',
                'gameType': 'ludo',
                'status': 'finished',
                'players': 3,
                'seats': 4,
                'playerIds': ['me', 'ada', 'chidi'],
                'youArePlaying': true,
              })));
    expect(find.text('Rematch — same players'), findsOneWidget);
    expect(find.text('Play Ludo with new players'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('huud-rematch')));
    await tester.pump();
    expect(calls, contains('POST /api/v1/huud-spaces/h1/game {"gameType":"ludo","rematch":true}'));
  });

  testWidgets('swiping: one Huud per screen, watched while on screen, swipe up for the next', (tester) async {
    LiveHuud live(String id, String name) => LiveHuud(
        id: id,
        name: name,
        privacy: HuudPrivacy.public,
        memberCount: 2,
        members: const [],
        youAreIn: false,
        host: const HuudMember(userId: 'ada', displayName: 'Ada', username: 'ada', host: true));
    final calls = await pump(
        tester,
        HuudSwipeScreen(huuds: [live('h1', 'First Huud'), live('h2', 'Second Huud')]),
        (r) async => _json({
              ..._huud(host: false, inIt: false, privacy: 'public'),
              'id': r.url.pathSegments[3],
              'name': r.url.pathSegments[3] == 'h1' ? 'First Huud' : 'Second Huud',
            }),
        settle: false);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('First Huud'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Swipe up for the next Huud'), findsOneWidget);
    expect(calls.where((c) => c.startsWith('POST /api/v1/huud-spaces/h1/watch')), isNotEmpty);

    await tester.fling(find.byKey(const ValueKey('huud-swipe')), const Offset(0, -600), 2000);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Second Huud'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(calls.where((c) => c.startsWith('POST /api/v1/huud-spaces/h2/watch')), isNotEmpty);

    await tester.tap(find.byKey(const ValueKey('swipe-enter-h2')));
    await tester.pump();
    expect(calls.where((c) => c.startsWith('POST /api/v1/huud-spaces/h2/join')), hasLength(1));
  });

  testWidgets('everyone in the Huud is listed and the host taps who plays; Cyber Agent is the only button',
      (tester) async {
    final calls = await pump(
        tester,
        const HuudSpaceScreen(id: 'h1'),
        (r) async => _json(_huud(game: {
              'roomId': 'room1',
              'code': 'AB12CD',
              'gameType': 'whot',
              'status': 'waiting',
              'players': 2,
              'seats': 4,
              'playerIds': ['me', 'ada'],
              'readyIds': ['ada'],
              'youArePlaying': true,
              'table': [
                {'userId': 'me', 'displayName': 'Eric', 'bot': false, 'ready': false},
                {'userId': 'ada', 'displayName': 'Ada Obi', 'bot': false, 'ready': true},
              ],
            })));
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text("Who's playing?"), findsOneWidget);
    expect(find.text('2 / 4 playing'), findsOneWidget);
    expect(find.text('✅ Ready'), findsOneWidget);
    expect(find.text('👑 Host'), findsOneWidget);
    expect(find.text('👀 Watching'), findsOneWidget); // Chidi
    expect(find.byKey(const ValueKey('huud-add-players')), findsNothing);
    expect(find.byKey(const ValueKey('roster-add-agent')), findsOneWidget);
    expect(find.text('Open the game to start'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('roster-chidi')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/v1/huud-spaces/h1/game/players {"userIds":["chidi"]}'));
    // No "… is playing!" banner covering Start game.
    expect(find.textContaining('is playing'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('roster-ada')));
    await tester.pumpAndSettle();
    expect(calls, contains('DELETE /api/v1/huud-spaces/h1/game/players/ada'));

    // One tap adds an agent — no picker, no "is playing" banner.
    await tester.tap(find.byKey(const ValueKey('roster-add-agent')));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.contains('/bots {"name":"Cyber 1","difficulty":"medium"}')), hasLength(1));
    expect(find.textContaining('is playing'), findsNothing);
  });

  testWidgets('the game lobby of a Huud game lists the Huud instead of a room code', (tester) async {
    await pump(
        tester,
        const JoinedRoomScreen(
            room: RoomView(id: 'room1', code: 'AB12CD', hostId: 'me', status: 'lobby', gameType: 'whot', members: [
          RoomMember(userId: 'me', nickname: 'Eric', ready: false, connected: true),
        ])),
        (r) async => r.url.path == '/api/v1/huud-spaces/by-room/room1'
            ? _json(_huud(game: {'roomId': 'room1', 'gameType': 'whot', 'status': 'waiting', 'players': 1, 'seats': 4}))
            : http.Response('', 200),
        settle: false);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('lobby-roster')), findsOneWidget);
    expect(find.text('AB12CD'), findsNothing);
    expect(find.text('👀 Watching'), findsNWidgets(2)); // Ada and Chidi
    expect(find.text('Ready up'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('a picked player is told to open the game and ready up', (tester) async {
    await pump(
        tester,
        const HuudSpaceScreen(id: 'h1'),
        (r) async => _json(_huud(host: false, game: {
              'roomId': 'room1',
              'code': 'AB12CD',
              'gameType': 'whot',
              'status': 'waiting',
              'players': 2,
              'seats': 4,
              'playerIds': ['ada', 'me'],
              'readyIds': <String>[],
              'youArePlaying': true,
              'table': [
                {'userId': 'ada', 'displayName': 'Ada', 'ready': false},
                {'userId': 'me', 'displayName': 'Eric', 'ready': false},
              ],
            })));
    expect(find.text('Open the game & ready up'), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-add-players')), findsNothing);
    expect(find.byKey(const ValueKey('unseat-ada')), findsNothing);
  });

  testWidgets('the host picks a background in settings; the Huud shows it faded behind everything', (tester) async {
    var background = 'default';
    final calls = await pump(tester, const HuudSpaceScreen(id: 'h1'), (r) async {
      if (r.method == 'PATCH') background = (jsonDecode(r.body) as Map)['background'] as String;
      return _json({..._huud(), 'background': background == 'default' ? null : background});
    });
    // Nothing picked yet: the disco floor.
    expect(find.byKey(const ValueKey('backdrop-disco')), findsOneWidget);
    expect(find.byKey(const ValueKey('backdrop-club')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('huud-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Disco'), findsOneWidget);
    for (final b in ['default', 'blank', 'lounge']) {
      expect(find.byKey(ValueKey('bg-$b')), findsOneWidget);
    }
    await tester.dragUntilVisible(
        find.byKey(const ValueKey('bg-club')), find.byKey(const ValueKey('bg-lounge')), const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bg-club')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.startsWith('PATCH /api/v1/huud-spaces/h1') && c.contains('"background":"club"')),
        hasLength(1));
    expect(find.byKey(const ValueKey('backdrop-club')), findsOneWidget);

    // Blank: no picture at all.
    await tester.tap(find.byKey(const ValueKey('huud-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bg-blank')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.contains('"background":"blank"')), hasLength(1));
    expect(find.byKey(const ValueKey('backdrop-club')), findsNothing);
    expect(find.byKey(const ValueKey('backdrop-disco')), findsNothing);
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

  test('chat times say "ago" while fresh, then the clock time', () {
    final now = DateTime(2026, 10, 9, 21, 30);
    expect(huudChatTime(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
    expect(huudChatTime(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
    expect(huudChatTime(DateTime(2026, 10, 9, 15, 42), now: now), '3:42 pm');
    expect(huudChatTime(DateTime(2026, 10, 8, 9, 5), now: now), 'Yesterday 9:05 am');
    expect(huudChatTime(DateTime(2026, 3, 12, 0, 15), now: now), '12 Mar 12:15 am');
  });

  testWidgets('a new chat message glows for everyone, and chat sits in its own scrolling box', (tester) async {
    final mock = MockClient((r) async {
      if (r.url.path.endsWith('/messages')) {
        return _json([
          for (var i = 1; i <= 12; i++)
            {'id': i, 'from': _member('ada', 'Ada'), 'body': 'Message $i', 'at': DateTime.now().toUtc().toIso8601String()},
        ]);
      }
      return _json(_huud());
    });
    final state = AppState(ApiClient(client: mock)..bearer = 'token')
      ..user = const UserView(id: 'me', displayName: 'Eric Barima', username: 'eric')
      ..identity = Identity.account;
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        AppScope(state: state, child: MaterialApp(theme: NeonTheme.light, home: const HuudSpaceScreen(id: 'h1'))));
    await tester.pump(const Duration(milliseconds: 500));

    // On the Play tab, Ada says something.
    state.debugHuudSpaceEvent({
      'type': 'HUUD_SPACE',
      'data': {
        'huudSpaceId': 'h1',
        'event': 'chat',
        'message': {'id': 13, 'from': _member('ada', 'Ada'), 'body': 'Ready?', 'at': DateTime.now().toUtc().toIso8601String()},
      },
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('huud-unread-chip')), findsOneWidget);
    expect(find.text('💬 1 new message'), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-tab-chat-unread')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('huud-unread-chip')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byKey(const ValueKey('huud-unread-chip')), findsNothing);
    final box = tester.getSize(find.byKey(const ValueKey('huud-chat-box')));
    expect(box.height, lessThanOrEqualTo(380), reason: 'a fixed box, not the whole page');
    expect(find.descendant(of: find.byKey(const ValueKey('huud-chat-box')), matching: find.byType(ListView)),
        findsOneWidget);
  });

  testWidgets("someone's card: profile, add friend (or Friends), and gift 3 coins", (tester) async {
    final calls = await pump(tester, const HuudSpaceScreen(id: 'h1'), (r) async {
      if (r.url.path == '/api/v1/friends') return _json([{'userId': 'chidi', 'displayName': 'Chidi', 'username': 'chidi'}]);
      if (r.url.path == '/api/v1/players/ada/gift') return _json({'coins': 3, 'balance': 17});
      if (r.url.path == '/api/v1/friends/requests/user/ada') return http.Response('', 201);
      return _json(_huud());
    });
    await tester.tap(find.byKey(const ValueKey('huud-tab-people')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('huud-person-chidi')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('person-profile')), findsOneWidget);
    expect(find.byKey(const ValueKey('person-friends')), findsOneWidget, reason: 'already friends');
    expect(find.byKey(const ValueKey('person-gift')), findsOneWidget);
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('huud-person-ada')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('person-gift')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/v1/players/ada/gift {}'));
    expect(find.textContaining('You gave ada 3 coins'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('huud-person-ada')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('person-add-friend')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/v1/friends/requests/user/ada {}'));
  });

  testWidgets('a gift shows a small splash in the corner that never blocks taps', (tester) async {
    final gifts = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(gifts.close);
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: GiftSplashHost(
        gifts: gifts.stream,
        child: Scaffold(body: SizedBox.expand(child: TextButton(onPressed: () => tapped++, child: const Text('board')))),
      ),
    ));
    gifts.add({'fromName': 'eric', 'coins': 3});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('eric sent you 3 coins!'), findsOneWidget);
    // Tapping right where the splash is still reaches the game underneath.
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('gift-splash'))));
    expect(tapped, 1);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('the mic: muted is a red crossed-out mic, talking is a bold green one', (tester) async {
    Future<void> show(bool talking) => tester.pumpWidget(MaterialApp(
        theme: NeonTheme.light,
        home: Scaffold(body: Center(child: HuudMicButton(talking: talking, label: talking ? 'Talking' : 'Muted', onTap: () {})))));
    await show(false);
    expect(tester.widget<Icon>(find.byKey(const ValueKey('mic-off'))).color, HuudMicButton.mutedRed);
    await show(true);
    expect(tester.widget<Icon>(find.byKey(const ValueKey('mic-on'))).color, Colors.white);
    final circle = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    expect((circle.decoration as BoxDecoration).color, HuudMicButton.talkingGreen);
  });
}
