import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:truearena/app.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/hangout_state.dart';
import 'package:truearena/features/huudspace/huud_voice.dart';

/// Opens Eric's Huud, goes Live, and taps the mic: it should go from
/// "Muted" to "Talking" without leaving the Huud (grant the simulator's
/// microphone first: `xcrun simctl privacy <sim> grant microphone app.truearena.truearena`).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> wait(WidgetTester tester, [int ms = 1500]) async {
    for (var waited = 0; waited < ms; waited += 100) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
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

  testWidgets('the Huud mic unmutes in place', (tester) async {
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

    await tapWhenThere(tester, find.byKey(const ValueKey('nav-Huud')));
    await tapWhenThere(tester, keyed((k) => k.startsWith('huud-open-')));
    await tapWhenThere(tester, find.byKey(const ValueKey('huud-go-live')));
    await tapWhenThere(tester, find.byKey(const ValueKey('golive-none')));
    await tapWhenThere(tester, find.byKey(const ValueKey('golive-confirm')));
    await wait(tester, 5000);
    debugPrint('MIC before: in=${HangoutState.instance.roomName} muted=${HangoutState.instance.muted}');
    await binding.takeScreenshot('m1_muted');
    debugPrint('MIC finder: ${find.byKey(const ValueKey('huud-talk')).evaluate().length} '
        'hittable=${find.byKey(const ValueKey('huud-talk')).hitTestable().evaluate().length} canSpeak=${HuudVoice.instance.canSpeak}');
    final direct = await HuudVoice.instance.setMuted(false);
    debugPrint('MIC direct setMuted(false) → $direct');
    await wait(tester, 4000);
    debugPrint('MIC after: in=${HangoutState.instance.roomName} muted=${HangoutState.instance.muted}');
    await binding.takeScreenshot('m2_after_tap');
    expect(HangoutState.instance.muted, isFalse);
    expect(find.text('Talking'), findsOneWidget);
  });
}
