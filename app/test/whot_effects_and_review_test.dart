import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:truearena/core/game_sfx.dart';
import 'package:truearena/core/game_music.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/whot/whot_game_screen.dart';
import 'package:truearena/features/whot/whot_effects.dart';
import 'package:truearena/features/whot/whot_var.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'whot_game_test.dart' show TestSocket;

void main() {
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await GameMusic.setEnabled(false);
    await GameSfx.setEnabled(false);
  });
  Future<TestSocket> open(WidgetTester tester,
      {bool spectating = false,
      bool reduced = false,
      Map<String, dynamic> state = const {}}) async {
    final socket = TestSocket();
    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('capture-whot'),
        child: AppScope(
          state: AppState(ApiClient()),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: NeonTheme.dark,
            builder: (context, child) => MediaQuery(
                data:
                    MediaQuery.of(context).copyWith(disableAnimations: reduced),
                child: child!),
            home: WhotGameScreen(
                socket: socket,
                selfId: 'me',
                nicknames: const {'other': 'Ada'},
                roomId: 'room',
                spectating: spectating),
          ),
        )));
    socket.snapshot({'stateSeq': 0, ...state});
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    return socket;
  }

  void event(TestSocket socket, int? seq, String type,
          Map<String, dynamic> data) =>
      socket.controller.add({
        'type': 'EVENT',
        'payload': {'type': type, if (seq != null) 'seq': seq, 'data': data},
      });

  testWidgets(
      'a confirmed counter animates once and reconnect history stays quiet',
      (tester) async {
    final socket = await open(tester, state: {
      'stateSeq': 10,
      'recentPlays': [
        {'id': 9, 'kind': 'pickTwo', 'by': 'other', 'debt': 2},
      ]
    });
    event(socket, 9, 'WHOT_MOMENT', {'id': 9, 'kind': 'pickTwo', 'debt': 2});
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('whot-effect-pickTwo')), findsNothing);
    event(socket, 11, 'WHOT_MOMENT', {
      'id': 11,
      'kind': 'pickTwo',
      'by': 'other',
      'target': 'me',
      'debt': 4,
      'pendingBefore': 2
    });
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('whot-effect-pickTwo')), findsOneWidget);
    event(socket, 11, 'WHOT_MOMENT', {'id': 11, 'kind': 'pickTwo', 'debt': 99});
    await tester.pump();
    await tester.pump();
    final stage =
        tester.widget<WhotEffectStage>(find.byType(WhotEffectStage).first);
    expect(stage.moment!['debt'], 4);
    expect(
        whotMomentTitle({
          'kind': 'pickTwo',
          'debt': 4,
          'pendingBefore': 2,
          'returned': true
        }),
        'RETURNED! +4');
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('whot-effect-pickTwo')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'final effect chooser is non-modal, saves its choice and does not release a pending card',
      (tester) async {
    final socket = await open(tester, state: {
      'yourHand': ['circle-3', 'triangle-5'],
      'handSizes': {'me': 2, 'other': 5}
    });
    socket.snapshot({
      'stateSeq': 1,
      'yourHand': ['circle-3'],
      'handSizes': {'me': 1, 'other': 5}
    });
    await tester.pump();
    await tester.pump();
    expect(find.text('Choose a final card effect'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('MARKET · 40'));
    await tester.pump();
    await tester.pump();
    expect(socket.sent.last['action'], 'DRAW');
    final choice = find.byKey(const ValueKey('whot-effect-royal'));
    await tester.scrollUntilVisible(choice, 180,
        scrollable: find.descendant(
            of: find.byKey(const ValueKey('whot-final-effect-picker')),
            matching: find.byType(Scrollable)));
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pump();
    await tester.pump();
    final cosmeticId = socket.sent.last['actionId'];
    expect(socket.sent.last['action'], 'SELECT_FINISH_EFFECT');
    expect(socket.sent.last['data'], {'effect': 'royal'});
    expect(
        (await SharedPreferences.getInstance()).getString('whot_final_effect'),
        'royal');
    expect(find.text('Choose a final card effect'), findsNothing);
    socket.snapshot({
      'stateSeq': 2,
      'ackActionId': cosmeticId,
      'yourHand': ['circle-3'],
      'handSizes': {'me': 1, 'other': 5},
      'finishEffects': {'me': 'royal'}
    });
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('MARKET · 40'));
    await tester.pump();
    await tester.pump();
    expect(socket.sent.where((m) => m['action'] == 'DRAW').length, 1);
    expect(find.text('Choose a final card effect'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'VAR reviews public cards and undo uses the shared Allow / No request',
      (tester) async {
    final socket = await open(tester, state: {
      'pendingUndo': 'other',
      'undoResponders': ['me'],
      'undoAccepted': [],
      'recentPlays': [
        {
          'id': 1,
          'by': 'other',
          'kind': 'pickTwo',
          'card': 'circle-2',
          'topBefore': 'circle-7',
          'handSizes': {'me': 3, 'other': 4},
          'debt': 2
        }
      ],
    });
    await tester.tap(find.byKey(const ValueKey('undo-yes')));
    await tester.pump();
    await tester.pump();
    expect(socket.sent.last['action'], 'ACCEPT_UNDO');
    await tester.tap(find.byKey(const ValueKey('game-control-var')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('whot-var-title')), findsOneWidget);
    expect(find.textContaining('Public plays only'), findsOneWidget);
    final replay = tester.widget<WhotVarSheet>(find.byType(WhotVarSheet));
    expect(replay.plays.first.containsKey('yourHand'), isFalse);
    expect(replay.plays.first['card'], 'circle-2');
    expect(socket.sent.any((m) => m['type'] == 'PAUSE_TOGGLE'), isFalse);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'spectator reactions stay outside the board and disappear without blocking it',
      (tester) async {
    final socket = await open(tester, spectating: true);
    await tester.tap(find.byKey(const ValueKey('whot-react-🔥')));
    await tester.pump();
    await tester.pump();
    expect(socket.sent.last, {'type': 'REACTION_SEND', 'emoji': '🔥'});
    event(socket, null, 'SPECTATOR_REACTION', {
      'id': 'r1',
      'from': 'viewer',
      'emoji': '🔥',
      'sentAtMs': DateTime.now().millisecondsSinceEpoch
    });
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final board =
        tester.getRect(find.byKey(const ValueKey('whot-board-play-area')));
    final lane = find.byKey(const ValueKey('whot-reactions-left'));
    final emoji = find.descendant(of: lane, matching: find.text('🔥'));
    expect(emoji, findsOneWidget);
    expect(tester.getRect(emoji).right, lessThanOrEqualTo(board.left));
    await tester.pump(const Duration(seconds: 3));
    expect(emoji, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'reduced motion is honoured and the phone layout shows effects without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      for (final name in {
        'Archivo',
        'Roboto',
        'Baloo2',
        'Baloo 2',
        NeonTheme.dark.textTheme.bodyMedium!.fontFamily!,
        NeonTheme.dark.textTheme.titleLarge!.fontFamily!
      }) {
        if (!File('/System/Library/Fonts/Supplemental/Arial.ttf').existsSync())
          break;
        final font = FontLoader(name)
          ..addFont(File('/System/Library/Fonts/Supplemental/Arial.ttf')
              .readAsBytes()
              .then((b) => ByteData.sublistView(b)));
        await font.load();
      }
      if (File(
              '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .existsSync()) {
        final icons = FontLoader('MaterialIcons')
          ..addFont(File(
                  '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
              .readAsBytes()
              .then((b) => ByteData.sublistView(b)));
        await icons.load();
      }
    });
    final socket = await open(tester, reduced: true);
    socket.snapshot({
      'stateSeq': 1,
      'yourHand': ['circle-3'],
      'handSizes': {'me': 1, 'other': 5}
    });
    await tester.pump();
    await tester.pump();
    event(socket, 2, 'WHOT_MOMENT', {
      'id': 2,
      'kind': 'pickTwo',
      'by': 'other',
      'target': 'me',
      'debt': 4,
      'pendingBefore': 2
    });
    event(socket, null, 'SPECTATOR_REACTION', {
      'id': 'r2',
      'emoji': '😮',
      'sentAtMs': DateTime.now().millisecondsSinceEpoch
    });
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
        tester
            .widget<WhotEffectStage>(find.byType(WhotEffectStage).first)
            .reduced,
        isTrue);
    expect(tester.takeException(), isNull);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture-whot')));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${Directory.systemTemp.path}/whot-effects-phone.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('every finisher renders and disposes without changing gameplay',
      (tester) async {
    for (final effect in whotFinishers.keys) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: WhotEffectStage(
        key: ValueKey(effect),
        moment: {'id': effect, 'kind': 'finish', 'effect': effect},
        seats: const {},
        reduced: false,
        child: const SizedBox.expand(),
      ))));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('whot-effect-finish')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets('reduced-motion dealing reveals the authoritative hand immediately', (tester) async {
    final socket = await open(tester, reduced: true, state: {
      'phase': 'Deal', 'yourHand': <String>[], 'handSizes': {'me': 0, 'other': 0}, 'topCard': '',
    });
    socket.snapshot({'phase': 'Turn', 'yourHand': ['circle-3', 'triangle-5', 'square-4'],
      'handSizes': {'me': 3, 'other': 3}, 'topCard': 'circle-7'});
    await tester.pump(); await tester.pump();
    expect(find.text('Waiting for your cards'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a final Tell interception stays visible before the result dialog', (tester) async {
    final socket = await open(tester, state: {'mode': 'tell', 'yourTeam': 0,
      'players': ['me', 'partner', 'other', 'rival'], 'teams': [['me', 'partner'], ['other', 'rival']]});
    socket.snapshot({'stateSeq': 12, 'phase': 'Results', 'mode': 'tell', 'yourTeam': 0, 'winner': 'other', 'winnerTeam': 1,
      'players': ['me', 'partner', 'other', 'rival'], 'teams': [['me', 'partner'], ['other', 'rival']],
      'handSizes': {'me': 3, 'partner': 3, 'other': 3, 'rival': 3}});
    await tester.pump(); await tester.pump();
    event(socket, 11, 'BUZZ_RESOLVED', {'correct': true, 'interception': true, 'by': 'other', 'team': 1, 'signalId': 10});
    await tester.pump(); await tester.pump();
    expect(find.byKey(const ValueKey('whot-effect-stolen')), findsOneWidget);
    expect(find.byKey(const ValueKey('whot-game-over-dialog')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1200)); await tester.pump();
    expect(find.byKey(const ValueKey('whot-game-over-dialog')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

}
