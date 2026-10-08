import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/game_socket.dart';
import 'package:truearena/features/game/game_screen.dart';
import 'package:truearena/features/wordbluff/wordbluff_game_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

class _Socket implements GameSocket {
  @override
  final memberAvatars = <String, String?>{};
  final frames = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <String>[];
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
  void send(String type, [Map<String, dynamic>? payload]) => sent.add(type);
  @override
  Future<void> close() => frames.close();
  void snapshot(Map<String, dynamic> payload) =>
      frames.add({'type': 'SNAPSHOT', 'payload': payload});
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> open(WidgetTester tester, Widget child, _Socket socket,
      Map<String, dynamic> snapshot) async {
    await tester.pumpWidget(AppScope(
      state: AppState(
          ApiClient(client: MockClient((_) async => http.Response('[]', 200)))),
      child: MaterialApp(theme: NeonTheme.dark, home: child),
    ));
    socket.snapshot(snapshot);
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  for (final size in [const Size(320, 568), const Size(280, 480), const Size(240, 480)]) {
    testWidgets('Traitors fits $size in vote and round table', (tester) async {
      await tester.binding.setSurfaceSize(size);
      final socket = _Socket();
      await open(
          tester,
          GameScreen(
              socket: socket, selfId: 'p1', isHost: true, nicknames: const {}),
          socket,
          {
            'phase': 'Vote',
            'round': 1,
            'players': ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'],
            'alive': ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'],
            'yourRole': 'faithful',
          });
      socket.snapshot({
        'phase': 'RoleReveal', 'round': 1,
        'players': ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'],
        'alive': ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'],
        'yourRole': 'traitor', 'fellowTraitors': ['p2'],
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      socket.snapshot({
        'phase': 'Night', 'round': 1,
        'players': ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'],
        'alive': ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'],
        'yourRole': 'traitor', 'fellowTraitors': ['p2'],
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      socket.snapshot({
        'phase': 'RoundTable',
        'round': 1,
        'players': ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'],
        'alive': ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'],
        'yourRole': 'faithful',
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Round table chat'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      socket.snapshot({
        'phase': 'Results',
        'round': 2,
        'players': ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'],
        'alive': ['p1', 'p2'],
        'winningSide': 'faithful',
        'allRoles': {
          'p1': 'faithful',
          'p2': 'faithful',
          'p3': 'traitor',
          'p4': 'faithful',
          'p5': 'traitor',
          'p6': 'faithful'
        },
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('Word Bluff fits $size in turn and review', (tester) async {
      await tester.binding.setSurfaceSize(size);
      final socket = _Socket();
      await open(
          tester,
          WordBluffGameScreen(
              socket: socket, selfId: 'p1', isHost: false, nicknames: const {}),
          socket,
          {
            'phase': 'Turn',
            'round': 1,
            'teamA': ['p1', 'p2'],
            'teamB': ['p3', 'p4'],
            'turnTeam': 'A',
            'describer': 'p1',
            'hasActiveCategory': false,
            'hasActiveWord': false,
            'targetScore': 30,
            'turnSeconds': 60,
          });
      socket.snapshot({
        'phase': 'Review',
        'round': 1,
        'teamA': ['p1', 'p2'],
        'teamB': ['p3', 'p4'],
        'turnTeam': 'A',
        'describer': 'p1',
        'attempts': [
          {'word': 'giraffe', 'correct': true, 'skipped': false}
        ],
        'targetScore': 30,
        'turnSeconds': 60,
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      socket.snapshot({
        'phase': 'Turn',
        'round': 2,
        'teamA': ['p1', 'p2'],
        'teamB': ['p3', 'p4'],
        'turnTeam': 'B',
        'describer': 'p3',
        'hasActiveCategory': true,
        'category': 'animals',
        'hasActiveWord': true,
        'yourWord': 'giraffe',
        'targetScore': 30,
        'turnSeconds': 60,
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      socket.snapshot({
        'phase': 'Results',
        'round': 2,
        'teamA': ['p1', 'p2'],
        'teamB': ['p3', 'p4'],
        'turnTeam': 'B',
        'describer': 'p3',
        'winningTeam': 'B',
        'targetScore': 30,
        'turnSeconds': 60,
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    });
  }

  testWidgets('Word Bluff spectator sees review without team controls',
      (tester) async {
    final socket = _Socket();
    await open(
        tester,
        WordBluffGameScreen(
            socket: socket,
            selfId: 'viewer',
            isHost: false,
            nicknames: const {},
            spectating: true),
        socket,
        {
          'phase': 'Review',
          'round': 1,
          'teamA': ['p1', 'p2'],
          'teamB': ['p3', 'p4'],
          'turnTeam': 'A',
          'describer': 'p1',
          'attempts': [
            {'word': 'giraffe', 'correct': true, 'skipped': false}
          ],
          'targetScore': 30,
          'turnSeconds': 60,
        });

    expect(find.text('The teams are reviewing this round.'), findsOneWidget);
    expect(find.textContaining('Accept 1 point'), findsNothing);
    await tester.tap(find.text('giraffe'));
    expect(socket.sent, isNot(contains('PLAYER_ACTION')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
