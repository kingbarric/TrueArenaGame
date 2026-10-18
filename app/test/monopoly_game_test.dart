import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/hangout_state.dart';
import 'package:truearena/core/game_music.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/huudspace/huud_voice.dart';
import 'package:truearena/features/monopoly/monopoly_game_screen.dart';
import 'package:truearena/features/lobby/joined_room_screen.dart';
import 'package:truearena/features/monopoly/monopoly_board.dart';
import 'whot_game_test.dart' show TestSocket;

class _Socket extends TestSocket {
  bool connected = true;
  @override
  bool get isConnected => connected;
  void frame(String type, Map<String, dynamic> payload) =>
      controller.add({'type': type, 'payload': payload});
}

Map<String, dynamic> _board() =>
    (jsonDecode(File('test/fixtures/monopoly.json').readAsStringSync()) as Map)
        .cast<String, dynamic>();
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    HangoutState.instance.clear();
    HuudVoice.instance.reset();
  });
  Future<void> open(WidgetTester tester, _Socket socket,
      {http.Response Function(http.Request)? route}) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = ApiClient(
        client: MockClient((request) async =>
            route?.call(request) ?? http.Response('offline', 503)))
      ..bearer = 'token';
    final app = AppState(api)
      ..user = const UserView(id: 'ada', displayName: 'Ada', username: 'ada')
      ..identity = Identity.account;
    await tester.pumpWidget(AppScope(
        state: app,
        child: MaterialApp(
            theme: ThemeData(fontFamily: 'MonopolySans', extensions: const [
              NeonColors.dark,
              NeonDesign(NeonDesignKind.cabinet)
            ]),
            home: MonopolyGameScreen(
                socket: socket,
                selfId: 'ada',
                nicknames: const {'ada': 'Ada', 'eric': 'Eric'},
                roomCode: 'ABCDEF'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });
  }

  testWidgets('reopening waits for the server and repairs an interrupted match into setup',
      (tester) async {
    final socket = _Socket();
    final app = AppState(ApiClient(client: MockClient((_) async => http.Response('offline', 503))))
      ..user = const UserView(id: 'ada', displayName: 'Ada', username: 'ada')
      ..identity = Identity.account;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(AppScope(state: app, child: MaterialApp(
      navigatorKey: navigator,
      theme: ThemeData(fontFamily: 'MonopolySans', extensions: const [
        NeonColors.dark, NeonDesign(NeonDesignKind.cabinet)]),
      home: const Scaffold(body: Text('Home')))));
    navigator.currentState!.push(MaterialPageRoute(builder: (_) => JoinedRoomScreen(
      socket: socket,
      room: RoomView(id: socket.roomId, code: 'ABCDEF', hostId: 'ada',
        status: 'in_game', gameType: 'monopoly', members: const []))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    socket.frame('CONNECTION', {'connected': true});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(JoinedRoomScreen), findsOneWidget);
    expect(find.byType(MonopolyGameScreen), findsNothing);
    socket.frame('SNAPSHOT', {'lobby': true, 'roomId': socket.roomId,
      'code': 'ABCDEF', 'hostId': 'ada', 'status': 'lobby',
      'members': [
        {'userId': 'eric', 'nickname': 'Eric', 'ready': true},
        {'userId': 'chidi', 'nickname': 'Chidi', 'ready': true}
      ]});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The organising host remains even without a selected game seat.
    expect(find.byType(JoinedRoomScreen), findsOneWidget);
    expect(find.byType(MonopolyGameScreen), findsNothing);
    expect(find.textContaining('The host changed the players'), findsNothing);
    expect(find.textContaining('Error has occurred'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('music starts with the live match and can still be muted',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ta_music_enabled': false});
    await GameMusic.load();
    expect(GameMusic.enabled, isFalse);
    final socket = _Socket();
    await open(tester, socket);
    expect(GameMusic.enabled, isFalse);
    socket.frame('SNAPSHOT', _board());
    await tester.pumpAndSettle();
    expect(GameMusic.enabled, isTrue);
    await tester.tap(find.byTooltip('Game settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute music'));
    await tester.pumpAndSettle();
    expect(GameMusic.enabled, isFalse);
  });

  testWidgets('Quit Game requires confirmation and can forfeit a paused match',
      (tester) async {
    final socket = _Socket();
    await open(tester, socket);
    socket.frame('SNAPSHOT', _board()..['paused'] = true);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Game settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('monopoly-quit-game')));
    await tester.pumpAndSettle();
    expect(find.text('Quit this match?'), findsOneWidget);
    await tester.tap(find.text('Keep playing'));
    await tester.pumpAndSettle();
    expect(socket.sent.where((e) => e['type'] == 'PLAYER_ACTION'), isEmpty);
    await tester.tap(find.byTooltip('Game settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('monopoly-quit-game')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Quit Game'));
    await tester.pump();
    final actions =
        socket.sent.where((e) => e['type'] == 'PLAYER_ACTION').toList();
    expect(actions, hasLength(1));
    expect(actions.single['action'], 'FORFEIT');
    socket.frame('ERROR', {'message': 'Error has occurred, try again later.'});
    await tester.pumpAndSettle();
  });

  testWidgets(
      'offline reopening restores the saved board without enabling moves',
      (tester) async {
    final socket = _Socket()..connected = false;
    SharedPreferences.setMockInitialValues({
      'monopoly_snapshot_ada_${socket.roomId}': jsonEncode({
        'state': _board(),
        'huudName': "Eric's Huud",
        'messages': [
          {'who': 'Eric', 'text': 'Saved conversation'}
        ]
      })
    });
    await open(tester, socket);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(MonopolyBoard), findsOneWidget);
    expect(find.text('OFFLINE • saved board'), findsOneWidget);
    expect(find.text('Saved conversation'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Buy \$240'))
            .onPressed,
        isNull);
    expect(socket.sent.where((f) => f['type'] == 'PLAYER_ACTION'), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Huud metadata failure cannot redirect messages into room chat',
      (tester) async {
    final socket = _Socket();
    await open(tester, socket);
    socket.frame('SNAPSHOT', _board());
    await tester.pump();
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pump();
    expect(find.byKey(const Key('monopoly-chat-input')), findsNothing);
    expect(find.text('Join the Huud to chat'), findsOneWidget);
    expect(socket.sent.where((f) => f['type'] == 'CHAT_SEND'), isEmpty);
  });

  testWidgets(
      'Huud chat uses persistent Huud messages and pending trades never enter the cache',
      (tester) async {
    final socket = _Socket(), posts = <http.Request>[];
    final messages = <Map<String, dynamic>>[
      {
        'from': {'username': 'eric'},
        'body': 'Keep this chat'
      }
    ];
    await open(tester, socket, route: (r) {
      if (r.url.path.endsWith('/messages')) {
        if (r.method == 'POST') {
          posts.add(r);
          messages.add({
            'from': {'username': 'ada'},
            'body': jsonDecode(r.body)['body']
          });
          return http.Response(jsonEncode(messages.last), 200);
        }
        return http.Response(jsonEncode(messages), 200);
      }
      return http.Response(
          jsonEncode({
            'id': 'h1',
            'name': "Eric's Huud",
            'youAreIn': true,
            'status': 'active',
            'privacy': 'public',
            'members': [],
            'voiceRoom': 'huud-h1'
          }),
          200);
    });
    socket.frame(
        'SNAPSHOT',
        _board()
          ..['legalActions'] = [
            {
              'action': 'ACCEPT_TRADE',
              'data': {'tradeId': 'private-offer'}
            }
          ]
          ..['tradeOffers'] = [
            {
              'id': 'private-offer',
              'from': 'eric',
              'to': 'ada',
              'giveCash': 10,
              'takeCash': 0,
              'giveDeeds': [],
              'takeDeeds': []
            }
          ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Keep this chat'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pump();
    await tester.enterText(
        find.byKey(const Key('monopoly-chat-input')), 'My next turn');
    await tester.tap(find.byTooltip('Send to Huud chat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(posts.single.url.path, '/api/v1/huud-spaces/h1/messages');
    expect(jsonDecode(posts.single.body), {'body': 'My next turn'});
    expect(socket.sent.where((f) => f['type'] == 'CHAT_SEND'), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('monopoly_snapshot_ada_${socket.roomId}')!;
    expect(stored, contains('My next turn'));
    expect(stored, isNot(contains('private-offer')));
    expect(stored, isNot(contains('legalActions')));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'the raised Properties control on the board opens property management',
      (tester) async {
    final socket = _Socket();
    await open(tester, socket);
    socket.frame('SNAPSHOT', _board());
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('monopoly-board-properties')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('PROPERTIES & BUILDINGS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('shared pause control freezes moves and accepts resume events',
      (tester) async {
    final socket = _Socket();
    await open(tester, socket);
    socket.frame('SNAPSHOT', _board());
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('Pause game'));
    expect(socket.sent.last['type'], 'PAUSE_TOGGLE');
    socket.frame('EVENT', {
      'type': 'GAME_PAUSED',
      'data': {'secondsLeft': 99}
    });
    await tester.pump();
    await tester.pump();
    expect(find.text('HUUDPOLY · PAUSED'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Buy \$240'))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('Resume game'));
    expect(socket.sent.last['type'], 'PAUSE_TOGGLE');
    socket.frame('EVENT', {
      'type': 'GAME_RESUMED',
      'data': {'secondsLeft': 99}
    });
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Pause game'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Buy \$240'))
            .onPressed,
        isNotNull);
  });
  testWidgets(
      'a replayed snapshot during an outage stays read-only until a live snapshot arrives',
      (tester) async {
    final socket = _Socket();
    await open(tester, socket);
    socket.frame('SNAPSHOT', _board());
    await tester.pump();
    socket.connected = false;
    socket.frame('CONNECTION', {'connected': false});
    socket.frame('SNAPSHOT', _board());
    await tester.pump();
    expect(find.byType(MonopolyBoard), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Buy \$240'))
            .onPressed,
        isNull);
    socket.connected = true;
    socket.frame('CONNECTION', {'connected': true});
    socket.frame('SNAPSHOT', _board());
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Buy \$240'))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });
}
