import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/game_socket.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/draughts/draughts_game_screen.dart';
import 'package:truearena/features/lobby/joined_room_screen.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/neon.dart' show Presence;

class _Socket implements GameSocket {
  final frames = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final sent = <Map<String, dynamic>>[];
  Map<String, dynamic>? latest;
  @override
  final onlinePlayers = ValueNotifier(<String>{'me', 'opponent'});
  @override
  final awaySince = <String, DateTime>{};
  @override
  final memberAvatars = <String, String?>{};
  @override
  Presence presenceOf(String id) => Presence.here;
  @override
  bool get isConnected => true;
  @override
  int get lastSeq => 0;
  @override
  String get roomId => 'room';
  @override
  Stream<Map<String, dynamic>> get envelopes => Stream.multi((listener) {
        final sub = frames.stream.listen(listener.add);
        if (latest != null) listener.add(latest!);
        listener.onCancel = sub.cancel;
      }, isBroadcast: true);
  void emit(String type, Map<String, dynamic> payload) {
    final frame = {'type': type, 'payload': payload};
    if (type == 'SNAPSHOT' && payload['lobby'] == false) latest = frame;
    frames.add(frame);
  }
  @override
  void send(String type, [Map<String, dynamic>? payload]) =>
      sent.add({'type': type, 'payload': payload});
  @override
  Future<void> close() => frames.close();
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<(_Socket, AppState)> open(WidgetTester tester, {bool huud = false, bool start = false}) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final socket = _Socket();
    final app = AppState(ApiClient(client: MockClient((_) async =>
        http.Response('{}', 404))));
    app.user = const UserView(id: 'me', displayName: 'Player');
    await tester.pumpWidget(AppScope(state: app, child: MaterialApp(
      theme: NeonTheme.dark,
      home: const Scaffold(body: Text('Your Huud')),
      routes: {'/resume': (_) => JoinedRoomScreen(
        socket: socket, huudId: huud ? 'h1' : null, startGame: start,
        room: const RoomView(id: 'room', code: 'ABCDEF', hostId: 'me',
          status: 'in_game', gameType: 'draughts', members: [
            RoomMember(userId: 'me', nickname: 'Player', ready: true, connected: true),
            RoomMember(userId: 'opponent', nickname: 'Cyber 1', ready: true, connected: true),
          ]),
      )},
    )));
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/resume');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    return (socket, app);
  }

  testWidgets('connection and phase wait for the authoritative board', (tester) async {
    final (socket, app) = await open(tester);
    socket.emit('CONNECTION', {'connected': true});
    socket.emit('PHASE', {'phase': 'TurnA', 'round': 1});
    await tester.pump();
    expect(find.byType(JoinedRoomScreen), findsOneWidget);
    expect(find.byType(DraughtsGameScreen), findsNothing);
    expect(socket.sent.last, {'type': 'HELLO', 'payload': {'lastSeq': 0}});
    socket.emit('SNAPSHOT', {
      'lobby': false, 'phase': 'TurnA', 'round': 1,
      'playerA': 'me', 'playerB': 'opponent',
      'board': List<String?>.generate(100, (i) => i == 10 ? 'A_MAN' : null),
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(DraughtsGameScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(JoinedRoomScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('lost server state offers retry and exit instead of an empty board', (tester) async {
    final (socket, app) = await open(tester);
    socket.emit('CONNECTION', {'connected': true});
    socket.emit('SNAPSHOT', {
      'lobby': true, 'roomId': 'room', 'code': 'ABCDEF', 'hostId': 'me',
      'status': 'in_game', 'members': [{'userId': 'me', 'nickname': 'Player'}],
    });
    await tester.pump();
    expect(find.text('This game is unavailable'), findsOneWidget);
    expect(find.byType(DraughtsGameScreen), findsNothing);
    final before = socket.sent.length;
    await tester.tap(find.text('Try again'));
    expect(socket.sent.length, before + 1);
    expect(socket.sent.last, {'type': 'HELLO', 'payload': {'lastSeq': 0}});
    await tester.tap(find.text('Back to Huud'));
    await tester.pumpAndSettle();
    expect(find.text('Your Huud'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('Huud host starts once from the current setup and can retry a rejected start', (tester) async {
    final (socket, app) = await open(tester, huud: true, start: true);
    final lobby = <String, dynamic>{
      'lobby': true, 'roomId': 'room', 'code': 'ABCDEF', 'hostId': 'me',
      'status': 'lobby', 'members': [{'userId': 'me', 'nickname': 'Player'}],
    };
    socket.emit('SNAPSHOT', lobby);
    socket.emit('SNAPSHOT', lobby);
    await tester.pump();
    expect(socket.sent.where((e) => e['type'] == 'GAME_START'), hasLength(1));
    expect(find.text('Starting the game…'), findsOneWidget);
    expect(find.byKey(const ValueKey('lobby-roster')), findsNothing);
    expect(find.byKey(const ValueKey('lobby-start')), findsNothing);
    socket.emit('ERROR', {'message': 'Add another player to start'});
    await tester.pump();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(socket.sent.where((e) => e['type'] == 'GAME_START'), hasLength(2));
    expect(find.text('Starting the game…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('a Huud participant waits without starting or seeing the old room lobby', (tester) async {
    final (socket, app) = await open(tester, huud: true);
    socket.emit('SNAPSHOT', {
      'lobby': true, 'roomId': 'room', 'code': 'ABCDEF', 'hostId': 'opponent',
      'status': 'lobby', 'members': [{'userId': 'me', 'nickname': 'Player'}],
    });
    await tester.pump();
    expect(find.text('Waiting for the host to start'), findsOneWidget);
    expect(find.text('Back to the Huud'), findsOneWidget);
    expect(socket.sent.where((e) => e['type'] == 'GAME_START'), isEmpty);
    expect(find.byKey(const ValueKey('lobby-roster')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    await tester.binding.setSurfaceSize(null);
  });

}
