import 'dart:async';
import 'dart:math' as math;

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
import 'package:truearena/features/draughts/draughts_theme.dart';
import 'package:truearena/theme/neon_theme.dart';

class _Socket implements GameSocket {
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
  @override
  void send(String type, [Map<String, dynamic>? payload]) {}
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
      expect(piecePaletteById('terracotta_ivory').id, 'red_white');
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
            nicknames: const {'me': 'You', 'opponent': 'Ada'},
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

    double textSize(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('draughts-turn-text'))).style!.fontSize!;

    testWidgets('"your turn" is big and bold, on a bright banner', (tester) async {
      final socket = await open(tester, 'me');
      socket.snapshot(snap('TurnA'));
      await tester.pump();

      expect(find.text('YOUR TURN'), findsOneWidget);
      expect(textSize(tester), greaterThanOrEqualTo(20), reason: 'it was 9pt before');
      final banner = tester.widget<AnimatedContainer>(find.byKey(const ValueKey('draughts-turn-banner')));
      expect((banner.decoration as BoxDecoration).color, const Color(0xffffc233));
    });

    testWidgets('"opponent is thinking" is just as readable', (tester) async {
      final socket = await open(tester, 'me');
      socket.snapshot(snap('TurnB'));
      await tester.pump();

      expect(find.text('OPPONENT IS THINKING'), findsOneWidget);
      expect(textSize(tester), greaterThanOrEqualTo(20));
      expect(find.byType(CircularProgressIndicator), findsWidgets, reason: 'a spinner says it is working');
    });

    testWidgets('a spectator is told whose turn it is by name, not "opponent"', (tester) async {
      final socket = await open(tester, 'a-watcher');
      socket.snapshot(snap('TurnB'));
      await tester.pump();

      expect(find.text("ADA'S TURN"), findsOneWidget);
      expect(find.text('OPPONENT IS THINKING'), findsNothing);
    });

    testWidgets('the banner fits a small phone without overflowing', (tester) async {
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
      expect(find.text('OPPONENT IS THINKING'), findsOneWidget);
    });
  });
}
