import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/game_socket.dart';
import 'package:truearena/features/ludo/ludo_game_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

class _Socket implements GameSocket {
  @override
  final memberAvatars = <String, String?>{};
  final frames = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final sent = <Map<String, dynamic>>[];
  @override
  final ValueNotifier<Set<String>> onlinePlayers = ValueNotifier({});
  @override
  Stream<Map<String, dynamic>> get envelopes => frames.stream;
  @override
  bool get isConnected => true;
  @override
  int get lastSeq => 0;
  @override
  String get roomId => '00000000-0000-0000-0000-000000000001';
  @override
  void send(String type, [Map<String, dynamic>? payload]) =>
      sent.add({'type': type, ...?payload});
  @override
  Future<void> close() => frames.close();

  void snapshot(
      {required List<String> players,
      required List<int> seats,
      required Map<String, List<int>> pieces,
      List<int> dice = const [],
      List<int>? rolledDice,
      String? rollPlayer,
      bool paused = false,
      List<Map<String, int>> legal = const [],
      int pieceCount = 4,
      String turn = 'me'}) {
    frames.add({
      'type': 'SNAPSHOT',
      'payload': {
        'lobby': false,
        'phase': 'Turn',
        'players': players,
        'seats': seats,
        'pieces': pieces,
        'pieceCount': pieceCount,
        'turnPlayer': turn,
        'dice': dice,
        'rolledDice': rolledDice ?? const [],
        if (rollPlayer != null) 'rollPlayer': rollPlayer,
        'paused': paused,
        'legalMoves': legal,
        'secondsLeft': 42,
      }
    });
  }
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<_Socket> open(WidgetTester tester,
      {Size size = const Size(390, 844)}) async {
    await tester.binding.setSurfaceSize(size);
    final socket = _Socket();
    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient()),
      child: MaterialApp(
          theme: NeonTheme.dark,
          home: LudoGameScreen(
              socket: socket,
              selfId: 'me',
              roomCode: '7K3M',
              nicknames: const {
                'me': 'You',
                'friend': 'Ama',
                'third': 'Kofi',
                'fourth': 'Zara'
              },
              agents: const {
                'third'
              })),
    ));
    await tester.pump();
    return socket;
  }

  testWidgets('tapping the huud code copies it and confirms', (tester) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('copy-huud-code-7K3M')));
    await tester.pump();

    expect(copiedText, '7K3M');
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('two dice can move two different pieces in sequence',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot(players: [
      'me',
      'friend'
    ], seats: [
      0,
      2
    ], pieces: {
      'me': [0, 5, -1, -1],
      'friend': [-1, -1, -1, -1],
    }, dice: [
      2,
      3
    ], legal: [
      {'die': 2, 'token': 0},
      {'die': 3, 'token': 1},
    ]);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('me:0')));
    expect(socket.sent.last['action'], 'MOVE');
    expect(socket.sent.last['data'], {'die': 2, 'token': 0});

    socket.snapshot(players: [
      'me',
      'friend'
    ], seats: [
      0,
      2
    ], pieces: {
      'me': [2, 5, -1, -1],
      'friend': [-1, -1, -1, -1],
    }, dice: [
      3
    ], legal: [
      {'die': 3, 'token': 1}
    ]);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('me:1')));
    expect(socket.sent.last['data'], {'die': 3, 'token': 1});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('both dice may be spent on the same piece', (tester) async {
    final socket = await open(tester);
    socket.snapshot(players: [
      'me',
      'friend'
    ], seats: [
      0,
      2
    ], pieces: {
      'me': [0, -1, -1, -1],
      'friend': [-1, -1, -1, -1],
    }, dice: [
      2,
      3
    ], legal: [
      {'die': 2, 'token': 0},
      {'die': 3, 'token': 0},
    ]);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('me:0')));
    socket.snapshot(players: [
      'me',
      'friend'
    ], seats: [
      0,
      2
    ], pieces: {
      'me': [2, -1, -1, -1],
      'friend': [-1, -1, -1, -1],
    }, dice: [
      3
    ], legal: [
      {'die': 3, 'token': 0}
    ]);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('me:0')));
    expect(socket.sent.last['data'], {'die': 3, 'token': 0});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cup spins while held and rolls when released', (tester) async {
    final socket = await open(tester);
    socket.snapshot(players: [
      'me',
      'friend'
    ], seats: [
      0,
      2
    ], pieces: {
      'me': [-1, -1, -1, -1],
      'friend': [-1, -1, -1, -1],
    });
    await tester.pump();
    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('ludo-dice-cup'))));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('RELEASE'), findsOneWidget);
    expect(
        socket.sent.where((message) => message['action'] == 'ROLL'), isEmpty);
    await gesture.up();
    await tester.pump();
    expect(socket.sent.last['action'], 'ROLL');
    expect(socket.sent.last['data'], isEmpty);
    socket.snapshot(players: [
      'me',
      'friend'
    ], seats: [
      0,
      2
    ], pieces: {
      'me': [-1, -1, -1, -1],
      'friend': [-1, -1, -1, -1],
    }, turn: 'friend');
    socket.frames.add({
      'type': 'EVENT',
      'payload': {
        'type': 'DICE_ROLLED',
        'data': {
          'player': 'me',
          'dice': [2, 3]
        }
      }
    });
    await tester.pump();
    expect(find.text('NO MOVE'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('eight pieces and You label fit a two-player board',
      (tester) async {
    final socket = await open(tester, size: const Size(320, 568));
    socket.snapshot(
        players: ['me', 'friend'],
        seats: [0, 2],
        pieces: {
          'me': List.filled(8, -1),
          'friend': List.filled(8, -1),
        },
        pieceCount: 8,
        dice: [6, 2],
        legal: [
          {'die': 6, 'token': 7}
        ]);
    await tester.pump();
    expect(find.text('You'), findsOneWidget);
    expect(find.byKey(const ValueKey('me:7')), findsOneWidget);
    expect(find.byKey(const ValueKey('friend:7')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('me:7')));
    expect(socket.sent.last['data'], {'die': 6, 'token': 7});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('finished opponents occupy separate colored center wedges',
      (tester) async {
    final socket = await open(tester, size: const Size(320, 568));
    socket.snapshot(players: [
      'me',
      'friend'
    ], seats: [
      0,
      2
    ], pieces: {
      'me': [56, 56, -1, -1],
      'friend': [56, -1, -1, -1],
    });
    await tester.pumpAndSettle();

    final mine = tester.getCenter(find.byKey(const ValueKey('me:0')));
    final mineSecond = tester.getCenter(find.byKey(const ValueKey('me:1')));
    final opponent = tester.getCenter(find.byKey(const ValueKey('friend:0')));
    expect(mine, isNot(mineSecond));
    expect(mine, isNot(opponent));
    expect(mine.dy, lessThan(opponent.dy));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opponent dice remain visible and fade until the turn ends',
      (tester) async {
    final socket = await open(tester, size: const Size(320, 568));
    final pieces = {
      'me': [-1, -1, -1, -1],
      'friend': [0, -1, -1, -1],
    };
    socket.snapshot(
        players: ['me', 'friend'],
        seats: [0, 2],
        pieces: pieces,
        turn: 'friend',
        dice: [6, 4],
        rolledDice: [6, 4],
        rollPlayer: 'friend');
    await tester.pump();
    expect(find.byKey(const ValueKey('ludo-die-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('ludo-die-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('ludo-dice-content')))
            .opacity,
        .72);
    final tray = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('ludo-dice-tray')));
    expect((tray.decoration as BoxDecoration).border!.top.color,
        const Color(0xffffcd21));

    socket.snapshot(
        players: ['me', 'friend'],
        seats: [0, 2],
        pieces: pieces,
        turn: 'friend',
        dice: [4],
        rolledDice: [6, 4],
        rollPlayer: 'friend');
    await tester.pump();
    expect(find.byKey(const ValueKey('ludo-die-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('ludo-die-1')), findsOneWidget);
    expect(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('ludo-die-0')))
            .opacity,
        .42);

    socket.snapshot(
        players: ['me', 'friend'], seats: [0, 2], pieces: pieces, turn: 'me');
    await tester.pump();
    expect(find.byKey(const ValueKey('ludo-die-0')), findsNothing);
    expect(
        (tester
                .widget<AnimatedContainer>(
                    find.byKey(const ValueKey('ludo-dice-tray')))
                .decoration as BoxDecoration)
            .border!
            .top
            .color,
        const Color(0xffe83d47));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settings menu pauses and blurs the board, then resumes',
      (tester) async {
    final socket = await open(tester, size: const Size(320, 568));
    socket.snapshot(players: [
      'me',
      'friend'
    ], seats: [
      0,
      2
    ], pieces: {
      'me': [-1, -1, -1, -1],
      'friend': [-1, -1, -1, -1],
    });
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ludo-settings-menu')));
    await tester.pumpAndSettle();
    expect(find.text('How to play'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(socket.sent.last['type'], 'PAUSE_TOGGLE');

    socket.frames.add({
      'type': 'EVENT',
      'payload': {
        'type': 'GAME_PAUSED',
        'data': {'secondsLeft': 31}
      }
    });
    await tester.pump();
    expect(
        find.byKey(const ValueKey('ludo-paused-board-blur')), findsOneWidget);
    expect(find.byKey(const ValueKey('ludo-paused-overlay')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ludo-resume-button')));
    expect(socket.sent.last['type'], 'PAUSE_TOGGLE');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('board themes can be selected and persist across matches',
      (tester) async {
    final socket = await open(tester, size: const Size(320, 568));
    socket.snapshot(players: [
      'me',
      'friend'
    ], seats: [
      0,
      2
    ], pieces: {
      'me': [-1, -1, -1, -1],
      'friend': [-1, -1, -1, -1],
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('ludo-wood-frame')), findsOneWidget);
    expect(find.byKey(const ValueKey('ludo-board-classic')), findsOneWidget);
    for (final theme in ['glass', 'wood', 'classic']) {
      await tester.tap(find.byKey(const ValueKey('ludo-settings-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Board theme'));
      await tester.pumpAndSettle();
      expect(find.text('Classic'), findsOneWidget);
      expect(find.text('Glass'), findsOneWidget);
      expect(find.text('Weathered wood'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('ludo-theme-$theme')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('ludo-board-$theme')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byKey(const ValueKey('ludo-settings-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Board theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ludo-theme-glass')));
    await tester.pumpAndSettle();
    expect(
        (await SharedPreferences.getInstance()).getString('ludo_board_theme'),
        'glass');
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ludo-board-glass')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unstarted server room clears stale turn and disables play',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot(players: [
      'me',
      'friend'
    ], seats: [
      0,
      2
    ], pieces: {
      'me': [-1, -1, -1, -1],
      'friend': [-1, -1, -1, -1],
    }, dice: [
      6,
      4
    ]);
    await tester.pump();
    socket.frames.add({
      'type': 'ERROR',
      'payload': {
        'code': 'NOT_STARTED',
        'message': "this huud hasn't started a game yet"
      }
    });
    await tester.pump();
    expect(find.text('MATCH NO LONGER RUNNING'), findsOneWidget);
    expect(find.byKey(const ValueKey('ludo-return-to-games')), findsOneWidget);
    final actionCount = socket.sent.length;
    await tester.tap(find.byKey(const ValueKey('ludo-dice-tray')),
        warnIfMissed: false);
    await tester.pump();
    expect(socket.sent.length, actionCount);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (players, seats) in [
    (['me', 'friend'], [0, 2]),
    (['me', 'friend', 'third'], [0, 1, 2]),
    (['me', 'friend', 'third', 'fourth'], [0, 1, 2, 3]),
  ]) {
    testWidgets('${players.length} seats fit on a compact screen',
        (tester) async {
      final socket = await open(tester, size: const Size(320, 568));
      socket.snapshot(players: players, seats: seats, pieces: {
        for (final p in players) p: [-1, -1, -1, -1]
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (final p in players) {
        expect(find.byKey(ValueKey('$p:0')), findsOneWidget);
      }
      if (players.length == 2) {
        final self = tester.getTopLeft(find.byKey(const ValueKey('me:0')));
        final opponent =
            tester.getTopLeft(find.byKey(const ValueKey('friend:0')));
        expect(self.dx, lessThan(opponent.dx));
        expect(self.dy, lessThan(opponent.dy));
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
