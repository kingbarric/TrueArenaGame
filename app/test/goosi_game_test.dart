import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/game_socket.dart';
import 'package:truearena/features/goosi/goosi_game_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

class _Socket implements GameSocket {
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

  void snapshot({
    String phase = 'TurnP0',
    List<int> pits = const [4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4],
    List<int> legalPits = const [0, 1, 2, 3, 4, 5],
    Map<String, int> scores = const {'me': 0, 'opponent': 0},
    bool paused = false,
  }) {
    frames.add({
      'type': 'SNAPSHOT',
      'payload': {
        'phase': phase,
        'round': 1,
        'players': ['me', 'opponent'],
        'owner': [
          ...List.filled(6, 'me'),
          ...List.filled(6, 'opponent'),
        ],
        'pits': pits,
        'pitsPerPlayer': 6,
        'legalPits': legalPits,
        'scores': scores,
        'paused': paused,
        'secondsLeft': 38,
      },
    });
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

  Future<_Socket> open(WidgetTester tester,
      {Size size = const Size(390, 844)}) async {
    await tester.binding.setSurfaceSize(size);
    final socket = _Socket();
    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient()),
      child: MaterialApp(
        theme: NeonTheme.dark,
        home: GoosiGameScreen(
          socket: socket,
          selfId: 'me',
          roomCode: '7K3M',
          nicknames: const {'me': 'Eric', 'opponent': 'Ama'},
        ),
      ),
    ));
    await tester.pump();
    return socket;
  }

  testWidgets('renders the two-row Macala table and attached players',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot();
    await tester.pump();

    expect(find.text('MACALA'), findsOneWidget);
    expect(find.text('HUUD 7K3M'), findsOneWidget);
    expect(find.byKey(const ValueKey('goosi-player-me')), findsOneWidget);
    expect(find.byKey(const ValueKey('goosi-player-opponent')), findsOneWidget);
    expect(find.text('YOU'), findsOneWidget);
    expect(find.text('AMA'), findsOneWidget);
    expect(find.byKey(const ValueKey('goosi-pit-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('goosi-pit-11')), findsOneWidget);
    expect(find.text('YOUR TURN'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('captured seeds remain visible outside both sides of the board',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot(scores: const {'me': 8, 'opponent': 5});
    await tester.pump();

    expect(find.byKey(const ValueKey('macala-captured-me')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('macala-captured-opponent')), findsOneWidget);
    expect(find.text('8 CAPTURED'), findsOneWidget);
    expect(find.text('5 CAPTURED'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opponent hand reaches and overlaps the top board pit',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot(phase: 'TurnP1');
    await tester.pump();

    socket.event('SOWN', {
      'from': 11,
      'touched': [10],
      'laps': [
        [10]
      ],
      'by': 'opponent',
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pump(const Duration(milliseconds: 450));

    final hand = find.byIcon(Icons.back_hand_rounded);
    final destination = find.byKey(const ValueKey('goosi-pit-10'));
    expect(hand, findsOneWidget);
    expect(tester.getRect(hand).overlaps(tester.getRect(destination)), isTrue);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('only a server-approved house can be sown', (tester) async {
    final socket = await open(tester);
    socket.snapshot(legalPits: const [5]);
    await tester.pump();

    final before = socket.sent.length;
    await tester.tap(find.byKey(const ValueKey('goosi-pit-0')));
    expect(socket.sent.length, before);

    await tester.tap(find.byKey(const ValueKey('goosi-pit-5')));
    expect(socket.sent.last, {
      'type': 'PLAYER_ACTION',
      'action': 'SOW',
      'data': {'pit': 5},
    });

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compact iPhone layout fits without overflow', (tester) async {
    final socket = await open(tester, size: const Size(320, 568));
    socket.snapshot();
    await tester.pump();

    expect(find.byKey(const ValueKey('goosi-pit-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('goosi-pit-11')), findsOneWidget);
    expect(find.text('Request undo'), findsOneWidget);
    expect(find.text('Offer draw'), findsOneWidget);
    expect(find.text('CHAT'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('paused game is covered and resume remains available',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot(paused: true);
    await tester.pump();

    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('theme menu exposes the five physical board designs',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Game settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Board & stones'));
    await tester.pumpAndSettle();

    expect(find.text('Macala Classic'), findsOneWidget);
    expect(find.text('The Folding Set'), findsOneWidget);
    expect(find.text('Riverstone Slab'), findsOneWidget);
    expect(find.text('Palm Wine Lacquer'), findsOneWidget);
    expect(find.text('Ebony & Brass'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
