import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/widgets/neon.dart' show Presence;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/game_socket.dart';
import 'package:truearena/features/wordbluff/wordbluff_game_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

/// Records what the screen sends so tests can assert on actions and their data.
class _Socket implements GameSocket {
  @override
  final awaySince = <String, DateTime>{};
  @override
  Presence presenceOf(String userId) => Presence.here;
  @override
  final memberAvatars = <String, String?>{};
  final frames = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <({String type, Map<String, dynamic>? payload})>[];
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
  void send(String type, [Map<String, dynamic>? payload]) =>
      sent.add((type: type, payload: payload));
  @override
  Future<void> close() => frames.close();

  void snapshot(Map<String, dynamic> payload) =>
      frames.add({'type': 'SNAPSHOT', 'payload': payload});
  void phase(String phase, {int round = 1}) => frames.add({
        'type': 'PHASE',
        'payload': {'phase': phase, 'round': round}
      });
  void event(String type, Map<String, dynamic> data) => frames.add({
        'type': 'EVENT',
        'payload': {'type': type, 'data': data}
      });

  List<Map<String, dynamic>> actions(String action) => sent
      .where((s) => s.type == 'PLAYER_ACTION' && s.payload?['action'] == action)
      .map((s) => s.payload!)
      .toList();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  Future<_Socket> open(WidgetTester tester,
      {bool textMode = true, String describer = 'p1'}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final socket = _Socket();
    await tester.pumpWidget(AppScope(
      state: AppState(
          ApiClient(client: MockClient((_) async => http.Response('[]', 200)))),
      child: MaterialApp(
          theme: NeonTheme.dark,
          home: WordBluffGameScreen(
              socket: socket,
              selfId: 'p1',
              isHost: true,
              nicknames: const {
                'p1': 'Ada',
                'p2': 'Bot partner',
                'p3': 'Judge',
                'p4': 'Other'
              })),
    ));
    socket.snapshot({
      'phase': 'Turn',
      'round': 1,
      'teamA': ['p1', 'p2'],
      'teamB': ['p3', 'p4'],
      'turnTeam': 'A',
      'describer': describer,
      'textMode': textMode,
      'wordIndex': 7,
      'hasActiveCategory': true,
      'hasActiveWord': true,
      'clockStarted': true,
      'secondsLeft': 50,
      'category': 'animals',
      if (describer == 'p1') 'yourWord': 'elephant'
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    return socket;
  }

  testWidgets('human describer can send a typed clue to a bot', (tester) async {
    final socket = await open(tester);
    expect(find.text('Describe your word without naming it…'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField), 'Large grey animal with a trunk');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(socket.actions('TEXT_CLUE').single['data'],
        {'text': 'Large grey animal with a trunk', 'wordIndex': 7});
  });

  testWidgets(
      'human can read bot clue and submit a guess without seeing answer',
      (tester) async {
    final socket = await open(tester, describer: 'p2');
    socket.event('TEXT_CLUE', {
      'from': 'p2',
      'text': 'Large grey animal with a trunk',
      'wordIndex': 7
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Large grey animal', findRichText: true),
        findsWidgets);
    expect(find.text('elephant'), findsNothing);
    await tester.enterText(find.byType(TextField), 'elephant');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(socket.actions('TEXT_GUESS').single['data'],
        {'text': 'elephant', 'wordIndex': 7});
  });

  testWidgets('all human game retains the voice instructions', (tester) async {
    await open(tester, textMode: false, describer: 'p2');
    expect(find.text('Shout your guesses!'), findsOneWidget);
    expect(find.text('Type your guesses below!'), findsNothing);
  });
}
