import 'package:truearena/widgets/game_artwork.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/widgets/neon.dart' show NeonButton, Presence;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/game_socket.dart';
import 'package:truearena/features/game/game_screen.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/table_chat.dart';

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
      {String self = 'p1', bool host = false, bool spectating = false}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final socket = _Socket();
    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient(client: MockClient((_) async => http.Response('[]', 200)))),
      child: MaterialApp(
        theme: NeonTheme.dark,
        home: GameScreen(socket: socket, selfId: self, isHost: host, spectating: spectating, nicknames: const {
          'p1': 'Ada', 'p2': 'Bola', 'p3': 'Chidi', 'p4': 'Dayo', 'p5': 'Efe', 'p6': 'Femi',
        }),
      ),
    ));
    socket.snapshot(snapshot);
    await tester.pump();
    return socket;
  }

  testWidgets('selected Traitors mode artwork is blended behind gameplay', (tester) async {
    await open(tester, _snap('RoundTable', extra: {'preset': 'blood_moon'}));
    final backdrop = tester.widget<GameArtworkBackdrop>(find.byType(GameArtworkBackdrop));
    expect(backdrop.mode, 'blood_moon');
    expect(backdrop.gameType, 'truearena');
    expect(find.byKey(const ValueKey('round-table-title')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bot game opens round-table text and sends player discussion',
      (tester) async {
    final socket =
        await open(tester, _snap('RoundTable', extra: {'botTextMode': true}));
    expect(
        find.text('Type to discuss the round with the bots.'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField), 'Why did you change your story?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(socket.sent.last.type, 'CHAT_SEND');
    expect(socket.sent.last.payload,
        {'channel': 'table', 'text': 'Why did you change your story?'});
  });

  testWidgets('all-human round table keeps text collapsed', (tester) async {
    await open(tester, _snap('RoundTable', extra: {'botTextMode': false}));
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('faithful in a bot game cannot type in the traitors night chat',
      (tester) async {
    await open(tester, _snap('Night', extra: {'botTextMode': true}));
    expect(find.byType(TextField), findsNothing);
  });

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
  testWidgets('the host can pause the clock and add two minutes', (tester) async {
    final socket = await open(tester, _snap('RoundTable', extra: {'secondsLeft': 90}), host: true);
    expect(find.text('1:30'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('traitors-add-time')));
    await tester.tap(find.byKey(const ValueKey('traitors-pause')));
    await tester.pump();
    expect(socket.sent.map((s) => s.type), containsAllInOrder(['HOST_CONTROL', 'PAUSE_TOGGLE']));
    expect(socket.sent.firstWhere((s) => s.type == 'HOST_CONTROL').payload, {'cmd': 'EXTEND_TIMER'});

    socket.event('GAME_PAUSED', {'by': 'p1', 'secondsLeft': 210, 'resumesInSeconds': 600});
    await tester.pump();
    expect(find.text('Clock paused · runs again in 10:00'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Clock paused · runs again in 9:57'), findsOneWidget);
    expect(find.text('⏸ 3:30'), findsWidgets, reason: 'a paused clock holds still');
  });

  testWidgets('players see the reveal moving on by itself, and no clock controls', (tester) async {
    final socket = await open(tester, _snap('Elimination', extra: {'secondsLeft': 20}));
    expect(find.text('Moving on in 20 s'), findsOneWidget);
    expect(find.byKey(const ValueKey('traitors-pause')), findsNothing);
    expect(find.byKey(const ValueKey('traitors-add-time')), findsNothing);

    socket.event('GAME_PAUSED', {'by': 'p2', 'secondsLeft': 18, 'resumesInSeconds': 600});
    await tester.pump();
    expect(find.text('The host paused the clock'), findsOneWidget);

    socket.event('GAME_RESUMED', {'reason': 'pause_limit', 'secondsLeft': 18});
    await tester.pump();
    expect(find.text('Moving on in 18 s'), findsOneWidget);
  });

  testWidgets('round table: everyone sits around the table, the talk and the skip in the middle', (tester) async {
    final table = [for (var i = 1; i <= 14; i++) 'p$i'];
    final socket = await open(tester, {
      'phase': 'RoundTable', 'round': 1, 'players': table, 'alive': table.sublist(0, 12),
      'yourRole': 'faithful', 'rules': const {'twists': []}, 'secondsLeft': 120,
    }, host: true);
    final seats = [for (final id in table) tester.getRect(find.byKey(ValueKey('table-seat-$id')))];
    final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final seat in seats) {
      expect(screen.contains(seat.topLeft) && screen.contains(seat.bottomRight), isTrue, reason: '$seat');
    }
    for (var i = 0; i < seats.length; i++) {
      for (var j = i + 1; j < seats.length; j++) {
        expect(seats[i].deflate(4).overlaps(seats[j].deflate(4)), isFalse, reason: 'seat $i and seat $j overlap');
      }
    }
    // The talk sits in the middle, ringed by the seats.
    final title = tester.getCenter(find.byKey(const ValueKey('round-table-title')));
    final top = seats.first.center, bottom = seats[7].center;
    expect(title.dy, inExclusiveRange(top.dy, bottom.dy));
    expect((title.dx - screen.width / 2).abs(), lessThan(24));

    await tester.tap(find.byKey(const ValueKey('round-table-skip')));
    await tester.pump();
    expect(socket.actions('ADVANCE_PHASE'), hasLength(1));
  });

  testWidgets('wooden table fits timer and both actions without scrolling on phones', (tester) async {
    await open(tester, _snap('RoundTable', extra: {
      'canAccuse': true, 'secondsLeft': 120, 'botTextMode': true,
      'players': [for (var i = 1; i <= 16; i++) 'p$i'],
    }), host: true);
    for (final size in [const Size(390, 844), const Size(390, 700)]) {
      tester.view.physicalSize = size * 3;
      await tester.pumpAndSettle(const Duration(milliseconds: 250));
      final wood = find.byKey(const ValueKey('discussion-wooden-table'));
      expect(wood, findsOneWidget);
      expect(find.descendant(of: wood, matching: find.byType(Scrollable)), findsNothing);
      final bounds = tester.getRect(wood);
      for (final key in ['round-table-accuse', 'round-table-skip']) {
        final button = tester.getRect(find.byKey(ValueKey(key)));
        expect(bounds.contains(button.topLeft), isTrue);
        expect(bounds.contains(button.bottomRight), isTrue);
        expect(button.height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('players other than the host have no skip', (tester) async {
    await open(tester, _snap('RoundTable'));
    expect(find.byKey(const ValueKey('round-table-skip')), findsNothing);
    expect(find.byKey(const ValueKey('round-table-title')), findsOneWidget);
  });

  testWidgets('table chat is one conversation in order — agents too — kept across rounds', (tester) async {
    final socket = await open(tester, _snap('RoundTable', extra: {'botTextMode': true}));
    socket.event('CHAT_MESSAGE', {'from': 'p2', 'channel': 'agent', 'text': 'I have a bad feeling about Chidi.'});
    socket.event('CHAT_MESSAGE', {'from': 'p1', 'channel': 'table', 'text': 'Why Chidi?'});
    socket.event('CHAT_MESSAGE', {'from': 'p3', 'channel': 'agent', 'text': 'Bola is deflecting.'});
    await tester.pump();
    final first = tester.getTopLeft(find.text('I have a bad feeling about Chidi.')).dy;
    final second = tester.getTopLeft(find.text('Why Chidi?')).dy;
    final third = tester.getTopLeft(find.text('Bola is deflecting.')).dy;
    expect(first, lessThan(second));
    expect(second, lessThan(third), reason: 'the newest message is at the bottom');
    // One chat on screen, not a second audience box.
    expect(find.byType(TableChatPanel), findsNothing);

    socket.phase('Vote');
    await tester.pump();
    socket.phase('RoundTable', round: 2);
    await tester.pump();
    expect(find.text('Bola is deflecting.'), findsOneWidget, reason: 'nothing is wiped between phases');
    expect(find.text('ROUND 2'), findsOneWidget);
  });

  testWidgets('the host can end the game for everyone: nobody wins, and every role is shown', (tester) async {
    final socket = await open(tester, _snap('RoundTable'), host: true);
    await tester.tap(find.byTooltip('Game settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End game for everyone'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('traitors-end-confirm')));
    await tester.pumpAndSettle();
    expect(socket.sent.last.type, 'PLAYER_ACTION');
    expect(socket.sent.last.payload, {'action': 'END_GAME'});

    socket.event('GAME_ENDED_BY_HOST', {'round': 1});
    socket.event('FULL_REVEAL', {'roles': {for (final p in _players) p: p == 'p2' ? 'traitor' : 'faithful'}});
    socket.phase('Results');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('The host ended the game'), findsOneWidget);
    expect(find.text('FULL REVEAL'), findsOneWidget);
    expect(find.text('You won! 🎉'), findsNothing);
  });

  testWidgets('only the host has End game', (tester) async {
    await open(tester, _snap('RoundTable'));
    await tester.tap(find.byTooltip('Game settings'));
    await tester.pumpAndSettle();
    expect(find.text('End game for everyone'), findsNothing);
  });

  testWidgets('the Traitors music is credited in settings', (tester) async {
    await open(tester, _snap('RoundTable'));
    await tester.tap(find.byTooltip('Game settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Music credits'));
    await tester.pumpAndSettle();
    final credits = tester.widget<SelectableText>(find.byKey(const ValueKey('traitors-music-credits'))).data!;
    expect(credits, contains('Kevin MacLeod (incompetech.com)'));
    expect(credits, contains('https://creativecommons.org/licenses/by/4.0/'));
    for (final title in ['Heart of Nowhere', 'Lightless Dawn', 'Crypto', 'Gathering Darkness']) {
      expect(credits, contains(title));
    }
  });

  /// What a spectator is sent: the public table, no role of their own.
  Map<String, dynamic> watching(String phase) => {..._snap(phase)}..remove('yourRole');

  testWidgets('a spectator watches the real table by name, reads the talk, and can react', (tester) async {
    final socket = await open(tester, watching('RoleReveal'), self: 'watcher', spectating: true);
    expect(find.byKey(const ValueKey('watch-role-reveal')), findsOneWidget);
    expect(find.text('You are Faithful'), findsNothing);

    socket.snapshot(watching('RoundTable'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (final id in _players) {
      expect(find.byKey(ValueKey('table-seat-$id')), findsOneWidget);
    }
    expect(find.text('Ada'), findsWidgets);
    expect(find.byKey(const ValueKey('round-table-skip')), findsNothing);
    // The players' debate is there to read, not to type into.
    await tester.tap(find.text('Round table chat'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('watch-table-chat-note')), findsOneWidget);

    // A reaction a second, as the server allows.
    expect(find.byKey(const ValueKey('traitors-reaction-tray')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('traitors-react-😮')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('traitors-react-🔥')));
    await tester.pump();
    expect(socket.sent.where((s) => s.type == 'REACTION_SEND').map((s) => s.payload), [
      {'emoji': '😮'}
    ]);
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.tap(find.byKey(const ValueKey('traitors-react-🔥')));
    await tester.pump();
    expect(socket.sent.where((s) => s.type == 'REACTION_SEND'), hasLength(2));

    socket.event('GAME_OVER', {'winningSide': 'faithful'});
    socket.phase('Results');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Thanks for watching 👀'), findsOneWidget);
    expect(find.text('Better luck next table.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the table sees spectators\' reactions float past, once each, and not while muted', (tester) async {
    final socket = await open(tester, _snap('RoundTable'));
    await tester.pump(const Duration(milliseconds: 400));
    // Players don't get a tray — reactions are the audience's.
    expect(find.byKey(const ValueKey('traitors-reaction-tray')), findsNothing);
    final now = DateTime.now().millisecondsSinceEpoch;
    socket.event('SPECTATOR_REACTION', {'id': 'r1', 'from': 'watcher', 'emoji': '🎉', 'sentAtMs': now});
    socket.event('SPECTATOR_REACTION', {'id': 'r1', 'from': 'watcher', 'emoji': '🎉', 'sentAtMs': now});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('🎉'), findsOneWidget);

    socket.event('SPECTATORS_MUTED', {});
    socket.event('SPECTATOR_REACTION', {'id': 'r2', 'from': 'watcher', 'emoji': '😂', 'sentAtMs': now});
    await tester.pump();
    expect(find.text('😂'), findsNothing);

    // Each one drifts away after a couple of seconds.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('🎉'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  Future<void> seconds(WidgetTester tester, int n) async {
    for (var i = 0; i < n * 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('a murder is revealed at the table: 5 seconds, the name, 3 seconds, then Faithful — sadly', (tester) async {
    final socket = await open(tester, _snap('MorningReveal', extra: {'secondsLeft': 30}), host: true);
    socket.event('MORNING_REVEAL', {'round': 1, 'eliminated': 'p3'});
    socket.event('PLAYER_ELIMINATED', {'id': 'p3', 'cause': 'murdered', 'roleShown': true, 'role': 'faithful'});
    await tester.pump();
    expect(find.text('Who was taken in the night?'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('reveal-count')), matching: find.text('5')), findsOneWidget);
    expect(find.byKey(const ValueKey('table-seat-p3')), findsOneWidget, reason: 'it happens at the round table');
    expect(tester.widget<NeonButton>(find.byKey(const ValueKey('reveal-continue'))).onPressed, isNull,
        reason: 'the host waits for the reveal');

    await seconds(tester, 5);
    expect(find.byKey(const ValueKey('reveal-name')), findsOneWidget);
    expect(find.text('Chidi'), findsWidgets);
    expect(find.text('was…'), findsOneWidget);
    expect(find.text('FAITHFUL'), findsNothing);

    await seconds(tester, 3);
    expect(find.text('FAITHFUL'), findsOneWidget);
    expect(find.text('An innocent soul is gone.'), findsOneWidget);

    await seconds(tester, 4);
    await tester.tap(find.byKey(const ValueKey('reveal-continue')));
    await tester.pump();
    expect(socket.actions('ADVANCE_PHASE'), hasLength(1));
  });

  testWidgets('host can continue the pre-tally elimination without a reveal event', (tester) async {
    final socket = await open(tester, _snap('VoteReview'), host: true);
    socket.phase('Elimination');
    await tester.pump();
    await seconds(tester, 6);
    final button = find.byKey(const ValueKey('reveal-continue'));
    expect(tester.widget<NeonButton>(button).onPressed, isNotNull,
      reason: 'the server needs ADVANCE_PHASE before it can calculate the outcome');
    await tester.tap(button);
    await tester.pump();
    expect(socket.actions('ADVANCE_PHASE'), hasLength(1));
    expect(tester.widget<NeonButton>(button).onPressed, isNull,
      reason: 'prevent duplicate requests while awaiting the server');
    socket.phase('WinCheck');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Checking the table…'), findsOneWidget);
  });

  testWidgets('an active banishment reveal still finishes before host can continue', (tester) async {
    final socket = await open(tester, _snap('Elimination'), host: true);
    socket.event('PLAYER_ELIMINATED', {'id': 'p2', 'cause': 'banished', 'roleShown': true, 'role': 'traitor'});
    await tester.pump();
    final button = find.byKey(const ValueKey('reveal-continue'));
    expect(tester.widget<NeonButton>(button).onPressed, isNull);
    await seconds(tester, 12);
    expect(tester.widget<NeonButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pump();
    expect(socket.actions('ADVANCE_PHASE'), hasLength(1));
  });

  testWidgets('a banished Traitor is a celebration', (tester) async {
    final socket = await open(tester, _snap('Elimination'));
    socket.event('BANISHED', {'id': 'p2', 'votes': 4});
    socket.event('PLAYER_ELIMINATED', {'id': 'p2', 'cause': 'banished', 'roleShown': true, 'role': 'traitor'});
    await tester.pump();
    expect(find.text('The table has spoken…'), findsOneWidget);
    await seconds(tester, 8);
    expect(find.text('A TRAITOR!'), findsOneWidget);
    expect(find.text('One less Traitor at the table.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hidden role stays hidden, and a quiet night says nobody left', (tester) async {
    final socket = await open(tester, _snap('Elimination'));
    socket.event('PLAYER_ELIMINATED', {'id': 'p4', 'cause': 'banished', 'roleShown': false});
    await tester.pump();
    await seconds(tester, 8);
    expect(find.text('Their role stays hidden'), findsOneWidget);
    expect(find.text('A TRAITOR!'), findsNothing);
    expect(find.text('FAITHFUL'), findsNothing);

    socket.phase('MorningReveal', round: 2);
    socket.event('NO_MURDER', {'round': 2, 'reason': 'skipped'});
    await tester.pump();
    await seconds(tester, 5);
    expect(find.text('Nobody left the table'), findsOneWidget);
  });
}
