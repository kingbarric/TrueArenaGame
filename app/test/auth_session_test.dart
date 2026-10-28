import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/hangout_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/core/inbox_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'ta_device_id': 'old-device',
      'ta_access': 'old',
      'ta_refresh': 'refresh',
      'ta_cached_user': 'old',
      'ta_avatar_emoji': 'old'
    });
    HangoutState.instance.clear();
  });
  test(
      'sign out clears identity even when hangout and push cleanup fail, then uses a fresh guest device',
      () async {
    String? guestDevice;
    final api = ApiClient(client: MockClient((r) async {
      if (r.url.path.endsWith('/auth/guest')) {
        guestDevice = jsonDecode(r.body)['deviceId'] as String;
        return http.Response(
            jsonEncode({
              'accessToken': 'guest-token',
              'refreshToken': 'guest-refresh',
              'user': {
                'id': 'guest',
                'displayName': 'New Guest',
                'username': 'new_guest',
                'isGuest': true
              }
            }),
            200);
      }
      return http.Response('{}', 200);
    }))
      ..deviceId = 'old-device'
      ..bearer = 'old';
    final app = AppState(api)
      ..user =
          const UserView(id: 'account', displayName: 'Old Name', isGuest: false)
      ..identity = Identity.account
      ..avatarEmoji = 'old';
    app.onSignedOut = () async {
      throw StateError('push offline');
    };
    HangoutState.instance.open(const SizedBox(), 'old-room', 'Old room');
    HangoutState.instance.leave = () async {
      throw StateError('voice offline');
    };
    await app.signOut();
    expect(app.user, isNull);
    expect(app.identity, Identity.anonymous);
    expect(api.bearer, isNull);
    expect(app.avatarEmoji, isNull);
    expect(HangoutState.instance.active, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ta_refresh'), isNull);
    expect(prefs.getString('ta_cached_user'), isNull);
    expect(api.deviceId, isNot('old-device'));
    await app.startGuest('New Guest');
    expect(guestDevice, api.deviceId);
    expect(app.identity, Identity.guest);
    expect(app.user?.displayName, 'New Guest');
    await app.signOut();
    app.dispose();
  });
  testWidgets('an inbox close that never completes cannot block local sign out', (tester) async {
    final api = ApiClient(client: MockClient((_) async => http.Response('{}', 200)))
      ..bearer = 'old';
    final app = AppState(api)
      ..user = const UserView(id: 'account', displayName: 'Old Name', isGuest: false)
      ..identity = Identity.account
      ..inbox = _NeverClosingInbox();
    var signedOut = false;
    app.signOut().then((_) => signedOut = true);
    await tester.pump();
    expect(signedOut, isFalse);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(signedOut, isTrue);
    expect(app.inbox, isNull);
    expect(app.user, isNull);
    expect(api.bearer, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ta_refresh'), isNull);
    expect(prefs.getString('ta_cached_user'), isNull);
    app.dispose();
  });
  test('refresh started before sign out cannot restore the previous account',
      () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    SharedPreferences.setMockInitialValues(
        {'ta_device_id': 'device', 'ta_refresh': 'refresh'});
    final api = ApiClient(client: MockClient((r) async {
      if (r.url.path.endsWith('/auth/refresh')) {
        started.complete();
        return pending.future;
      }
      return http.Response('{}', 200);
    }));
    final app = AppState(api);
    await app.bootstrap();
    final refreshing = api.refreshHandler!();
    await started.future;
    await app.signOut();
    pending.complete(http.Response(
        jsonEncode({
          'accessToken': 'old-access',
          'refreshToken': 'old-refresh',
          'user': {'id': 'old', 'displayName': 'Old Name', 'isGuest': false}
        }),
        200));
    expect(await refreshing, isFalse);
    expect(api.bearer, isNull);
    expect(app.user, isNull);
    expect(app.identity, Identity.anonymous);
    app.dispose();
  });
}

class _NeverClosingInbox implements InboxClient {
  @override
  Future<void> close() => Completer<void>().future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
