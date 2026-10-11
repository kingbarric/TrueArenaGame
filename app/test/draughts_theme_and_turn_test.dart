import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/widgets/neon.dart' show Presence;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/game_socket.dart';
import 'package:truearena/features/draughts/draughts_game_screen.dart';
import 'package:truearena/features/draughts/draughts_theme.dart';
import 'package:truearena/theme/neon_theme.dart';

class _Socket implements GameSocket {
  @override
  final awaySince = <String, DateTime>{};
  @override
  Presence presenceOf(String userId) => Presence.here;
  @override
  final memberAvatars = <String, String?>{};
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
  final sent = <String>[];
  @override
  void send(String type, [Map<String, dynamic>? payload]) => sent.add('$type ${payload?['action'] ?? ''}');
  @override
  Future<void> close() => frames.close();
  void snapshot(Map<String, dynamic> payload) => frames.add({'type': 'SNAPSHOT', 'payload': payload});
}

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

/// Straight-line distance in RGB (0–255 per channel) — a rough "how different
/// do these look", good enough to catch two pieces that read as one colour.
double _distance(Color a, Color b) {
  double ch(double x, double y) => (x - y) * 255;
  return math.sqrt(math.pow(ch(a.r, b.r), 2) + math.pow(ch(a.g, b.g), 2) + math.pow(ch(a.b, b.b), 2));
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('board and piece themes', () {
    test('there are exactly four boards, and black & white is the default', () {
      expect(boardPalettes.map((p) => p.id), ['classic', 'tournament', 'ocean', 'wood']);
      expect(boardPalettes.first.label, 'Black & White');
      expect(boardPalettes.first.darkSquare.computeLuminance(), lessThan(0.05));
      expect(boardPalettes.first.lightSquare.computeLuminance(), greaterThan(0.8));
    });

    test('on every board the two square colours are easy to tell apart', () {
      for (final b in boardPalettes) {
        expect(_contrast(b.darkSquare, b.lightSquare), greaterThan(4.0), reason: '${b.label} grid is hard to read');
      }
    });

    test('every piece pair stands out from every board and from each other', () {
      for (final p in piecePalettes) {
        expect(_distance(p.aMid, p.bMid), greaterThan(150), reason: '${p.label}: the two sides look alike');
        for (final b in boardPalettes) {
          for (final c in [p.aTop, p.aMid, p.bTop, p.bMid]) {
            expect(_distance(c, b.darkSquare), greaterThan(90), reason: '${p.label} blends into ${b.label}');
          }
        }
      }
    });

    test('colour choices saved from the old brown set fall back to the new default', () {
      expect(boardPaletteById('walnut').id, 'classic');
      expect(piecePaletteById('terracotta_ivory').id, 'red_blue');
    });
  });

  group('whose turn it is', () {
    Future<_Socket> open(WidgetTester tester, String selfId) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final socket = _Socket();
      await tester.pumpWidget(AppScope(
        state: AppState(ApiClient(client: MockClient((_) async => http.Response('{}', 200)))),
        child: MaterialApp(
          theme: NeonTheme.dark,
          home: DraughtsGameScreen(
            socket: socket,
            selfId: selfId,
            nicknames: const {'me': 'eric', 'opponent': 'ada'},
          ),
        ),
      ));
      return socket;
    }

    Map<String, dynamic> snap(String phase) => {
          'phase': phase,
          'round': 1,
          'playerA': 'me',
          'playerB': 'opponent',
          'board': List<String?>.filled(50, null)..[30] = 'B_MAN'..[45] = 'A_MAN',
          'turnSeconds': 60,
        };

    /// The ring round a side's picture: 'active' (green) or 'waiting' (amber).
    String ring(WidgetTester tester, String side) {
      final active = find.descendant(
          of: find.byKey(ValueKey('draughts-side-$side')), matching: find.byKey(const ValueKey('turn-ring-active')));
      return active.evaluate().isNotEmpty ? 'active' : 'waiting';
    }

    Alignment handAt(WidgetTester tester) => tester
        .widget<AnimatedAlign>(find.ancestor(of: find.byKey(const ValueKey('turn-hand')), matching: find.byType(AnimatedAlign)))
        .alignment as Alignment;

    testWidgets('no turn banner: you glow green with the hand, the other player amber', (tester) async {
      final socket = await open(tester, 'me');
      socket.snapshot(snap('TurnA'));
      await tester.pump();

      expect(find.byKey(const ValueKey('draughts-turn-banner')), findsNothing);
      expect(ring(tester, 'A'), 'active');
      expect(ring(tester, 'B'), 'waiting');
      expect(handAt(tester).x, -1, reason: 'the hand sits with player A (left)');
    });

    testWidgets("on the other player's turn the green ring and the hand move over to them", (tester) async {
      final socket = await open(tester, 'me');
      socket.snapshot(snap('TurnB'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(ring(tester, 'A'), 'waiting');
      expect(ring(tester, 'B'), 'active');
      expect(handAt(tester).x, 1);
      expect(find.text('ada'), findsOneWidget, reason: 'names stay under the pictures');
    });

    testWidgets('a spectator sees whose turn it is from the green ring and the hand', (tester) async {
      final socket = await open(tester, 'a-watcher');
      socket.snapshot(snap('TurnB'));
      await tester.pump();

      expect(ring(tester, 'B'), 'active');
      expect(find.byKey(const ValueKey('turn-hand')), findsOneWidget);
    });

    testWidgets('when the other player asks to undo, you see it and can allow it', (tester) async {
      final socket = await open(tester, 'me');
      socket.snapshot({...snap('TurnB'), 'pendingUndo': 'opponent'});
      await tester.pump();
      expect(find.byKey(const ValueKey('undo-ask')), findsOneWidget);
      expect(find.text('ada wants to undo their move'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('undo-yes')));
      expect(socket.sent, contains('PLAYER_ACTION ACCEPT_UNDO'));
    });

    testWidgets('your own undo request does not ask you', (tester) async {
      final socket = await open(tester, 'me');
      socket.snapshot({...snap('TurnB'), 'pendingUndo': 'me'});
      await tester.pump();
      expect(find.byKey(const ValueKey('undo-ask')), findsNothing);
    });

    testWidgets('the players and board fit a small phone without overflowing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final socket = _Socket();
      await tester.pumpWidget(AppScope(
        state: AppState(ApiClient(client: MockClient((_) async => http.Response('{}', 200)))),
        child: MaterialApp(
          theme: NeonTheme.dark,
          home: DraughtsGameScreen(socket: socket, selfId: 'me', nicknames: const {'me': 'You', 'opponent': 'Ada'}),
        ),
      ));
      socket.snapshot(snap('TurnB'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('turn-hand')), findsOneWidget);
    });
  });
}
