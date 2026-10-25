// Drives the SlayHuud preview on a simulator like a player would. Each step
// prints a SLAYSHOT marker and pauses so a host script can take a real
// screenshot (WebView included):
//   flutter test integration_test/slay_tour_test.dart -d <simulator>
//     --dart-define=API_BASE=http://localhost:55667
//     --dart-define=SLAY_ASSET_BASE=http://localhost:8932/
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:truearena/features/slayhuud/slay_theme.dart';
import 'package:truearena/slayhuud_preview.dart' as preview;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SlayHuud career tour', (t) async {
    Future<void> wait(int seconds) async {
      for (int i = 0; i < seconds * 4; i++) {
        await t.pump(const Duration(milliseconds: 250));
      }
    }

    Future<void> shot(String name, {int settle = 6}) async {
      await wait(settle);
      debugPrint('SLAYSHOT:$name');
      await wait(4);
    }

    Future<void> tap(Finder finder) async {
      await t.ensureVisible(finder.first);
      await t.tap(finder.first);
      await wait(1);
    }

    await preview.main();
    await shot('01-hub', settle: 10);
    await tap(find.text('My Career'));
    await shot('02-picker-amara', settle: 10);
    for (final name in ['03-picker-kofi', '04-picker-zuri', '05-picker-tayo']) {
      await tap(find.byIcon(Icons.chevron_right_rounded));
      await shot(name, settle: 10);
    }
    await tap(find.text('This is my star'));
    await tap(find.text('That’s my star!'));
    await shot('06-career-home');
    await tap(find.text('NEXT UP'));
    await shot('07-invite', settle: 2);
    await tap(find.text('Let’s slay!'));
    await shot('08-studio', settle: 12);
    for (final (tab, item, name) in [
      ('👕 Shirts', 'Logo Tee', '09-shirt'),
      ('👖 Trousers', 'Classic Jeans', '10-jeans'),
      ('👠 Shoes', 'Street Sneakers', '11-sneakers'),
    ]) {
      final tabFinder = find.text(tab);
      final tabRow = find.ancestor(
          of: find.byWidgetPredicate((w) => w is SlayTab && !w.pill).first,
          matching: find.byType(ListView));
      for (int i = 0; i < 10 && tabFinder.evaluate().isEmpty; i++) {
        await t.drag(tabRow, const Offset(-150, 0));
        await wait(1);
      }
      await tap(tabFinder);
      await tap(find.text(item));
      await shot(name, settle: 8);
    }
  });
}
