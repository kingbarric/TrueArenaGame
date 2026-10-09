import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:truearena/app.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';

/// Walks the Live and Huud tabs on a real device against a local backend
/// (local profile, so `000000` signs in) and saves screenshots along the way.
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/huud_smoke_test.dart \
///     --dart-define=API_BASE=http://localhost:8091 \
///     --dart-define=SMOKE_EMAIL=eric@huud.test -d <simulator>
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

  testWidgets('Live and Huud tabs', (tester) async {
    const email = String.fromEnvironment('SMOKE_EMAIL', defaultValue: 'eric@huud.test');
    const base = '${ApiClient.base}/api/v1';
    await http.post(Uri.parse('$base/auth/otp/request'),
        headers: {'content-type': 'application/json'}, body: jsonEncode({'email': email}));
    final verified = jsonDecode((await http.post(Uri.parse('$base/auth/otp/verify'),
            headers: {'content-type': 'application/json'}, body: jsonEncode({'email': email, 'code': '000000'})))
        .body) as Map<String, dynamic>;
    const secure = FlutterSecureStorage(
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device));
    await secure.write(key: 'ta_access', value: verified['accessToken'] as String);
    await secure.write(key: 'ta_refresh', value: verified['refreshToken'] as String);

    final state = AppState(ApiClient());
    await state.bootstrap();
    await state.setThemeMode(ThemeMode.dark);
    await tester.pumpWidget(TrueArenaApp(state: state));
    await wait(tester, 4000);
    await binding.convertFlutterSurfaceToImage().catchError((Object _) {});

    // ----- Huud tab (dark)
    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Huud')));
    await shot(tester, '01_huud_tab_dark');
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -500));
    await shot(tester, '02_huud_history_dark');
    await tapWhenThere(tester, find.text('Saturday Whot'));
    await shot(tester, '03_history_detail_dark');
    await tester.tapAt(const Offset(20, 60)); // close the sheet
    await wait(tester);
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 800));
    await wait(tester);

    // ----- Make a Huud
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-make')));
    await shot(tester, '04_create_sheet_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-create')));
    await wait(tester, 2000);
    await shot(tester, '05_inside_host_dark');
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -500));
    await shot(tester, '06_inside_games_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-tab-people')));
    await shot(tester, '07_inside_people_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-leave')));
    await shot(tester, '08_leave_confirm_dark');
    await tapWhenThere(tester, find.text('No, stay'));
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-back')));
    await wait(tester, 1500);
    await shot(tester, '09_huud_tab_hosting_dark');

    // ----- Live tab (dark)
    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Live')));
    await shot(tester, '10_live_now_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-tab-friends')));
    await shot(tester, '11_feed_friends_dark');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-tab-live')));

    // ----- Light theme
    await state.setThemeMode(ThemeMode.light);
    await wait(tester, 1200);
    await shot(tester, '12_live_now_light');
    await tapWhenThere(tester, find.textContaining('Zara'));
    await shot(tester, '13_peek_light');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-join')));
    await wait(tester, 1500);
    await shot(tester, '14_inside_member_light');
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-back')));
    await wait(tester, 1200);
    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Huud')));
    await shot(tester, '15_huud_tab_light');
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -600));
    await shot(tester, '16_huud_history_light');
  });
}
