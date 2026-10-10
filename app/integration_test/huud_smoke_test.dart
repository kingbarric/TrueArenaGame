import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:truearena/app.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';

/// Walks Live, Huud, Games and Friends on a real device against a local
/// backend (local profile, so `000000` signs in) and saves screenshots.
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/huud_smoke_test.dart \
///     --dart-define=API_BASE=http://localhost:8091 \
///     --dart-define=SMOKE_PRIVATE_CODE=<code of someone else's private Huud> -d <simulator>
///
/// Expects `eric@huud.test` hosting a shared public Huud with a pending play
/// request and some chat (see docs/HUUD_SPACES.md).
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

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 80));
    await wait(tester);
  }

  testWidgets('Live, Huud, Games and Friends', (tester) async {
    const email = String.fromEnvironment('SMOKE_EMAIL', defaultValue: 'eric@huud.test');
    const privateCode = String.fromEnvironment('SMOKE_PRIVATE_CODE');
    const base = '${ApiClient.base}/api/v1';
    await http.post(Uri.parse('$base/auth/otp/request'),
        headers: {'content-type': 'application/json'}, body: jsonEncode({'email': email}));
    final verified = jsonDecode((await http.post(Uri.parse('$base/auth/otp/verify'),
            headers: {'content-type': 'application/json'}, body: jsonEncode({'email': email, 'code': '000000'})))
        .body) as Map<String, dynamic>;
    const secure = FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device));
    await secure.write(key: 'ta_access', value: verified['accessToken'] as String);
    await secure.write(key: 'ta_refresh', value: verified['refreshToken'] as String);

    final state = AppState(ApiClient());
    await state.bootstrap();
    await state.setThemeMode(ThemeMode.dark);
    await tester.pumpWidget(TrueArenaApp(state: state));
    await wait(tester, 4000);

    // ----- Live (first tab)
    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Live')));
    await shot(tester, '01_live_now_dark');
    // Tap a live Huud → full-screen watching, swipe up for the next.
    await tapWhenThere(tester, find.textContaining('Ludo Party'));
    await shot(tester, '01b_swipe_watch_dark');
    await tester.fling(find.byKey(const ValueKey('huud-swipe')), const Offset(0, -500), 1500);
    await wait(tester, 2000);
    await shot(tester, '01c_swipe_next_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('swipe-close')));
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-tab-friends')));
    await shot(tester, '02_feed_shared_huud_dark');
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -700));
    await shot(tester, '02b_feed_posts_dark');
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 700));
    await wait(tester, 600);

    // ----- Huud tab → inside as host
    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Huud')));
    await shot(tester, '03_huud_tab_dark');
    await tapWhenThere(tester, keyed((k) => k.startsWith('huud-go-in-')));
    await shot(tester, '04_host_asking_dark');
    await tapWhenThere(tester, keyed((k) => k.startsWith('answer-play-') && k.endsWith('-yes')));
    await shot(tester, '05_after_yes_dark');
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -450));
    await shot(tester, '06_game_seats_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-tab-chat')));
    await shot(tester, '07_chat_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-tab-people')));
    await shot(tester, '08_people_dark');
    await tapWhenThere(tester, keyed((k) => k.startsWith('huud-person-')).last);
    await shot(tester, '09_person_sheet_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('person-safety')));
    await tapWhenThere(tester, find.byKey(const ValueKey('safety-report')));
    await tapWhenThere(tester, find.byKey(const ValueKey('safety-reason-unsafe')));
    await shot(tester, '10_report_dark');
    await closeSheet(tester);
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-back')));

    // ----- Games tab: a game tap goes through your Huud
    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Games')));
    await shot(tester, '11_games_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('home-game-chess')));
    await shot(tester, '12_games_tap_opens_huud_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-back')));

    // ----- Friends (retry: the tap can land while the last screen is still closing)
    for (var i = 0; i < 5 && find.byKey(const ValueKey('friends-tab-requests')).hitTestable().evaluate().isEmpty; i++) {
      await tapWhenThere(tester, find.byKey(const ValueKey('nav-Friends')));
    }
    await shot(tester, '13_friends_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('friends-tab-requests')));
    await shot(tester, '14_requests_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('friends-tab-messages')));
    await shot(tester, '15_messages_dark');

    // ----- Light: a private Huud by code → ask → wait
    await state.setThemeMode(ThemeMode.light);
    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Huud')));
    if (privateCode.isNotEmpty) {
      await tester.enterText(find.byKey(const ValueKey('huud-code-input')), privateCode);
      await wait(tester, 500);
      await tapWhenThere(tester, find.byKey(const ValueKey('huud-code-join')));
      await shot(tester, '16_private_waiting_light');
      await tapWhenThere(tester, find.byKey(const ValueKey('huud-back')));
    }
    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Live')));
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-tab-friends')));
    await shot(tester, '17_feed_light');

    // ----- End Live: the Huud stays; a game tap asks to Go Live again
    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Huud')));
    await tapWhenThere(tester, keyed((k) => k.startsWith('huud-go-in-')));
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-end')));
    await tapWhenThere(tester, find.text('End Live').last);
    await shot(tester, '18_after_end_live_light');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-back')));
    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Games')));
    await tapWhenThere(tester, find.byKey(const ValueKey('home-game-chess')));
    await shot(tester, '19_game_asks_go_live_light');
  });
}
