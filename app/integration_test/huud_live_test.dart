import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:truearena/app.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';

/// Your Huud stays; going Live is the hangout. Walks the Huud tab, Go Live,
/// End Live and a Huud you're a member of, in dark then light, and saves
/// screenshots (the nav icons are in every one).
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/huud_live_test.dart \
///     --dart-define=API_BASE=http://localhost:8091 -d <simulator>
///
/// Expects `eric@huud.test` owning an offline Huud with members and chat,
/// a member of a friend's Live Huud and of an offline one he muted.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> wait(WidgetTester tester, [int ms = 1500]) async {
    for (var waited = 0; waited < ms; waited += 100) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await wait(tester, 900);
    await binding.takeScreenshot(name);
  }

  Future<void> tapWhenThere(WidgetTester tester, Finder finder, {int tries = 40}) async {
    for (var i = 0; i < tries && finder.evaluate().isEmpty; i++) {
      await wait(tester, 250);
    }
    await tester.tap(finder.first, warnIfMissed: false);
    await wait(tester, 1200);
  }

  Finder keyed(bool Function(String key) test) => find.byWidgetPredicate((w) {
        final key = w.key;
        return key is ValueKey<String> && test(key.value);
      });

  testWidgets('Your Huud: offline, Go Live, End Live', (tester) async {
    const base = '${ApiClient.base}/api/v1';
    await http.post(Uri.parse('$base/auth/otp/request'),
        headers: {'content-type': 'application/json'}, body: jsonEncode({'email': 'eric@huud.test'}));
    final verified = jsonDecode((await http.post(Uri.parse('$base/auth/otp/verify'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'email': 'eric@huud.test', 'code': '000000'})))
        .body) as Map<String, dynamic>;
    const secure = FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device));
    await secure.write(key: 'ta_access', value: verified['accessToken'] as String);
    await secure.write(key: 'ta_refresh', value: verified['refreshToken'] as String);

    final state = AppState(ApiClient());
    await state.bootstrap();
    await state.setThemeMode(ThemeMode.dark);
    await tester.pumpWidget(TrueArenaApp(state: state));
    await wait(tester, 4000);

    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Live')));
    await shot(tester, 'p01_live_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Huud')));
    await shot(tester, 'p02_huud_tab_dark');
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -500));
    await shot(tester, 'p03_huuds_youre_in_dark');
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 500));
    await wait(tester, 600);

    // Your Huud, offline → Go Live
    await tapWhenThere(tester, keyed((k) => k.startsWith('huud-open-')));
    await shot(tester, 'p04_offline_owner_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-go-live')));
    await shot(tester, 'p05_go_live_sheet_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('golive-online')));
    await tapWhenThere(tester, find.byKey(const ValueKey('golive-confirm')));
    await wait(tester, 1500);
    await shot(tester, 'p06_live_owner_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-end')));
    await shot(tester, 'p07_end_live_confirm_dark');
    await tapWhenThere(tester, find.text('End Live').last);
    await wait(tester, 1500);
    await shot(tester, 'p08_after_end_live_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-back')));

    // ----- Light
    await state.setThemeMode(ThemeMode.light);
    await wait(tester, 800);
    await shot(tester, 'p09_huud_tab_light');
    // A Huud you're a member of that's offline (muted) → the bell
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -500));
    await wait(tester, 600);
    await tapWhenThere(tester, keyed((k) => k.startsWith('member-huud-')).last);
    await shot(tester, 'p10_offline_member_light');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-back')));
    // Back to the top so the tab bar shows again.
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 600));
    await wait(tester, 800);
    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Live')));
    await shot(tester, 'p11_live_light');
    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Friends')));
    await shot(tester, 'p12_friends_light');
    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Games')));
    await shot(tester, 'p13_games_light');
  });
}
