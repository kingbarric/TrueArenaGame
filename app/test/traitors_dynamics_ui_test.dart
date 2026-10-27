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
import 'package:truearena/features/game/traitors_twists.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/neon.dart' show Presence;

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
  void send(String type, [Map<String, dynamic>? payload]) => sent.add((type: type, payload: payload));
  @override
  Future<void> close() => frames.close();

  void snapshot(Map<String, dynamic> payload) => frames.add({'type': 'SNAPSHOT', 'payload': payload});

  /// The last game action sent, as {action, data}.
  Map<String, dynamic> get lastAction => sent.lastWhere((s) => s.type == 'PLAYER_ACTION').payload!;
}

const _players = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'];
const _names = {'p1': 'Ada', 'p2': 'Bola', 'p3': 'Chidi', 'p4': 'Dayo', 'p5': 'Efe', 'p6': 'Femi'};

Map<String, dynamic> _table(String phase, {String role = 'faithful', List<String> alive = _players,
    List<String> twists = const [], Map<String, dynamic> extra = const {}}) => {
      'phase': phase,
      'round': 2,
      'players': _players,
      'alive': alive,
      'yourRole': role,
      'rules': {'twists': twists},
      ...extra,
    };

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<_Socket> open(WidgetTester tester, Map<String, dynamic> snapshot,
      {String self = 'p1', bool spectating = false}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final socket = _Socket();
    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient(client: MockClient((_) async => http.Response('[]', 200)))),
      child: MaterialApp(
        theme: NeonTheme.dark,
        home: GameScreen(socket: socket, selfId: self, isHost: false, spectating: spectating, nicknames: _names),
      ),
    ));
    socket.snapshot(snapshot);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return socket;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await settle(tester);
  }

  testWidgets('a Traitor plans the night: recruit, bake, mark', (tester) async {
    final socket = await open(tester, _table('Night', role: 'traitor', extra: {
      'fellowTraitors': ['p2'],
      'canRecruit': true,
      'recruitTargets': ['p3', 'p4'],
      'canBakePie': true,
      'canPlaceSpot': true,
      'spotPending': null,
    }));
    expect(find.byKey(const ValueKey('traitors-night-plan')), findsOneWidget);

    await tapKey(tester, 'plan-recruit');
    expect(find.text('Make an offer'), findsOneWidget);
    await tapKey(tester, 'pick-p3');
    expect(socket.lastAction, {'action': 'RECRUIT_OFFER', 'data': {'target': 'p3'}});

    socket.snapshot(_table('Night', role: 'traitor', extra: {'fellowTraitors': ['p2'], 'canBakePie': true, 'canPlaceSpot': true}));
    await settle(tester);
    await tapKey(tester, 'plan-pie');
    await tapKey(tester, 'bake-poison');
    expect(socket.lastAction, {'action': 'BAKE_PIE', 'data': {'filling': 'poison'}});

    socket.snapshot(_table('Night', role: 'traitor', extra: {'fellowTraitors': ['p2'], 'canPlaceSpot': true}));
    await settle(tester);
    await tapKey(tester, 'plan-spot');
    await tapKey(tester, 'pick-p5');
    expect(socket.lastAction, {'action': 'PLACE_SPOT', 'data': {'target': 'p5'}});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a recruiting night the Traitors see who gets the letter, not a target picker', (tester) async {
    await open(tester, _table('Night', role: 'traitor', extra: {'fellowTraitors': ['p2'], 'recruitingTonight': 'p4'}));
    expect(find.byKey(const ValueKey('traitors-recruiting-tonight')), findsOneWidget);
    expect(find.textContaining('Dayo finds your sealed letter'), findsOneWidget);
    expect(find.text('Choose your target'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('at night the Faithful give an alibi, and the Seer lights the lantern or keeps it', (tester) async {
    final socket = await open(tester, _table('Night', twists: ['alibis'], extra: {'alibiNeeded': true}));
    expect(find.text('Where were you tonight?'), findsOneWidget);
    await tester.tap(find.text('Chidi'));
    await settle(tester);
    expect(socket.lastAction, {'action': 'ALIBI', 'data': {'with': 'p3'}});
    await tester.pumpWidget(const SizedBox());

    final seer = await open(tester, _table('Night', twists: ['seer_lantern'],
        extra: {'seer': {'canLight': true, 'lanternUsed': false, 'visions': {}}}));
    expect(find.text('Light the lantern'), findsOneWidget);
    await tester.tap(find.text('Bola'));
    await settle(tester);
    expect(seer.lastAction, {'action': 'SEER_LANTERN', 'data': {'target': 'p2'}});
    // The server answers with a fresh table; a Seer who'd rather wait keeps the lantern.
    seer.snapshot(_table('Night', twists: ['seer_lantern'],
        extra: {'seer': {'canLight': true, 'lanternUsed': false, 'visions': {}}}));
    await settle(tester);
    await tapKey(tester, 'traitors-lantern-keep');
    expect(seer.lastAction, {'action': 'SEER_LANTERN'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Traitors\' offer arrives as a sealed letter, answered in a tap', (tester) async {
    final socket = await open(tester, _table('MorningReveal', twists: ['recruiting'], extra: {'recruitOffer': true}));
    expect(find.byKey(const ValueKey('traitors-recruit-letter')), findsOneWidget);
    expect(find.text('The Traitors want you.'), findsOneWidget);
    await tapKey(tester, 'traitors-recruit-accept');
    expect(socket.lastAction, {'action': 'RECRUIT_ANSWER', 'data': {'accept': true}});
    socket.snapshot(_table('MorningReveal', twists: ['recruiting']));
    await settle(tester);
    expect(find.byKey(const ValueKey('traitors-recruit-letter')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the round table carries the pie, the clue, the alibis and the Black Spot', (tester) async {
    final socket = await open(tester, _table('RoundTable', twists: ['poisoned_pie', 'crime_clues', 'alibis', 'black_spot'], extra: {
      'pie': {'available': true, 'clue': 'A faint smell of bitter almonds', 'holder': null},
      'crimeClues': [
        {'kind': 'seat', 'within': 1, 'victim': 'p6', 'round': 2}
      ],
      'alibiBoard': {'p1': 'p2', 'p2': 'p1', 'p3': 'p4'},
      'blackSpot': {'holder': 'p1', 'chain': ['p5', 'p1'], 'silenced': null},
    }));
    expect(find.byKey(const ValueKey('traitors-tabletop-tray')), findsOneWidget);
    expect(find.textContaining('bitter almonds'), findsOneWidget);
    expect(find.text('A Traitor sat within 1 seat of Femi.'), findsOneWidget);
    // The seats either side of the victim glow.
    expect(find.byKey(const ValueKey('clue-glow-p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('clue-glow-p5')), findsOneWidget);
    expect(find.byKey(const ValueKey('clue-glow-p3')), findsNothing);
    // The web stays folded away until someone opens it.
    expect(find.byKey(const ValueKey('discussion-table-links')), findsNothing);
    expect(find.byKey(const ValueKey('spot-on-p1')), findsOneWidget);

    await tester.tap(find.text('Take the pie'));
    await settle(tester);
    expect(socket.lastAction, {'action': 'TAKE_PIE'});
    await tester.scrollUntilVisible(find.byKey(const ValueKey('tray-alibis')), 200,
        scrollable: find.descendant(of: find.byKey(const ValueKey('traitors-tabletop-tray')), matching: find.byType(Scrollable)));
    expect(find.textContaining('1 pair backs each other up; 1 story goes one way'), findsOneWidget);
    await tester.ensureVisible(find.text('See the web'));
    await settle(tester);
    await tester.tap(find.text('See the web'));
    await settle(tester);
    expect(find.byKey(const ValueKey('discussion-table-links')), findsOneWidget);
    expect(find.byKey(const ValueKey('traitors-web-legend')), findsOneWidget);
    expect(find.byKey(const ValueKey('round-table-title')), findsNothing);
    await tapKey(tester, 'traitors-web-hide');
    expect(find.byKey(const ValueKey('discussion-table-links')), findsNothing);
    socket.snapshot(_table('RoundTable', twists: ['black_spot'], extra: {
      'blackSpot': {'holder': 'p1', 'chain': ['p5', 'p1'], 'silenced': null},
    }));
    await settle(tester);
    await tester.ensureVisible(find.text('Pass it on'));
    await settle(tester);
    await tester.tap(find.text('Pass it on'));
    await settle(tester);
    expect(find.byKey(const ValueKey('pick-p5')), findsNothing, reason: 'never back to someone who held it');
    await tapKey(tester, 'pick-p3');
    expect(socket.lastAction, {'action': 'PASS_SPOT', 'data': {'to': 'p3'}});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Black Spot\'s holder sits the vote out', (tester) async {
    await open(tester, _table('Vote', twists: ['black_spot'], extra: {
      'blackSpot': {'holder': 'p1', 'chain': ['p1'], 'silenced': 'p1'},
    }));
    expect(find.byKey(const ValueKey('traitors-silenced')), findsOneWidget);
    expect(find.text('Cast your vote'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the crowd\'s meter — and a hunch from a Faithful who is out', (tester) async {
    final socket = await open(tester, _table('RoundTable', twists: ['crowd_hunch'],
        alive: ['p2', 'p3', 'p4', 'p5', 'p6'],
        extra: {'crowdHunch': {'voters': 3, 'suspect': 'p2', 'percent': 67, 'split': false}, 'canCrowdVote': true}));
    expect(find.text('The crowd suspects Bola'), findsOneWidget);
    expect(find.textContaining('67% · 3 voices'), findsOneWidget);
    await tapKey(tester, 'traitors-crowd-vote');
    await tapKey(tester, 'pick-p4');
    expect(socket.lastAction, {'action': 'CROWD_VOTE', 'data': {'target': 'p4'}});
    await tester.pumpWidget(const SizedBox());

    await open(tester, _table('RoundTable', twists: ['crowd_hunch'], extra: {'crowdHunch': {'voters': 2}}));
    expect(find.text('The crowd is still making up its mind…'), findsOneWidget);
    expect(find.byKey(const ValueKey('traitors-crowd-vote')), findsNothing, reason: 'players at the table have no say');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a spectator casts a hunch and sees it', (tester) async {
    final socket = await open(tester, {..._table('RoundTable', twists: ['crowd_hunch'],
        extra: {'crowdHunch': {'voters': 0}})}..remove('yourRole'), self: 'watcher', spectating: true);
    await tapKey(tester, 'traitors-crowd-vote');
    await tapKey(tester, 'pick-p6');
    expect(socket.lastAction, {'action': 'CROWD_VOTE', 'data': {'target': 'p6'}});
    expect(find.textContaining('your hunch: Femi'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Ghost Jury: a juror chooses between the tied, everyone else waits', (tester) async {
    final socket = await open(tester, _table('GhostJury', twists: ['ghost_jury'], alive: ['p2', 'p3', 'p4', 'p5'],
        extra: {'tieCandidates': ['p2', 'p3'], 'ghostJuror': true}));
    expect(find.byKey(const ValueKey('traitors-ghost-jury')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ghost-vote-p3')));
    await settle(tester);
    expect(socket.lastAction, {'action': 'GHOST_VOTE', 'data': {'target': 'p3'}});
    await tester.pumpWidget(const SizedBox());

    await open(tester, _table('GhostJury', twists: ['ghost_jury'], extra: {'tieCandidates': ['p2', 'p3']}));
    expect(find.text('The ghosts are deliberating…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a Last Stand at the final four, then the table sees what it showed', (tester) async {
    final socket = await open(tester, _table('RoundTable', twists: ['last_stand'], alive: ['p1', 'p2', 'p3', 'p4'],
        extra: {'canLastStand': true}));
    await tester.ensureVisible(find.text('Make a stand'));
    await tester.tap(find.text('Make a stand'));
    await settle(tester);
    await tapKey(tester, 'last-stand-confirm');
    await tapKey(tester, 'pick-p2');
    expect(socket.lastAction, {'action': 'LAST_STAND', 'data': {'target': 'p2'}});

    socket.snapshot(_table('RoundTable', twists: ['last_stand'], alive: ['p2', 'p3', 'p4'],
        extra: {'standReveal': {'by': 'p1', 'target': 'p2', 'side': 'traitor'}, 'lastStandUsed': true}));
    await settle(tester);
    expect(find.byKey(const ValueKey('traitors-last-stand')), findsOneWidget);
    expect(find.text('You made a Last Stand: Bola is a TRAITOR.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('every clue reads as a sentence', () {
    String name(String id) => _names[id] ?? id;
    expect(clueText({'kind': 'seat', 'within': 2, 'victim': 'p1'}, name), 'A Traitor sat within 2 seats of Ada.');
    expect(clueText({'kind': 'trio', 'ids': ['p2', 'p3', 'p4'], 'victim': 'p1'}, name),
        'At least one of Bola, Chidi and Dayo is a Traitor.');
    expect(clueText({'kind': 'vote', 'target': 'p5', 'victim': 'p1'}, name), 'A Traitor voted for Efe at the last vote.');
  });

  test('alibis become lines: one gold line for a pair, a red one for a one-way story', () {
    final tw = TraitorsTwists()..apply({'alibiBoard': {'a': 'b', 'b': 'a', 'c': 'a'}});
    final links = tw.alibiLinks;
    expect(links.where((l) => l.mutual), hasLength(1));
    expect(links.where((l) => !l.mutual).single, (from: 'c', to: 'a', mutual: false));
    expect(tw.seatGlow(['a', 'b', 'c', 'd', 'e']), isEmpty);
    tw.apply({'crimeClues': [{'kind': 'seat', 'within': 1, 'victim': 'a'}]});
    expect(tw.seatGlow(['a', 'b', 'c', 'd', 'e']), {'b', 'e'});
  });
}
