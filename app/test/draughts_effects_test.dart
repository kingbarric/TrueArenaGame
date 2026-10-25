import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:truearena/core/game_music.dart';
import 'package:truearena/core/game_sfx.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/game_socket.dart';
import 'package:truearena/features/draughts/draughts_effects.dart';
import 'package:truearena/features/draughts/draughts_game_screen.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/neon.dart' show Presence;
import 'package:truearena/widgets/spectator_reactions.dart';

class _Socket implements GameSocket {
  final frames = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final sent = <Map<String, dynamic>>[];
  @override
  final awaySince = <String, DateTime>{};
  @override
  final memberAvatars = <String, String?>{};
  @override
  final onlinePlayers = ValueNotifier(<String>{'a', 'b'});
  @override
  Presence presenceOf(String id) => Presence.here;
  @override
  bool get isConnected => true;
  @override
  int get lastSeq => 0;
  @override
  String get roomId => 'room';
  @override
  Stream<Map<String, dynamic>> get envelopes => frames.stream;
  @override
  void send(String type, [Map<String, dynamic>? payload]) =>
      sent.add({'type': type, 'payload': payload});
  @override
  Future<void> close() => frames.close();
  void emit(String type, Map<String, dynamic> data) =>
      frames.add({'type': type, 'payload': data});
  void event(String type, Map<String, dynamic> data, [int? seq]) =>
      emit('EVENT', {'type': type, 'data': data, if (seq != null) 'seq': seq});
}

void main() {
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await GameMusic.setEnabled(false);
    await GameSfx.setEnabled(false);
  });
  testWidgets(
      'a burst of captures preserves the combo and king-down before the random finisher',
      (t) async {
    final effects = DraughtsEffects()..synchronize(10);
    effects.event(
        'PIECE_CAPTURED', {'from': 20, 'to': 31, 'capturedKing': true}, 11);
    effects.event('PIECE_CAPTURED', {'from': 31, 'to': 42}, 12);
    effects.event('PIECE_CAPTURED', {'from': 42, 'to': 33}, 13);
    effects.event('PIECE_PROMOTED', {'square': 33}, 14);
    effects.event('GAME_OVER',
        {'winningSide': 'A', 'reason': 'capture', 'finishEffect': 'fire'}, 15);
    expect(effects.current!.title, 'KING DOWN');
    expect(effects.holdFinalBoard, isTrue);
    await t.pump(const Duration(milliseconds: 400));
    expect(effects.current!.title, 'TRIPLE TAKE');
    expect(effects.current!.trail, [20, 31, 42, 33]);
    await t.pump(const Duration(milliseconds: 400));
    expect(effects.current!.title, 'KING ME');
    await t.pump(const Duration(milliseconds: 700));
    expect(effects.current!.title, 'FINAL TAKE');
    await t.pump(const Duration(milliseconds: 550));
    expect(effects.current!.kind, 'finish');
    expect(effects.current!.effect, 'fire');
    expect(effects.holdFinalBoard, isFalse);
    await t.pump(const Duration(milliseconds: 1400));
    expect(effects.current, isNull);
    effects.dispose();
  });
  testWidgets(
      'snapshots duplicates undo VAR and draws never replay celebrations',
      (t) async {
    final effects = DraughtsEffects();
    effects.event('PIECE_PROMOTED', {'square': 45}, 1);
    expect(effects.current, isNull);
    effects.synchronize(10);
    effects.event('PIECE_PROMOTED', {'square': 45}, 9);
    expect(effects.current, isNull);
    effects.event('PIECE_PROMOTED', {'square': 45}, 11);
    final id = effects.current!.id;
    effects.event('PIECE_PROMOTED', {'square': 45}, 11);
    expect(effects.current!.id, id);
    effects.event('UNDO_ACCEPTED', {}, 12);
    expect(effects.current, isNull);
    effects.event('PIECE_PROMOTED', {'square': 45}, 13, muted: true);
    expect(effects.current, isNull);
    effects.event('GAME_OVER', {'winningSide': 'draw'}, 14);
    expect(effects.current, isNull);
    effects.suspend();
    effects.event(
        'GAME_OVER', {'winningSide': 'A', 'finishEffect': 'neon'}, 15);
    effects.synchronize(15);
    expect(effects.current, isNull);
    effects.dispose();
  });
  testWidgets('a capture after reconnect uses the server chain count',
      (t) async {
    final effects = DraughtsEffects()..synchronize(25);
    effects.event(
        'PIECE_CAPTURED', {'from': 20, 'to': 31, 'captureCount': 4}, 26);
    expect(effects.current!.title, 'BOARD SWEEP ×4');
    effects.dispose();
  });
  testWidgets(
      'queued captures from different turns never merge their king-down status',
      (t) async {
    final effects = DraughtsEffects()..synchronize(0);
    effects.event('PIECE_CAPTURED', {'from': 20, 'to': 31}, 1);
    effects.event(
        'PIECE_CAPTURED', {'from': 31, 'to': 42, 'capturedKing': true}, 2);
    effects.event('TURN_STARTED', {'side': 'B'}, 3);
    effects.event('PIECE_CAPTURED', {'from': 45, 'to': 34}, 4);
    await t.pump(const Duration(milliseconds: 400));
    expect(effects.current!.king, isTrue);
    await t.pump(const Duration(milliseconds: 400));
    expect(effects.current!.king, isFalse);
    expect(effects.current!.count, 1);
    effects.dispose();
  });
  testWidgets('reaction floods are bounded deduplicated and expire', (t) async {
    final reactions = SpectatorReactions();
    final sent = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 20; i++) {
      reactions.receive({'id': '$i', 'emoji': '🔥', 'sentAtMs': sent});
    }
    expect(reactions.visible, hasLength(8));
    reactions.receive({'id': '19', 'emoji': '🔥', 'sentAtMs': sent});
    reactions.receive({'id': 'old', 'emoji': '🔥', 'sentAtMs': sent - 5000});
    expect(reactions.visible, hasLength(8));
    await t.pump(const Duration(milliseconds: 2400));
    expect(reactions.visible, isEmpty);
    reactions.dispose();
  });

  Future<_Socket> open(WidgetTester t,
      {bool spectator = false, bool reduced = false}) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final socket = _Socket();
    final app = AppState(
        ApiClient(client: MockClient((_) async => http.Response('{}', 200))));
    addTearDown(app.dispose);
    await t.pumpWidget(AppScope(
        state: app,
        child: MaterialApp(
            theme: NeonTheme.dark,
            builder: (context, child) => MediaQuery(
                data:
                    MediaQuery.of(context).copyWith(disableAnimations: reduced),
                child: child!),
            home: RepaintBoundary(
                key: const ValueKey('draughts-preview'),
                child: DraughtsGameScreen(
                    socket: socket,
                    selfId: spectator ? 'viewer' : 'a',
                    spectating: spectator,
                    nicknames: const {'a': 'Ada', 'b': 'Eric'})))));
    socket.emit('SNAPSHOT', {
      'lobby': false,
      'phase': 'TurnA',
      'round': 1,
      'seq': 10,
      'playerA': 'a',
      'playerB': 'b',
      'turnSeconds': 0,
      'board': List<String?>.filled(50, null)
        ..[20] = 'A_MAN'
        ..[25] = 'B_KING'
        ..[45] = 'B_MAN'
    });
    await t.pump();
    return socket;
  }

  testWidgets(
      'spectator reactions stay outside the board and honour cooldown and mute',
      (t) async {
    final socket = await open(t, spectator: true);
    final board = t.getRect(find.byKey(const ValueKey('draughts-board-area')));
    final left =
        t.getRect(find.byKey(const ValueKey('draughts-reactions-left')));
    final right =
        t.getRect(find.byKey(const ValueKey('draughts-reactions-right')));
    expect(left.right, lessThanOrEqualTo(board.left));
    expect(right.left, greaterThanOrEqualTo(board.right));
    await t.tap(find.byKey(const ValueKey('draughts-react-🔥')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('draughts-react-🔥')));
    expect(
        socket.sent.where((e) => e['type'] == 'REACTION_SEND'), hasLength(1));
    socket.event('SPECTATOR_REACTION', {
      'id': 'r1',
      'emoji': '🔥',
      'sentAtMs': DateTime.now().millisecondsSinceEpoch
    });
    await t.pump();
    expect(find.byKey(const ValueKey('reaction-r1')), findsOneWidget);
    socket.event('SPECTATORS_MUTED', {});
    await t.pump();
    expect(find.byKey(const ValueKey('reaction-r1')), findsNothing);
    expect(find.byKey(const ValueKey('draughts-react-🔥')), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'confirmed effects render with reduced motion and never add a finish picker',
      (t) async {
    final socket = await open(t, reduced: true);
    socket.event(
        'PIECE_CAPTURED',
        {
          'from': 20,
          'to': 31,
          'captured': 25,
          'side': 'A',
          'capturedKing': true
        },
        11);
    await t.pump();
    expect(
        find.byKey(const ValueKey('draughts-effect-capture')), findsOneWidget);
    await t.pump(const Duration(milliseconds: 450));
    socket.event('PIECE_PROMOTED', {'square': 31, 'side': 'A'}, 12);
    await t.pump();
    expect(find.byKey(const ValueKey('draughts-effect-crown')), findsOneWidget);
    socket.event(
        'GAME_OVER',
        {'winningSide': 'A', 'reason': 'blocked', 'finishEffect': 'confetti'},
        13);
    socket.emit('PHASE', {'phase': 'Results', 'round': 1});
    await t.pump();
    await t.pump(const Duration(milliseconds: 700));
    expect(
        find.byKey(const ValueKey('draughts-effect-decisive')), findsOneWidget);
    await t.pump(const Duration(milliseconds: 550));
    expect(
        find.byKey(const ValueKey('draughts-effect-finish')), findsOneWidget);
    expect(find.textContaining('Choose'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  for (final effect in draughtsFinishers) {
    testWidgets('$effect celebration keeps underlying controls tappable',
        (t) async {
      final effects = DraughtsEffects()..synchronize(0);
      effects.event(
          'GAME_OVER', {'winningSide': 'A', 'finishEffect': effect}, 1);
      var taps = 0;
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: DraughtsEffectStage(
        effects: effects,
        finishOnly: true,
        child: Center(
            child: TextButton(
                onPressed: () => taps++, child: const Text('Continue'))),
      ))));
      await t.pump(const Duration(milliseconds: 200));
      expect(
          find.byKey(const ValueKey('draughts-effect-finish')), findsOneWidget);
      await t.tap(find.text('Continue'));
      expect(taps, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      effects.dispose();
    });
  }

  testWidgets(
      'full-motion phone preview shows capture and crown effects without overflow',
      (t) async {
    if (const bool.fromEnvironment('CAPTURE_DRAUGHTS_EFFECTS')) {
      await t.runAsync(() async {
        final fontFile = File('assets/fonts/monopoly/Roboto-Regular.ttf');
        for (final name in {
          'Roboto',
          'Archivo',
          'Baloo2',
          'Baloo 2',
          NeonTheme.dark.textTheme.bodyMedium!.fontFamily!,
          NeonTheme.dark.textTheme.titleLarge!.fontFamily!
        }) {
          final loader = FontLoader(name)
            ..addFont(fontFile.readAsBytes().then(ByteData.sublistView));
          await loader.load();
        }
        final icons = File(
            '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
        if (icons.existsSync()) {
          await (FontLoader('MaterialIcons')
                ..addFont(icons.readAsBytes().then(ByteData.sublistView)))
              .load();
        }
      });
    }
    final socket = await open(t);
    socket.event(
        'PIECE_CAPTURED',
        {
          'from': 20,
          'to': 31,
          'captured': 25,
          'side': 'A',
          'capturedKing': true
        },
        11);
    await t.pump();
    await t.pump(const Duration(milliseconds: 160));
    Future<void> capture(String name) async {
      if (!const bool.fromEnvironment('CAPTURE_DRAUGHTS_EFFECTS')) return;
      final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('draughts-preview')));
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../output/draughts-effects-validation/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('king-down');
    await t.pump(const Duration(milliseconds: 400));
    socket.event('PIECE_PROMOTED', {'square': 31, 'side': 'A'}, 12);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    await capture('king-me');
    expect(find.byKey(const ValueKey('draughts-effect-crown')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
