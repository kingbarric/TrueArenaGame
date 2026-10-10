import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/widgets/neon.dart' show Presence;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/game_socket.dart';
import 'package:truearena/features/chess/chess_game_screen.dart';
import 'package:truearena/features/chess/chess_view.dart';
import 'package:truearena/theme/neon_theme.dart';

class _Socket implements GameSocket {
  @override
  final awaySince = <String, DateTime>{};
  @override
  Presence presenceOf(String userId) => Presence.here;
  @override
  final memberAvatars = <String, String?>{};
  final frames = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final sent = <Map<String, dynamic>>[];

  @override
  final ValueNotifier<Set<String>> onlinePlayers =
      ValueNotifier({'me', 'opponent'});

  @override
  Stream<Map<String, dynamic>> get envelopes => frames.stream;

  @override
  bool get isConnected => true;

  @override
  int get lastSeq => 0;

  @override
  String get roomId => '00000000-0000-0000-0000-000000000001';

  @override
  void send(String type, [Map<String, dynamic>? payload]) {
    sent.add({'type': type, ...?payload});
  }

  @override
  Future<void> close() => frames.close();

  List<Map<String, dynamic>> get actions =>
      sent.where((m) => m['type'] == 'PLAYER_ACTION').toList();

  void snapshot({
    String phase = 'TurnW',
    String white = 'me',
    String black = 'opponent',
    String turn = 'white',
    Map<String, String> pieces = const {},
    Map<String, List<String>> legalMoves = const {},
    bool inCheck = false,
    String? pendingDrawOffer,
    String? pendingUndo,
    bool canClaimThreefold = false,
    String? winningSide,
    String? resultReason,
    List<String> moves = const [],
    Map<String, String>? lastMove,
  }) {
    final board = List<String?>.filled(64, null);
    final setup = pieces.isEmpty ? _initial : pieces;
    setup.forEach((sq, code) => board[parseSquare(sq)!] = code);
    frames.add({
      'type': 'SNAPSHOT',
      'payload': {
        'phase': phase,
        'round': 1,
        'white': white,
        'black': black,
        'turn': turn,
        'board': board,
        'inCheck': inCheck,
        'moves': moves,
        'lastMove': lastMove,
        'capturedByWhite': <String>[],
        'capturedByBlack': <String>[],
        'whiteMs': 600000,
        'blackMs': 600000,
        'incrementMs': 0,
        'pendingDrawOffer': pendingDrawOffer,
        'pendingUndo': pendingUndo,
        'canClaimThreefold': canClaimThreefold,
        'canClaimFiftyMove': false,
        'legalMoves': legalMoves,
        'winningSide': winningSide,
        'resultReason': resultReason,
        'clockMsLeft': 600000,
        'spectatorCount': 0,
      },
    });
  }
}

const _initial = {
  'a1': 'wR', 'b1': 'wN', 'c1': 'wB', 'd1': 'wQ', //
  'e1': 'wK', 'f1': 'wB', 'g1': 'wN', 'h1': 'wR',
  'a2': 'wP', 'b2': 'wP', 'c2': 'wP', 'd2': 'wP',
  'e2': 'wP', 'f2': 'wP', 'g2': 'wP', 'h2': 'wP',
  'a7': 'bP', 'b7': 'bP', 'c7': 'bP', 'd7': 'bP',
  'e7': 'bP', 'f7': 'bP', 'g7': 'bP', 'h7': 'bP',
  'a8': 'bR', 'b8': 'bN', 'c8': 'bB', 'd8': 'bQ',
  'e8': 'bK', 'f8': 'bB', 'g8': 'bN', 'h8': 'bR',
};

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<_Socket> open(WidgetTester tester, {bool spectating = false}) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final socket = _Socket();
    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient()),
      child: MaterialApp(
        theme: NeonTheme.dark,
        home: ChessGameScreen(
          socket: socket,
          selfId: spectating ? 'viewer' : 'me',
          spectating: spectating,
          roomCode: '7K3M',
          nicknames: const {'me': 'Eric', 'opponent': 'Ama'},
        ),
      ),
    ));
    await tester.pump();
    return socket;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  }

  testWidgets('renders the table: header, both players, board and turn',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot(legalMoves: const {
      'e2': ['e3', 'e4']
    });
    await tester.pump();

    expect(find.text('CHESS'), findsOneWidget);
    expect(find.text('HUUD 7K3M'), findsOneWidget);
    expect(find.text('YOU'), findsOneWidget);
    expect(find.text('Ama'), findsOneWidget);
    // Your picture glows green with the hand; your opponent's is amber.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('chess-player-white')), matching: find.byKey(const ValueKey('turn-ring-active'))),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('chess-player-black')), matching: find.byKey(const ValueKey('turn-ring-waiting'))),
        findsOneWidget);
    expect(
        find.descendant(of: find.byKey(const ValueKey('chess-player-white')), matching: find.byKey(const ValueKey('turn-hand'))),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chess-square-a1')), findsOneWidget);
    expect(find.byKey(const ValueKey('chess-square-h8')), findsOneWidget);
    expect(find.byKey(const ValueKey('chess-clock-white')), findsOneWidget);
    expect(find.text('10:00'), findsWidgets);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('tap a piece then a lit square sends the move', (tester) async {
    final socket = await open(tester);
    socket.snapshot(legalMoves: const {
      'e2': ['e3', 'e4']
    });
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('chess-square-e2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chess-square-e4')));
    await tester.pump();

    expect(socket.actions.single['action'], 'MOVE');
    expect(socket.actions.single['data'], {'from': 'e2', 'to': 'e4'});
    // Now the green ring is with the opponent.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('chess-player-black')), matching: find.byKey(const ValueKey('turn-ring-active'))),
        findsOneWidget);
    await close(tester);
  });

  testWidgets('a square the engine did not list is not a move', (tester) async {
    final socket = await open(tester);
    socket.snapshot(legalMoves: const {
      'e2': ['e3', 'e4']
    });
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('chess-square-e2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chess-square-e5')));
    await tester.pump();
    // A pinned piece, or any piece with nowhere to go, can't be picked up.
    await tester.tap(find.byKey(const ValueKey('chess-square-d2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chess-square-d4')));
    await tester.pump();

    expect(socket.actions, isEmpty);
    await close(tester);
  });

  testWidgets('black sees the board turned round', (tester) async {
    final socket = await open(tester);
    socket.snapshot(white: 'opponent', black: 'me');
    await tester.pump();

    final a1 = tester.getCenter(find.byKey(const ValueKey('chess-square-a1')));
    final h8 = tester.getCenter(find.byKey(const ValueKey('chess-square-h8')));
    expect(h8.dy, greaterThan(a1.dy));
    expect(h8.dx, lessThan(a1.dx));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('chess-player-white')), matching: find.byKey(const ValueKey('turn-ring-active'))),
        findsOneWidget);
    await close(tester);
  });

  testWidgets('promotion asks which piece and sends the choice',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot(pieces: const {
      'e1': 'wK',
      'a7': 'wP',
      'h8': 'bK',
    }, legalMoves: const {
      'a7': ['a8']
    });
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('chess-square-a7')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chess-square-a8')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Promote to'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chess-promote-n')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(socket.actions.single['data'],
        {'from': 'a7', 'to': 'a8', 'promotion': 'n'});
    await close(tester);
  });

  testWidgets('an opponent\'s draw offer can be accepted from the banner',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot(pendingDrawOffer: 'opponent');
    await tester.pump();

    expect(find.text('Ama offers a draw'), findsOneWidget);
    await tester.tap(find.text('Accept').first);
    await tester.pump();
    expect(socket.actions.single['action'], 'ACCEPT_DRAW');
    await close(tester);
  });

  testWidgets('threefold repetition offers a claim on your turn',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot(canClaimThreefold: true);
    await tester.pump();

    await tester.tap(find.text('Claim draw'));
    await tester.pump();
    expect(socket.actions.single['action'], 'CLAIM_DRAW');
    await close(tester);
  });

  testWidgets('a finished game shows who won and why', (tester) async {
    final socket = await open(tester);
    socket.snapshot(
        phase: 'Results', winningSide: 'black', resultReason: 'checkmate');
    await tester.pump();

    expect(find.byKey(const ValueKey('chess-results')), findsOneWidget);
    expect(find.text('You lost'), findsOneWidget);
    expect(find.text('Checkmate'), findsOneWidget);
    expect(find.text('0 – 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chess-view-board')));
    await tester.pump();
    expect(find.byKey(const ValueKey('chess-results')), findsNothing);
    await close(tester);
  });

  testWidgets('pausing stops the clocks and blocks moves until resumed',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot(legalMoves: const {
      'e2': ['e3', 'e4']
    });
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('chess-pause')));
    expect(socket.sent.last['type'], 'PAUSE_TOGGLE');
    socket.frames.add({
      'type': 'EVENT',
      'payload': {
        'type': 'GAME_PAUSED',
        'data': {'by': 'opponent', 'clockMsLeft': 431000},
      },
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('chess-paused')), findsOneWidget);
    expect(find.text('PAUSED'), findsWidgets);
    expect(find.text('7:11'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chess-square-e2')),
        warnIfMissed: false);
    await tester.tap(find.byKey(const ValueKey('chess-square-e4')),
        warnIfMissed: false);
    await tester.pump();
    expect(socket.actions, isEmpty);

    await tester.tap(find.byKey(const ValueKey('chess-resume')));
    expect(socket.sent.last['type'], 'PAUSE_TOGGLE');
    socket.frames.add({
      'type': 'EVENT',
      'payload': {
        'type': 'GAME_RESUMED',
        'data': {'by': 'me', 'clockMsLeft': 431000},
      },
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('chess-paused')), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('chess-player-white')), matching: find.byKey(const ValueKey('turn-ring-active'))),
        findsOneWidget);
    await close(tester);
  });

  testWidgets('VAR replays the opponent\'s last move', (tester) async {
    final socket = await open(tester);
    socket.snapshot(
        white: 'opponent', black: 'me', turn: 'white', moves: const []);
    await tester.pump();
    final tv = find.byKey(const ValueKey('game-control-var'));
    InkWell tvButton() => tester.widget<InkWell>(find.descendant(of: tv, matching: find.byType(InkWell)));
    expect(tv, findsOneWidget);
    expect(tvButton().onTap, isNull, reason: 'nothing to replay yet');

    final after = Map<String, String>.of(_initial)
      ..remove('e2')
      ..['e4'] = 'wP';
    socket.snapshot(
        white: 'opponent',
        black: 'me',
        turn: 'black',
        pieces: after,
        moves: const ['e4'],
        lastMove: const {'from': 'e2', 'to': 'e4'});
    await tester.pump();
    expect(tvButton().onTap, isNotNull);

    await tester.tap(tv);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('chess-var-sheet')), findsOneWidget);
    expect(find.text('Ama played e4'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // let the replay finish
    await close(tester);
  });

  testWidgets('spectators get no move controls', (tester) async {
    final socket = await open(tester, spectating: true);
    socket.snapshot(legalMoves: const {
      'e2': ['e4']
    });
    await tester.pump();

    expect(find.text('Resign'), findsNothing);
    // Watchers see whose move it is from the green ring; they get VAR and Rules only.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('chess-player-white')), matching: find.byKey(const ValueKey('turn-ring-active'))),
        findsOneWidget);
    expect(find.byKey(const ValueKey('game-control-undo')), findsNothing);
    expect(find.byKey(const ValueKey('game-control-rules')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chess-square-e2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chess-square-e4')));
    await tester.pump();
    expect(socket.actions, isEmpty);
    await close(tester);
  });

  group('chess_view helpers', () {
    test('square names and board orientation', () {
      expect(squareName(0), 'a1');
      expect(squareName(63), 'h8');
      expect(parseSquare('e4'), 28);
      expect(parseSquare('z9'), isNull);
      expect(squareAtCell(7, 0, flipped: false), parseSquare('a1'));
      expect(squareAtCell(0, 0, flipped: false), parseSquare('a8'));
      expect(squareAtCell(7, 0, flipped: true), parseSquare('h8'));
      expect(squareAtCell(0, 0, flipped: true), parseSquare('h1'));
    });

    test('promotion only for pawns reaching the last rank', () {
      expect(needsPromotion('wP', parseSquare('a8')!), isTrue);
      expect(needsPromotion('bP', parseSquare('h1')!), isTrue);
      expect(needsPromotion('wP', parseSquare('a7')!), isFalse);
      expect(needsPromotion('wQ', parseSquare('a8')!), isFalse);
    });

    test('clock shows tenths only in a scramble', () {
      expect(formatClock(600000), '10:00');
      expect(formatClock(61000), '1:01');
      expect(formatClock(19400), '0:19.4');
      expect(formatClock(-5), '0:00.0');
      expect(formatClock(3600000), '1:00:00');
    });

    test('reads the server view', () {
      final v = ChessView.fromJson({
        'phase': 'TurnB',
        'board': List<String?>.filled(64, null),
        'legalMoves': {
          'e7': ['e5', 'e6']
        },
        'lastMove': {'from': 'e2', 'to': 'e4'},
        'whiteMs': 599000,
      });
      expect(v.legalMoves[parseSquare('e7')], [36, 44]);
      expect(v.lastTo, parseSquare('e4'));
      expect(v.whiteMs, 599000);
      expect(v.finished, isFalse);
    });
  });

  testWidgets('when your opponent asks to undo, you see it and can allow it', (tester) async {
    final socket = await open(tester);
    socket.snapshot(turn: 'white', pendingUndo: 'opponent');
    await tester.pump();
    expect(find.byKey(const ValueKey('undo-ask')), findsOneWidget);
    expect(find.text('Ama wants to undo their move'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('undo-yes')));
    await tester.pump();
    expect(socket.actions.last['action'], 'ACCEPT_UNDO');
    await close(tester);
  });
}
