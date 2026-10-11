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
import 'package:truearena/core/models.dart';
import 'package:truearena/features/huudspace/huud_voice.dart';
import 'package:truearena/features/monopoly/monopoly_game_screen.dart';
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
    expect(find.text('MONOPOLY · PAUSED'), findsOneWidget);
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
