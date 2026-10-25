import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/hangout_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/core/table_minimum.dart';
import 'package:truearena/features/huudspace/huud_start_check.dart';
import 'package:truearena/features/huudspace/huud_voice.dart';
import 'package:truearena/features/lobby/joined_room_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

import 'whot_game_test.dart' show TestSocket;

class _Socket extends TestSocket {
  void frame(String type, Map<String, dynamic> payload) => controller.add({'type': type, 'payload': payload});

  void lobby(List<String> players, {int minPlayers = 2, String? mode}) => frame('SNAPSHOT', {
        'lobby': true,
        'roomId': roomId,
        'code': 'ABCDEF',
        'hostId': 'me',
        'status': 'lobby',
        'minPlayers': minPlayers,
        if (mode != null) 'mode': mode,
        'members': [for (final id in players) {'userId': id, 'nickname': id, 'ready': false}],
      });

  bool get started => sent.any((f) => f['type'] == 'GAME_START');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    HangoutState.instance.clear();
    HuudVoice.instance.reset();
  });

  test('a short table is told how many to add — players or Cyber Agents', () {
    expect(tableStartProblem('Draughts', 2, 2), isNull);
    expect(tableStartProblem('Draughts', 1, 2), 'Add a player or a Cyber Agent to start Draughts.');
    expect(tableStartProblem('Draughts', 0, 2),
        'Draughts needs at least 2 players. Add 2 more — players or Cyber Agents.');
    expect(huudStartProblem('truearena', 'blood_moon', 3, 8),
        'Traitors · Blood Moon needs at least 8 players. Add 5 more — players or Cyber Agents.');
    expect(huudStartProblem('wordbluff', null, 3, 4), 'Add a player or a Cyber Agent to start Word Bluff.');
    // The Tell: enough people, but the teams have to pair up too.
    expect(huudStartProblem('whot', 'tell', 5, 4), isNotNull);
    expect(huudStartProblem('whot', 'tell', 6, 4), isNull);
    expect(huudStartProblem('whot', null, 2, 2), isNull);
  });

  test('without the server\'s figure, each game falls back to its own minimum', () {
    expect(defaultMinPlayers('draughts'), 2);
    expect(defaultMinPlayers('wordbluff'), 4);
    expect(defaultMinPlayers('whot', mode: 'tell'), 4);
    expect(defaultMinPlayers('truearena'), 6);
  });

  Future<_Socket> open(WidgetTester tester, {String gameType = 'draughts'}) async {
    final socket = _Socket();
    final app = AppState(ApiClient(client: MockClient((_) async => http.Response('offline', 503))))
      ..user = const UserView(id: 'me', displayName: 'Eric', username: 'eric')
      ..identity = Identity.account;
    addTearDown(app.dispose);
    await tester.pumpWidget(AppScope(
        state: app,
        child: MaterialApp(
            theme: ThemeData(extensions: const [NeonColors.dark, NeonDesign(NeonDesignKind.cabinet)]),
            home: JoinedRoomScreen(
                socket: socket,
                huudId: 'h1',
                startGame: true,
                room: RoomView(
                    id: socket.roomId, code: 'ABCDEF', hostId: 'me', status: 'lobby', gameType: gameType, members: const [])))));
    await tester.pump();
    return socket;
  }

  testWidgets('Start with nobody else at the table asks for a player or an agent, and never asks the server',
      (tester) async {
    final socket = await open(tester);
    socket.lobby(['me']);
    await tester.pump();
    expect(socket.started, isFalse);
    expect(find.text('Add a player or a Cyber Agent to start Draughts.'), findsOneWidget);
    expect(find.textContaining('another go'), findsNothing);

    // Try again checks a fresh roster: with an opponent seated, it starts.
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(socket.sent.last['type'], 'HELLO');
    expect(socket.started, isFalse);
    socket.lobby(['me', 'agent-1']);
    await tester.pump();
    expect(socket.started, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('someone leaving just as Start goes: the refusal says who to add', (tester) async {
    final socket = await open(tester);
    socket.lobby(['me', 'ada']);
    await tester.pump();
    expect(socket.started, isTrue);
    // Ada left before the server dealt: it turns Start down for the table's size.
    socket.lobby(['me']);
    socket.frame('ERROR', {'code': 'NEEDS_TWO_PLAYERS', 'message': tableTooSmallMessage});
    await tester.pump();
    expect(find.text('Add a player or a Cyber Agent to start Draughts.'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('The Tell validates complete teams from the lobby mode before Huud data loads', (tester) async {
    final socket = await open(tester, gameType: 'whot');
    socket.lobby(['me', 'a', 'b', 'c', 'd'], minPlayers: 4, mode: 'tell');
    await tester.pump();
    expect(socket.started, isFalse);
    expect(find.textContaining('4, 6 or 8'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    socket.lobby(['me', 'a', 'b', 'c', 'd', 'e'], minPlayers: 4, mode: 'tell');
    await tester.pump();
    expect(socket.started, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  test('SlayHuud requires contestants and, when applicable, judges', () {
    expect(slayStartProblem('battle', 1, 0), isNotNull);
    expect(slayStartProblem('battle', 2, 0), isNull);
    expect(slayStartProblem('group', 3, 0), isNotNull);
    expect(slayStartProblem('group', 4, 0), isNull);
    expect(slayStartProblem('slay_or_pass', 3, 2), isNotNull);
    expect(slayStartProblem('slay_or_pass', 2, 3), isNotNull);
    expect(slayStartProblem('slay_or_pass', 3, 3), isNull);
  });

}
