import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/whot/whot_lobby_screen.dart';
import 'package:truearena/features/shell/main_shell.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/game_music.dart';
import 'package:truearena/core/game_sfx.dart';
import 'package:truearena/core/game_socket.dart';
import 'package:truearena/features/whot/whot_game_screen.dart';
import 'package:truearena/features/whot/whot_card.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/neon.dart';
import 'package:truearena/widgets/table_chat.dart';

class TestSocket implements GameSocket {
  @override
  final ValueNotifier<Set<String>> onlinePlayers = ValueNotifier(<String>{});
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];
  @override
  Stream<Map<String, dynamic>> get envelopes => controller.stream;
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
  Future<void> close() => controller.close();
  void snapshot(Map<String, dynamic> overrides) => controller.add({
        'type': 'SNAPSHOT',
        'payload': {
          'lobby': false,
          'phase': 'Turn',
          'players': ['me', 'other'],
          'dealer': 'me',
          'turnPlayer': 'me',
          'yourHand': ['circle-3', 'triangle-5', 'whot-20'],
          'topCard': 'circle-7',
          'activeShape': 'circle',
          'handSizes': {'me': 3, 'other': 5},
          'marketLeft': 40,
          'discardCount': 3,
          'secondsLeft': 45,
          'pendingPick': 0,
          'rules': {'pickTwo': true, 'pickTwoStacking': true},
          ...overrides,
        }
      });
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  Future<TestSocket> open(WidgetTester tester,
      {Map<String, dynamic> state = const {}}) async {
    final socket = TestSocket();
    await tester.pumpWidget(AppScope(
        state: AppState(ApiClient()),
        child: MaterialApp(
            theme: NeonTheme.dark,
            home: WhotGameScreen(
                socket: socket,
                selfId: 'me',
                roomId: 'room',
                roomCode: '572918',
                nicknames: const {'other': 'Alex'},
                avatars: const {'me': '🦊', 'other': '🤖'}))));
    socket.snapshot(state);
    await tester.pump();
    return socket;
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(target, warnIfMissed: false);
    await tester.pump();
  }

  testWidgets(
      'private hand, legal selection, and one action until acknowledgement',
      (tester) async {
    final socket = await open(tester);
    expect(find.byType(Avatar), findsNWidgets(2));
    expect(find.byWidgetPredicate((w) => w is Avatar && w.emoji == '🦊'),
        findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Avatar && w.emoji == '🤖'),
        findsOneWidget);
    expect(find.text('5 cards'), findsNothing);
    expect(find.byType(WhotCardView),
        findsNWidgets(12)); // private opponent stack, two piles, and own hand
    await tap(
        tester,
        find.byWidgetPredicate(
            (w) => w is WhotCardView && w.code == 'triangle-5'));
    expect(find.text('Play triangle 5'), findsNothing);
    await tap(
        tester,
        find.byWidgetPredicate(
            (w) => w is WhotCardView && w.code == 'circle-3'));
    socket.snapshot({
      'yourHand': ['triangle-5', 'whot-20'],
      'turnPlayer': 'other'
    });
    await tester.pump();
    expect(find.textContaining('IS PLAYING'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('last card warns briefly, then fades away', (tester) async {
    final socket = await open(tester);
    socket.snapshot({
      'handSizes': {'me': 3, 'other': 1}
    });
    await tester.pump();
    expect(find.text('Alex · LAST CARD!'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Alex · LAST CARD!'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('agent final card clears its seat and opens defeat summary',
      (tester) async {
    final socket = await open(tester);
    socket.controller.add({
      'type': 'EVENT',
      'payload': {
        'type': 'CARD_PLAYED',
        'data': {'by': 'other', 'card': 'circle-9'}
      }
    });
    socket.snapshot({
      'phase': 'Results',
      'winner': 'other',
      'topCard': 'circle-9',
      'yourHand': ['triangle-5', 'whot-20'],
      'handSizes': {'me': 2, 'other': 0},
      'round': 8,
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('whot-empty-hand')), findsOneWidget);
    expect(find.byKey(const ValueKey('whot-final-splash')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.byKey(const ValueKey('whot-game-over-dialog')), findsOneWidget);
    expect(find.textContaining('2 cards left'), findsOneWidget);
    await tester.tap(find.text('View summary'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('whot-result-summary')), findsOneWidget);
    expect(find.text('DEFEAT'), findsOneWidget);
    expect(find.text('Alex cards left'), findsOneWidget);
    expect(find.text('Play again'), findsOneWidget);
    expect(find.text('Play another game'), findsOneWidget);
    await tester.tap(find.text('Play again'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(WhotLobbyScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('winner sees victory and opponent remaining cards',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final socket = await open(tester);
    socket.snapshot({
      'phase': 'Results',
      'winner': 'me',
      'yourHand': <String>[],
      'handSizes': {'me': 0, 'other': 3},
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.tap(find.text('View summary'));
    await tester.pumpAndSettle();
    expect(find.text('VICTORY!'), findsOneWidget);
    expect(find.text('Alex cards left'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    await tester.tap(find.text('Play another game'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MainShell), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('forfeit ends without pretending a final card was played',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot({
      'phase': 'Results',
      'winner': 'me',
      'handSizes': {'me': 3, 'other': 5},
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('whot-final-splash')), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('whot-game-over-dialog')), findsOneWidget);
    await tester.tap(find.text('View summary'));
    await tester.pumpAndSettle();
    expect(find.text('None · game ended early'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('wild card requires a shape and sends it to server',
      (tester) async {
    final socket = await open(tester);
    await tap(
        tester,
        find.byWidgetPredicate(
            (w) => w is WhotCardView && w.code == 'whot-20'));
    final discard = find.byKey(const ValueKey('whot-discard-target'));
    final gesture = await tester.startGesture(tester.getCenter(find
        .byWidgetPredicate((w) => w is WhotCardView && w.code == 'whot-20')));
    await gesture.moveTo(tester.getCenter(discard),
        timeStamp: const Duration(milliseconds: 350));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(socket.sent.where((m) => m['action'] == 'PLAY'), isEmpty);
    expect(find.text('NAME YOUR SHAPE'), findsOneWidget);
    await tester.tap(find.text('▲  triangle'));
    await tester.pumpAndSettle();
    expect(socket.sent.last['data'], {'card': 'whot-20', 'shape': 'triangle'});
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('room code copies and all game controls live under one gear',
      (tester) async {
    await open(tester);
    expect(find.text('572918'), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);

    await tap(tester, find.byKey(const ValueKey('whot-room-code-copy')));
    expect(find.text('COPIED'), findsOneWidget);
    expect(find.text('Copied'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tap(tester, find.byIcon(Icons.settings_rounded));
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Mute music'), findsOneWidget);
    expect(find.text('Mute game sounds'), findsOneWidget);
    expect(find.text('Mute spectator comments'), findsOneWidget);
    expect(find.text('End game'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('audio can be muted from the game bar in one tap',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await GameMusic.setEnabled(true);
    await GameSfx.setEnabled(true);
    await open(tester);

    final toggle = find.byKey(const ValueKey('whot-audio-toggle'));
    expect(toggle, findsOneWidget);
    expect(find.byTooltip('Mute music and effects'), findsOneWidget);
    expect(find.byTooltip('Game voice and live speakers'), findsOneWidget);
    await tap(tester, toggle);
    expect(GameMusic.enabled, isFalse);
    expect(GameSfx.enabled, isFalse);
    expect(find.byTooltip('Unmute music and effects'), findsOneWidget);

    await tap(tester, toggle);
    expect(GameMusic.enabled, isTrue);
    expect(GameSfx.enabled, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('pausing blurs only the game table and shows a pause marker',
      (tester) async {
    final socket = await open(tester, state: {'paused': true});

    expect(
        find.byKey(const ValueKey('whot-paused-table-blur')), findsOneWidget);
    expect(find.byKey(const ValueKey('whot-paused-table-overlay')),
        findsOneWidget);
    expect(find.text('GAME PAUSED'), findsOneWidget);
    expect(find.text('TABLE PAUSED'), findsOneWidget);
    expect(find.byType(TableChatPanel), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('whot-resume-button')));
    expect(socket.sent.last['type'], 'PAUSE_TOGGLE');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'dealer controls use host rules and reconnect results include winner',
      (tester) async {
    final socket = await open(tester, state: {
      'phase': 'Deal',
      'yourHand': <String>[],
      'handSizes': {'me': 0, 'other': 0},
      'suggestedHand': 7
    });
    await tap(tester, find.text('DEAL HAND'));
    expect(socket.sent.last['data'], {'rounds': 7});
    socket.snapshot({
      'phase': 'Results',
      'winner': 'other',
      'yourHand': ['circle-3']
    });
    await tester.pump();
    expect(find.text('Alex won!'), findsOneWidget);
    expect(find.text('BACK TO GAMES'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('small phone layout and draw penalty', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final socket = await open(tester, state: {'pendingPick': 4});
    await tap(tester, find.text('MARKET · PICK 4'));
    expect(socket.sent.last['action'], 'DRAW');
    // Layout errors are reported by the test binding.
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('new cards travel from the market before joining the hand',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot({
      'yourHand': ['circle-3', 'triangle-5', 'whot-20', 'square-4'],
      'handSizes': {'me': 4, 'other': 5},
    });
    await tester.pump();
    expect(
        find.byWidgetPredicate(
            (w) => w is WhotCardView && w.code == 'square-4'),
        findsNothing);
    expect(find.byType(TweenAnimationBuilder<double>), findsWidgets);
    await tester.pump(const Duration(milliseconds: 900));
    expect(
        find.byWidgetPredicate(
            (w) => w is WhotCardView && w.code == 'square-4'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('opening deal sends cards around seats before revealing hand',
      (tester) async {
    final socket = await open(tester, state: {
      'phase': 'Deal',
      'yourHand': <String>[],
      'handSizes': {'me': 0, 'other': 0},
      'topCard': '',
    });
    socket.snapshot({
      'phase': 'Turn',
      'yourHand': ['circle-3', 'triangle-5', 'square-4', 'star-2', 'cross-7'],
      'handSizes': {'me': 5, 'other': 5},
      'topCard': 'circle-7',
    });
    await tester.pump();
    expect(find.text('Dealing cards around the table'), findsOneWidget);
    expect(find.text('Waiting for your cards'), findsOneWidget);
    expect(
        find.byType(TweenAnimationBuilder<double>), findsAtLeastNWidgets(10));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(
        find.byWidgetPredicate(
            (widget) => widget is WhotCardView && widget.code == 'triangle-5'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('pick two sends two staggered cards from market to your hand',
      (tester) async {
    final socket = await open(tester, state: {'pendingPick': 2});
    final faceDown =
        find.byWidgetPredicate((w) => w is WhotCardView && w.code == null);
    final before = faceDown.evaluate().length;

    await tap(tester, find.text('MARKET · PICK 2'));
    expect(faceDown, findsNWidgets(before + 2));
    expect(socket.sent.last['action'], 'DRAW');

    socket.snapshot({
      'pendingPick': 0,
      'turnPlayer': 'other',
      'handSizes': {'me': 5, 'other': 5},
      'yourHand': ['circle-3', 'triangle-5', 'whot-20', 'square-4', 'star-5'],
    });
    await tester.pump();
    expect(faceDown, findsNWidgets(before + 2));
    expect(find.text('You went to market · drew 2 cards'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1100));
    expect(
        find.byWidgetPredicate(
            (w) => w is WhotCardView && w.code == 'square-4'),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((w) => w is WhotCardView && w.code == 'star-5'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('opponent market cards travel to that opponent and announce it',
      (tester) async {
    final socket = await open(tester, state: {'turnPlayer': 'other'});
    final faceDown =
        find.byWidgetPredicate((w) => w is WhotCardView && w.code == null);
    final before = faceDown.evaluate().length;

    socket.snapshot({
      'turnPlayer': 'me',
      'handSizes': {'me': 3, 'other': 7},
    });
    await tester.pump();

    expect(faceDown, findsNWidgets(before + 2));
    expect(find.text('Alex went to market · drew 2 cards'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(faceDown, findsNWidgets(before));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('market and discard stacks reflect counts and animate recycling',
      (tester) async {
    final socket = await open(tester, state: {
      'marketLeft': 1,
      'discardCount': 4,
      'discardCards': ['square-4', 'triangle-7', 'circle-7'],
    });
    final market = find.byKey(const ValueKey('whot-market-pile'));
    final discard = find.byKey(const ValueKey('whot-discard-pile'));
    expect(find.descendant(of: market, matching: find.byType(WhotCardView)),
        findsOneWidget);
    expect(find.descendant(of: discard, matching: find.byType(WhotCardView)),
        findsNWidgets(3));
    expect(
        find.descendant(
            of: discard,
            matching: find.byWidgetPredicate(
                (w) => w is WhotCardView && w.code == 'triangle-7')),
        findsOneWidget);

    socket.snapshot({
      'marketLeft': 3,
      'discardCount': 1,
      'discardCards': ['circle-7'],
    });
    socket.controller.add({
      'type': 'EVENT',
      'payload': {
        'type': 'MARKET_RESHUFFLED',
        'data': {'marketLeft': 3}
      }
    });
    await tester.pump();
    expect(find.descendant(of: market, matching: find.byType(WhotCardView)),
        findsNWidgets(3));
    expect(find.descendant(of: discard, matching: find.byType(WhotCardView)),
        findsOneWidget);
    expect(find.text('RESHUFFLING MARKET'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1250));
    expect(find.text('RESHUFFLING MARKET'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('an opponent card travels to discard before becoming the top',
      (tester) async {
    final socket = await open(tester);
    socket.snapshot({'topCard': 'star-8', 'turnPlayer': 'other'});
    await tester.pump();
    expect(
        find.byWidgetPredicate(
            (w) => w is WhotCardView && w.code == 'circle-7'),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((w) => w is WhotCardView && w.code == 'star-8'),
        findsOneWidget); // The moving card, not the discard top yet.
    await tester.pump(const Duration(milliseconds: 900));
    expect(
        find.byWidgetPredicate(
            (w) => w is WhotCardView && w.code == 'circle-7'),
        findsNothing);
    expect(
        find.byWidgetPredicate((w) => w is WhotCardView && w.code == 'star-8'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('phone table renders with twenty seats and a large hand',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, state: {
      'players': ['me', 'other', for (var i = 2; i < 20; i++) 'p$i'],
      'yourHand': [
        for (var i = 0; i < 6; i++) ...['circle-3', 'triangle-5', 'whot-20']
      ],
    });
    await tester.pumpAndSettle();
    final capture = Platform.environment['WHOT_CAPTURE'];
    if (capture != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first);
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(capture).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'lobby sends chosen rules and lets the host retry a failed create',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? request;
    final client = MockClient((r) async {
      expect(r.url.path, '/api/v1/rooms');
      request = jsonDecode(r.body) as Map<String, dynamic>;
      return http.Response('{"message":"Local server unavailable"}', 503);
    });
    final state = AppState(ApiClient(client: client));
    await tester.pumpWidget(AppScope(
        state: state,
        child:
            MaterialApp(theme: NeonTheme.dark, home: const WhotLobbyScreen())));
    expect(find.byType(ListView), findsOneWidget);
    // Include Whot cards now defaults to off, so this assertion already holds
    // without tapping it — only toggle the switch we're actually testing here.
    await tap(tester, find.text('Stack twos'));
    await tap(tester, find.text('Open a huud'));
    await tester.pumpAndSettle();
    expect(request?['gameType'], 'whot');
    expect(request?['gameConfig'], containsPair('pickTwoStacking', false));
    expect(request?['gameConfig'], containsPair('includeWhot', false));
    expect(request?['gameConfig'], containsPair('startingHand', 5));
    expect(request?['gameConfig'], containsPair('turnSeconds', 60));
    expect(find.text('Local server unavailable'), findsWidgets);
    expect(find.text('Open a huud'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets('The Tell offers 30 symbols and sends a private choice',
      (tester) async {
    final socket = await open(tester, state: {
      'mode': 'tell',
      'phase': 'Signals',
      'players': ['me', 'other', 'p2', 'p3'],
      'teams': [
        ['me', 'other'],
        ['p2', 'p3']
      ],
      'yourTeam': 0,
    });
    expect(
        find.byKey(const ValueKey('whot-tell-signal-setup')), findsOneWidget);
    expect(find.byKey(const ValueKey('whot-choose-🪐')), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNWidgets(30));
    await tap(tester, find.byKey(const ValueKey('whot-choose-🪐')));
    expect(socket.sent.last['type'], 'PLAYER_ACTION');
    expect(socket.sent.last['action'], 'CHOOSE_SIGNAL');
    expect((socket.sent.last['data'] as Map)['symbol'], '🪐');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('The Tell lobby sends its matching rule and minimum',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? request;
    final client = MockClient((r) async {
      request = jsonDecode(r.body) as Map<String, dynamic>;
      return http.Response('{"message":"Unavailable"}', 503);
    });
    final state = AppState(ApiClient(client: client));
    await tester.pumpWidget(AppScope(
        state: state,
        child:
            MaterialApp(theme: NeonTheme.dark, home: const WhotLobbyScreen())));
    await tap(tester, find.text('The Tell'));
    expect(find.byKey(const ValueKey('whot-tell-rule')), findsOneWidget);
    expect(find.text('MINIMUM TELL'), findsOneWidget);
    await tap(tester, find.text('Open a huud'));
    await tester.pumpAndSettle();
    expect(request?['gameConfig'], containsPair('mode', 'tell'));
    expect(request?['gameConfig'], containsPair('tellRule', 'either'));
    expect(request?['gameConfig'], containsPair('tellMinCards', 3));
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('a public signal can be tapped to buzz and fades after 3 seconds',
      (tester) async {
    final socket = await open(tester, state: {
      'mode': 'tell',
      'players': ['me', 'other', 'p2', 'p3'],
      'teams': [
        ['me', 'other'],
        ['p2', 'p3']
      ],
      'yourTeam': 0,
      'yourSignal': '🪐',
    });
    socket.snapshot({
      'mode': 'tell',
      'players': ['me', 'other', 'p2', 'p3'],
      'teams': [
        ['me', 'other'],
        ['p2', 'p3']
      ],
      'yourTeam': 0,
      'signal': {
        'id': 7,
        'by': 'other',
        'symbol': '🪐',
        'sentAtMs': DateTime.now().millisecondsSinceEpoch,
      }
    });
    await tester.pump();
    expect(find.text('Alex → 🪐'), findsOneWidget);
    expect(find.text('TAP TO BUZZ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('whot-tell-signal-card')),
        warnIfMissed: false);
    expect(socket.sent.last['action'], 'BUZZ');
    expect((socket.sent.last['data'] as Map)['signalId'], 7);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('whot-tell-signal-card')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('pick-two debt cannot be answered with a wild or when stacking is off',
      () {
    final state = {
      'pendingPick': 2,
      'rules': {'pickTwo': true, 'pickTwoStacking': true}
    };
    expect(whotCanPlay('whot-20', state), isFalse);
    expect(whotCanPlay('triangle-2', state), isTrue);
    state['rules'] = {'pickTwo': true, 'pickTwoStacking': false};
    expect(whotCanPlay('triangle-2', state), isFalse);
  });
}
