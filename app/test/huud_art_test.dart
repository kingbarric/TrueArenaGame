import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/features/huud/huud_models.dart';
import 'package:truearena/features/huudspace/huud_kit.dart';
import 'package:truearena/features/slayhuud/slay_ui.dart';
import 'package:truearena/widgets/huud_art.dart';
import 'package:truearena/widgets/neon.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test(
      'saved avatars, reactions, games and wardrobe categories all have Huud art',
      () {
    for (final token in [
      ...kAvatarPresets,
      ...huudReactionEmoji,
      ...huudGameEmoji.values,
      ...slayCategoryEmoji.values,
      '😴',
      '🔑',
      '📡',
      '✋',
      '🏆',
      '🔒',
      '🎁',
    ]) {
      expect(HuudArt.lookup(token), isNotNull, reason: token);
    }
    expect(HuudArt.lookup('❤️')!.asset, HuudArt.lookup('❤')!.asset);
    expect(kAvatarPresets.map((e) => HuudArt.lookup(e)!.asset).toSet(),
        hasLength(15));
  });

  test('all pictograms are bundled; generated artwork has an alpha channel',
      () async {
    for (final asset in HuudArt.all.map((e) => e.asset).toSet()) {
      if (asset.startsWith('huud-signal:')) continue;
      final bytes = await rootBundle.load(asset);
      expect(bytes.lengthInBytes, greaterThan(24), reason: asset);
      if (asset.contains('/huud_ui/')) {
        expect(bytes.getUint8(25), 6, reason: 'Expected RGBA PNG: $asset');
      }
    }
  });

  test('all thirty Tell signals stay visually distinct', () {
    const signals = [
      '🪐',
      '🌌',
      '☄️',
      '🌠',
      '🌑',
      '🌒',
      '🌓',
      '🌔',
      '🌕',
      '🌘',
      '🌙',
      '🌚',
      '🌝',
      '✨',
      '🔮',
      '🧿',
      '🗝️',
      '🪬',
      '🕯️',
      '🪞',
      '🪄',
      '🕳️',
      '🛸',
      '👁️',
      '🗿',
      '🧬',
      '🌀',
      '⚗️',
      '💠',
      '🧩',
    ];
    expect(signals.map((e) => HuudArt.lookup(e)!.asset).toSet(), hasLength(30));
  });

  testWidgets(
      'empty state and join key render actual Huud images with readable semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      theme: NeonTheme.light,
      home: const Scaffold(
          body: Column(children: [
        HuudFriendlyState(
          emoji: '😴',
          title: "Nobody's live right now",
          message: 'Start a Huud and invite your friends.',
        ),
        HuudText('🔑 Got a code?', style: TextStyle(fontSize: 24)),
      ])),
    ));
    await tester.pump();
    expect(find.byType(HuudSymbol), findsNWidgets(2));
    expect(find.bySemanticsLabel('Resting Huud'), findsOneWidget);
    expect(find.bySemanticsLabel('Join code Got a code?'), findsOneWidget);
    final assets = tester.widgetList<Image>(find.byType(Image)).map((image) {
      final provider = image.image;
      return (provider is ResizeImage
              ? provider.imageProvider as AssetImage
              : provider as AssetImage)
          .assetName;
    }).toSet();
    expect(
        assets,
        containsAll([
          'assets/images/huud_ui/sleep.png',
          'assets/images/huud_ui/key.png',
        ]));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('inline art wraps and scales on narrow dark and light screens',
      (tester) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final theme in [NeonTheme.light, NeonTheme.dark]) {
      for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 780), textScaler: TextScaler.linear(2)),
            child: Directionality(
              textDirection: direction,
              child: const Scaffold(
                  body: Padding(
                padding: EdgeInsets.all(16),
                child: HuudText(
                  '🏆 Your championship match is ready. ✋ Ask the host for the mic.',
                  style: TextStyle(fontSize: 18),
                ),
              )),
            ),
          ),
        ));
        await tester.pump();
        expect(find.byType(HuudSymbol), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        for (final symbol in find.byType(HuudSymbol).evaluate()) {
          final box = symbol.renderObject as RenderBox;
          expect(box.size.width, closeTo(42.48, .1));
        }
      }
    }
  });

  testWidgets('user-authored text retains its original emoji', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
      body: HuudText('Hello 😂', artwork: false),
    )));
    expect(find.byType(HuudSymbol), findsNothing);
    expect(find.text('Hello 😂'), findsOneWidget);
  });
}
