import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/game_socket.dart';
import 'package:truearena/features/game/game_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

/// Records what the screen sends so tests can assert on actions and their data.
class _Socket implements GameSocket {
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
  void send(String type, [Map<String, dynamic>? payload]) => sent.add((type: type, payload: payload));
  @override
  Future<void> close() => frames.close();

  void snapshot(Map<String, dynamic> payload) => frames.add({'type': 'SNAPSHOT', 'payload': payload});
  void phase(String phase, {int round = 1}) =>
      frames.add({'type': 'PHASE', 'payload': {'phase': phase, 'round': round}});
  void event(String type, Map<String, dynamic> data) =>
      frames.add({'type': 'EVENT', 'payload': {'type': type, 'data': data}});

  List<Map<String, dynamic>> actions(String action) => sent
      .where((s) => s.type == 'PLAYER_ACTION' && s.payload?['action'] == action)
      .map((s) => s.payload!)
      .toList();
}

const _players = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'];

Map<String, dynamic> _snap(String phase, {
  String role = 'faithful',
  List<String> alive = _players,
  Map<String, dynamic> rules = const {'twists': []},
  Map<String, dynamic> extra = const {},
}) =>
    {
      'phase': phase,
      'round': 1,
      'players': _players,
      'alive': alive,
      'yourRole': role,
      'rules': rules,
      ...extra,
    };

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<_Socket> open(WidgetTester tester, Map<String, dynamic> snapshot,
      {String self = 'p1', bool host = false}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final socket = _Socket();
    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient(client: MockClient((_) async => http.Response('[]', 200)))),
      child: MaterialApp(
        theme: NeonTheme.dark,
        home: GameScreen(socket: socket, selfId: self, isHost: host, nicknames: const {
          'p1': 'Ada', 'p2': 'Bola', 'p3': 'Chidi', 'p4': 'Dayo', 'p5': 'Efe', 'p6': 'Femi',
        }),
      ),
    ));
    socket.snapshot(snapshot);
    await tester.pump();
    return socket;
  }

  testWidgets('a locked vote stays highlighted when someone else votes', (tester) async {
    final socket = await open(tester, _snap('Vote', extra: {'yourVote': 'p3', 'voteProgress': {'locked': 1, 'total': 6}}));
    expect(find.text('Your vote is locked: Chidi · 1/6 in'), findsOneWidget);

    // Another player votes: the server re-sends PHASE (same phase) and a fresh snapshot.
    socket.phase('Vote');
    socket.snapshot(_snap('Vote', extra: {'yourVote': 'p3', 'voteProgress': {'locked': 2, 'total': 6}}));
    await tester.pump();
    expect(find.text('Your vote is locked: Chidi · 2/6 in'), findsOneWidget);

    await tester.tap(find.text('Dayo'));
    await tester.pump();
    expect(socket.actions('CAST_VOTE'), isEmpty, reason: 'a locked vote cannot be re-cast');
  });

  testWidgets('eliminated players watch the vote instead of getting a picker that errors', (tester) async {
    await open(tester, _snap('Vote', alive: ['p2', 'p3', 'p4', 'p5', 'p6']));
    expect(find.text('The table is voting'), findsOneWidget);
    expect(find.text('Cast your vote'), findsNothing);
  });

  testWidgets('traitors see each other\'s night picks, can skip, and can talk', (tester) async {
    final socket = await open(tester, _snap('Night', role: 'traitor',
        rules: const {'twists': [], 'requireTraitorConsensus': true, 'allowSkip': true},
        extra: {
          'fellowTraitors': ['p2'],
          'nightPicks': {'p2': 'p4'},
          'canSkipNight': true,
        }));

    expect(find.text('Every traitor must pick the same target before the clock runs out.'), findsOneWidget);
    expect(find.text('Bola'), findsWidgets); // the partner's pick is tagged on Dayo
    expect(find.text('Traitors only'), findsOneWidget); // night chat for the traitors

    await tester.tap(find.text('Skip tonight (once per game)'));
    await tester.pump();
    expect(socket.actions('NIGHT_SKIP'), hasLength(1));
  });

  testWidgets('the traitors\' night chat survives each other\'s picks', (tester) async {
    final socket = await open(tester, _snap('Night', role: 'traitor', extra: {'fellowTraitors': ['p2']}));
    socket.event('CHAT_MESSAGE', {'from': 'p2', 'channel': 'traitors', 'text': 'Dayo?'});
    await tester.pump();
    await tester.tap(find.text('Traitors only'));
    await tester.pumpAndSettle(); // the panel animates open
    expect(find.text('Dayo?'), findsOneWidget);

    socket.phase('Night'); // re-sent after Bola's pick
    await tester.pump();
    expect(find.text('Dayo?'), findsOneWidget);
  });

  testWidgets('a double murder comes from the server flag, so it works in Custom games too', (tester) async {
    final socket = await open(tester, _snap('Night', role: 'traitor',
        extra: {'fellowTraitors': <String>[], 'doubleMurderAvailable': true}));
    await tester.tap(find.text('Chidi'));
    await tester.pump();
    expect(find.text('Choose a second target'), findsOneWidget);
    await tester.tap(find.text('Dayo'));
    await tester.pump();
    expect(socket.actions('NIGHT_TARGET').single['data'], {'target': 'p3', 'secondTarget': 'p4'});
  });

  testWidgets('the host can award immunity in any game that has the coin', (tester) async {
    await open(tester, _snap('RoundTable', rules: const {'twists': ['immunity_coin']},
        extra: {'immunityAvailable': true}), host: true);
    expect(find.text('Award challenge immunity'), findsOneWidget);
  });

  testWidgets('host-assigned votes have a screen instead of a spinner', (tester) async {
    final socket = await open(tester, _snap('HostAssignVotes', extra: {'missingVoters': ['p5']}), host: true);
    expect(find.text('Efe hasn\'t voted.'), findsOneWidget);
    await tester.tap(find.text('VOTE FOR EFE')); // NeonChip uppercases its label
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ada'));
    await tester.pumpAndSettle();
    expect(socket.actions('HOST_ASSIGN_VOTE').single['data'], {'voterId': 'p5', 'target': 'p1'});
  });

  testWidgets('trial of two names both tied players in the defense', (tester) async {
    await open(tester, _snap('Defense', extra: {'tieCandidates': ['p2', 'p3']}));
    expect(find.text('Trial of two'), findsOneWidget);
    expect(find.text('Bola and Chidi each make their case. Then a final vote between them.'), findsOneWidget);
  });

  testWidgets('the host can step through a sequential vote review', (tester) async {
    final socket = await open(tester, _snap('VoteReview', rules: const {'twists': [], 'voteReveal': 'sequential'}),
        host: true);
    await tester.tap(find.text('Reveal next vote'));
    await tester.pump();
    expect(socket.actions('REVEAL_NEXT'), hasLength(1));
  });

  testWidgets('twist actions appear only when the table has the twist', (tester) async {
    await open(tester, _snap('RoundTable', role: 'traitor',
        rules: const {'twists': ['confessional', 'false_reveal']},
        extra: {'confessionalSubmitted': false, 'falseRevealUses': 1, 'falseRevealArmed': false,
          'fellowTraitors': ['p2']}));
    expect(find.text('Submit your confessional'), findsOneWidget);
    expect(find.text('Hide the next banished Faithful\'s role'), findsOneWidget);
  });

  testWidgets('results release the votes the veiled endgame hid', (tester) async {
    final socket = await open(tester, _snap('Results', extra: {'winningSide': 'faithful'}));
    socket.event('FULL_REVEAL', {
      'roles': {for (final p in _players) p: p == 'p2' ? 'traitor' : 'faithful'},
      'ballots': [
        {'round': 3, 'stage': 'vote', 'veiled': true, 'votes': {'p1': 'p2', 'p3': 'p2'}},
        {'round': 1, 'stage': 'vote', 'veiled': false, 'votes': {'p1': 'p4'}},
      ],
    });
    await tester.pump();
    expect(find.text('THE HIDDEN VOTES'), findsOneWidget);
    expect(find.text('Ada → Bola'), findsOneWidget);
    expect(find.text('Ada → Dayo'), findsNothing, reason: 'unveiled rounds were already shown live');
  });
}
