import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/features/monopoly/monopoly_board.dart';
import 'package:truearena/features/monopoly/monopoly_table.dart';
import 'package:truearena/widgets/table_chat.dart';

Map<String, dynamic> snapshot() =>
    (jsonDecode(File('test/fixtures/monopoly.json').readAsStringSync()) as Map)
        .cast<String, dynamic>();
void main() {
  setUpAll(() async {
    final fonts = FontLoader('MonopolySans');
    for (final name in ['Regular', 'Bold', 'Black']) {
      fonts.addFont(rootBundle.load('assets/fonts/monopoly/Roboto-$name.ttf'));
    }
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  test('all forty spaces have disjoint touch areas inside the board', () {
    final rects = [for (int i = 0; i < 40; i++) monopolySpaceRect(i, 390)];
    for (int i = 0; i < 40; i++) {
      expect(const Rect.fromLTWH(0, 0, 390, 390).contains(rects[i].center),
          isTrue);
      for (int j = i + 1; j < 40; j++) {
        expect(
            rects[i].intersect(rects[j]).width <= 0.00001 ||
                rects[i].intersect(rects[j]).height <= 0.00001,
            isTrue,
            reason: '$i / $j');
      }
    }
  });
  Future<void> pumpTable(WidgetTester tester,
      {Size size = const Size(390, 844),
      bool spectator = false,
      bool connected = true,
      Map<String, dynamic>? state,
      void Function(String, Map<String, dynamic>)? onAction,
      TextEditingController? input}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = input ?? TextEditingController();
    if (input == null) addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            fontFamily: 'MonopolySans',
            useMaterial3: true,
            extensions: const [
              NeonColors.dark,
              NeonDesign(NeonDesignKind.cabinet)
            ]),
        home: Scaffold(
            body: RepaintBoundary(
                key: const Key('capture'),
                child: MonopolyTable(
                  state: state ?? snapshot(),
                  selfId: 'ada',
                  names: const {
                    'eric': 'Eric',
                    'ada': 'Ada',
                    'chidi': 'Chidi',
                    'sarah': 'Sarah'
                  },
                  huudName: 'Eric’s Huud',
                  watching: 12,
                  seconds: 146,
                  connected: connected,
                  spectating: spectator,
                  onAction: onAction ?? (_, __) {},
                  onBack: () {},
                  onProperties: () {},
                  onTrade: () {},
                  chatController: controller,
                  messages: const [
                    (who: 'Eric', text: 'Who is buying the next street?'),
                    (who: 'Sarah', text: 'I’m coming for that green set!')
                  ],
                  onSendChat: () {},
                  voice: const Icon(Icons.mic_rounded, color: monopolyGold),
                )))));
    await tester.runAsync(() async {
      final context = tester.element(find.byType(MonopolyTable));
      await precacheImage(
          const AssetImage('assets/images/monopoly/walnut.png'), context);
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
      'purchase buttons act only for the selected player and chat remains visible',
      (tester) async {
    final actions = <String>[];
    await pumpTable(tester, onAction: (a, _) => actions.add(a));
    expect(find.text('ILLINOIS AVENUE'), findsOneWidget);
    await tester.tap(find.text('Buy \$240'));
    expect(actions, ['BUY']);
    final board = tester.getRect(find.byType(MonopolyBoard));
    expect(board.width, greaterThanOrEqualTo(380));
    expect(board.bottom, lessThan(844));
    expect(find.text('YOUR TURN'), findsNothing);
    expect(find.byType(TableChatPanel), findsOneWidget);
    expect(find.byKey(const Key('monopoly-chat-input')), findsNothing);
    expect(tester.getSize(find.byType(TableChatPanel)).height, lessThan(60));
    expect(tester.takeException(), isNull);
    const path = String.fromEnvironment('MONOPOLY_CAPTURE');
    if (path.isNotEmpty) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('capture')));
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(path).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
  testWidgets('chat opens and minimises using the shared panel',
      (tester) async {
    await pumpTable(tester);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('monopoly-chat-input')), findsOneWidget);
    expect(find.byTooltip('Send to Huud chat'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('monopoly-chat-input')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('spectators can watch but cannot buy or trade', (tester) async {
    await pumpTable(tester, spectator: true);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Buy \$240'))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('Game settings'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<PopupMenuItem<String>>(
                find.widgetWithText(PopupMenuItem<String>, 'Trade'))
            .enabled,
        isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('saved offline board is visible with game actions disabled',
      (tester) async {
    await pumpTable(tester, connected: false);
    expect(find.text('OFFLINE • saved board'), findsOneWidget);
    expect(find.byType(MonopolyBoard), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Buy \$240'))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrow phone and large text keep chat usable without overflow',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpTable(tester, size: const Size(320, 568));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('monopoly-chat-input')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byKey(const Key('monopoly-chat-input')));
    expect(rect.bottom, lessThanOrEqualTo(568));
  });
  testWidgets('keyboard lifts the chat composer while the board can scroll',
      (tester) async {
    await pumpTable(tester);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const Key('monopoly-chat-input')));
    expect(rect.bottom, lessThanOrEqualTo(544));
    expect(tester.takeException(), isNull);
  });
  testWidgets('auction and debt render the appropriate controls',
      (tester) async {
    final state = snapshot()
      ..['phase'] = 'Auction'
      ..['auction'] = {'property': 24, 'bid': 30, 'bidder': 'eric'};
    await pumpTable(tester, state: state);
    expect(find.text('Place bid'), findsOneWidget);
    expect(find.text('Pass'), findsOneWidget);
    final debt = snapshot()
      ..['phase'] = 'Debt'
      ..['message'] = 'Rent — \$500 due';
    await pumpTable(tester, state: debt);
    expect(find.text('Raise cash'), findsOneWidget);
    expect(find.text('Pay now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  Future<ValueNotifier<Map<String, dynamic>>> liveBoard(
      WidgetTester tester) async {
    final state = ValueNotifier(snapshot());
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 390,
                    child: RepaintBoundary(
                        key: const Key('landing-capture'),
                        child: ValueListenableBuilder<Map<String, dynamic>>(
                            valueListenable: state,
                            builder: (_, value, __) => MonopolyBoard(
                                state: value, onSpace: (_) {}))))))));
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets(
      'dice settle before movement and the landing lens lasts three seconds',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final state = await liveBoard(tester);
    final next = snapshot()
      ..['dice'] = [5, 2]
      ..['round'] = 2;
    (next['playerState'] as Map)['eric']['position'] = 7;
    state.value = next;
    await tester.pump();
    expect(find.byKey(const Key('monopoly-dice-rolling')), findsOneWidget);
    expect(find.byKey(const Key('monopoly-landing-magnifier')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byKey(const Key('monopoly-dice-rolling')), findsNothing);
    expect(find.bySemanticsLabel('Dice result: 5 and 2'), findsOneWidget);
    expect(find.byKey(const Key('monopoly-landing-magnifier')), findsNothing);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const Key('monopoly-landing-magnifier')), findsOneWidget);
    expect(find.bySemanticsLabel('Landed on Chance'), findsOneWidget);
    const path = String.fromEnvironment('MONOPOLY_LANDING_CAPTURE');
    if (path.isNotEmpty) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('landing-capture')));
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(path).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pump(const Duration(milliseconds: 2999));
    expect(find.byKey(const Key('monopoly-landing-magnifier')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2));
    expect(find.byKey(const Key('monopoly-landing-magnifier')), findsNothing);
    expect(next['dice'], [5, 2],
        reason: 'animation never changes authoritative dice');
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cash-only updates do not replay dice or magnify a landing',
      (tester) async {
    final state = await liveBoard(tester);
    final next = snapshot()..['round'] = 2;
    (next['playerState'] as Map)['eric']['cash'] = 1400;
    state.value = next;
    await tester.pump();
    expect(find.byKey(const Key('monopoly-dice-rolling')), findsNothing);
    expect(find.byKey(const Key('monopoly-landing-magnifier')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a roll event animates repeated dice without a position change',
      (tester) async {
    final sequence = ValueNotifier(0);
    addTearDown(sequence.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 390,
                    child: ValueListenableBuilder<int>(
                        valueListenable: sequence,
                        builder: (_, value, __) => MonopolyBoard(
                            state: snapshot(),
                            onSpace: (_) {},
                            rollSequence: value,
                            rolledDice: const [3, 4])))))));
    await tester.pumpAndSettle();
    sequence.value++;
    await tester.pump();
    expect(find.byKey(const Key('monopoly-dice-rolling')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byKey(const Key('monopoly-dice-rolling')), findsNothing);
    expect(find.byKey(const Key('monopoly-landing-magnifier')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
