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
import 'package:truearena/features/draughts/draughts_game_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

class _Socket implements GameSocket {
  final frames = StreamController<Map<String, dynamic>>.broadcast();

  @override
  final ValueNotifier<Set<String>> onlinePlayers = ValueNotifier(<String>{});

  @override
  Stream<Map<String, dynamic>> get envelopes => frames.stream;

  @override
  bool get isConnected => true;

  @override
  int get lastSeq => 0;

  @override
  String get roomId => '00000000-0000-0000-0000-000000000001';

  @override
  void send(String type, [Map<String, dynamic>? payload]) {}

  @override
  Future<void> close() => frames.close();

  void snapshot(Map<String, dynamic> payload) {
    frames.add({'type': 'SNAPSHOT', 'payload': payload});
  }

  void event(String type, Map<String, dynamic> data) {
    frames.add({
      'type': 'EVENT',
      'payload': {'type': type, 'data': data},
    });
  }
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('opponent VAR move visibly replays and can restart',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    final socket = _Socket();
    final board = List<String?>.filled(50, null)..[30] = 'B_MAN';

    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient(
        client: MockClient((_) async => http.Response('{}', 200)),
      )),
      child: MaterialApp(
        theme: NeonTheme.dark,
        home: DraughtsGameScreen(
          socket: socket,
          selfId: 'me',
          nicknames: const {'me': 'You', 'opponent': 'Ada'},
        ),
      ),
    ));
    socket.snapshot({
      'phase': 'TurnB',
      'round': 1,
      'playerA': 'me',
      'playerB': 'opponent',
      'board': board,
      'turnSeconds': 60,
    });
    await tester.pump();

    socket.event('PIECE_MOVED', {
      'side': 'B',
      'from': 30,
      'to': 25,
    });
    await tester.pump();
    socket.event('TURN_STARTED', {'side': 'A'});
    await tester.pump();

    final varButton = find.byKey(const Key('draughts-var-tv'));
    expect(varButton, findsOneWidget);
    expect(tester.widget<TextButton>(varButton).onPressed, isNotNull);
    expect(
        find.descendant(of: varButton, matching: find.byIcon(Icons.tv_rounded)),
        findsOneWidget);
    expect(find.descendant(of: varButton, matching: find.text('VAR')),
        findsOneWidget);

    await tester.ensureVisible(varButton);
    await tester.pump();
    await tester.tap(varButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('draughts-var-sheet')), findsOneWidget);

    final replayPiece = find.byKey(const ValueKey('var-30'));
    expect(replayPiece, findsOneWidget);
    final start = tester.getTopLeft(replayPiece);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 210));
    final duringMove = tester.getTopLeft(replayPiece);
    expect(duringMove, isNot(start));

    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.byTooltip('Replay from start'));
    await tester.pump();
    final restarted = tester.getTopLeft(replayPiece);
    expect(restarted, start);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 210));
    expect(tester.getTopLeft(replayPiece), isNot(start));
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
}
