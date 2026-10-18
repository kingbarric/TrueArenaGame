import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/settings/delete_account_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('cancel never sends a deletion request', (tester) async {
    var calls = 0;
    final state = AppState(ApiClient(client: MockClient((r) async {
      calls++;
      return http.Response('{}', 200);
    })));
    await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
            theme: NeonTheme.light, home: const DeleteAccountScreen())));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Permanently delete your account?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Keep account').last);
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets('failed deletion keeps the session and allows retry',
      (tester) async {
    var deletes = 0;
    final api = ApiClient(client: MockClient((r) async {
      if (r.method == 'DELETE') {
        deletes++;
        return http.Response('{}', 503);
      }
      return http.Response(
          jsonEncode({'appleLinked': false, 'appleRevocationReady': false}),
          200);
    }));
    api.bearer = 'existing-session';
    final state = AppState(api);
    await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
            theme: NeonTheme.light, home: const DeleteAccountScreen())));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(api.bearer, 'existing-session');
    expect(find.text(userRetryMessage), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets(
      'successful guest deletion clears session and rotates device identity',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ta_device_id': 'old-device',
      'ta_access': 'old-access',
      'ta_refresh': 'old-refresh',
      'ta_avatar_image': '/old-photo',
    });
    var deletes = 0;
    final api = ApiClient(client: MockClient((r) async {
      if (r.method == 'DELETE') {
        deletes++;
        expect(jsonDecode(r.body), {'confirmed': true});
        return http.Response('', 204);
      }
      return http.Response(jsonEncode({'appleLinked': false}), 200);
    }));
    api.bearer = 'old-access';
    api.deviceId = 'old-device';
    final state = AppState(api)..identity = Identity.guest;
    await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
            theme: NeonTheme.light, home: const DeleteAccountScreen())));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(deletes, 1);
    expect(api.bearer, isNull);
    expect(state.identity, Identity.anonymous);
    expect(api.deviceId, isNot('old-device'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ta_refresh'), isNull);
    expect(prefs.getString('ta_access'), isNull);
    expect(prefs.getString('ta_avatar_image'), isNull);
    expect(find.text('Continue with email'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('Apple-linked account is kept when revocation is unavailable',
      (tester) async {
    var deletes = 0;
    final api = ApiClient(client: MockClient((r) async {
      if (r.method == 'DELETE') deletes++;
      return http.Response(
          jsonEncode({'appleLinked': true, 'appleRevocationReady': false}),
          200);
    }))
      ..bearer = 'still-signed-in';
    final state = AppState(api);
    await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
            theme: NeonTheme.light, home: const DeleteAccountScreen())));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    expect(api.bearer, 'still-signed-in');
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
