import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/app.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/core/page_cache.dart';
import 'package:truearena/features/huud/social_huud_controller.dart';
import 'package:truearena/features/huud/social_huud_models.dart';
import 'package:truearena/features/huud/social_huud_home.dart';
import 'social_huud_test.dart' show fixture;
import 'package:truearena/theme/neon_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PageCache> cache(
          [String user = 'host', String origin = ApiClient.base]) async =>
      PageCache(await SharedPreferences.getInstance(), origin, user);

  test(
      'persisted pages survive relaunch and are isolated by account and server',
      () async {
    final first = await cache();
    await first.write('/huuds/sessions', [fixture()]);
    expect((await cache()).read('/huuds/sessions'), hasLength(1));
    expect((await cache('someone-else')).read('/huuds/sessions'), isNull);
    expect(
        (await cache('host', 'https://another.example'))
            .read('/huuds/sessions'),
        isNull);
    await first.clear();
    expect((await cache()).read('/huuds/sessions'), isNull);
    await first.write('/huuds/sessions', [fixture()]);
    expect((await cache()).read('/huuds/sessions'), isNull);
  });

  test('private match state, credentials and voice tokens cannot be cached',
      () async {
    final saved = await cache();
    for (final path in [
      '/rooms/game',
      '/auth/refresh',
      '/me',
      '/voice/token',
      '/wallet',
      '/friends/online'
    ]) {
      await saved.write(path, {'secret': 'never persisted'});
      expect(saved.read(path), isNull);
    }
    expect(
        (await SharedPreferences.getInstance()).getString(saved.key), isNull);
  });

  test('expired or corrupt snapshots cannot break launch', () async {
    final saved = await cache();
    await saved.prefs.setString(
        saved.key,
        jsonEncode({
          '/friends': {
            'at': DateTime.now()
                .subtract(const Duration(days: 8))
                .millisecondsSinceEpoch,
            'data': []
          }
        }));
    expect((await cache()).read('/friends'), isNull);
    await saved.prefs.setString(saved.key, 'broken-json');
    expect((await cache()).read('/friends'), isNull);
  });

  test('network failures show saved data and subsequent success refreshes it',
      () async {
    bool disconnected = false;
    final api = ApiClient(client: MockClient((_) async {
      if (disconnected) throw const SocketException('offline');
      return http.Response('[{"username":"Chidi"}]', 200);
    }))
      ..pageCache = await cache();
    await api.get('/friends');
    disconnected = true;
    expect((await api.get('/friends') as List).first['username'], 'Chidi');
    expect(api.offline.value, isTrue);
    expect(api.usedSavedResponse('/friends'), isTrue);
    disconnected = false;
    await api.get('/friends');
    expect(api.offline.value, isFalse);
    expect(api.usedSavedResponse('/friends'), isFalse);
  });

  for (final status in [401, 403, 404, 410]) {
    test('HTTP $status evicts the snapshot and never grants cached access',
        () async {
      final saved = await cache();
      await saved.write('/friends', []);
      final api =
          ApiClient(client: MockClient((_) async => http.Response('', status)))
            ..pageCache = saved;
      await expectLater(api.get('/friends'), throwsA(isA<ApiException>()));
      expect(saved.read('/friends'), isNull);
    });
  }

  test('an offline refresh preserves saved pages instead of declaring logout',
      () async {
    final api = ApiClient(client: MockClient((r) async {
      if (r.url.path.endsWith('/auth/refresh')) {
        throw const SocketException('offline');
      }
      return http.Response('', 401);
    }))
      ..bearer = 'expired'
      ..pageCache = await cache();
    await api.pageCache!.write('/friends', [
      {'username': 'Ada'}
    ]);
    api.refreshHandler = () async {
      try {
        await api.post('/auth/refresh');
      } catch (_) {
        return false;
      }
      return true;
    };
    expect((await api.get('/friends') as List).first['username'], 'Ada');
    expect(api.bearer, 'expired');
  });

  test('in-flight requests cannot save into a different signed-in account',
      () async {
    final response = Completer<http.Response>();
    final oldCache = await cache();
    final api = ApiClient(client: MockClient((_) => response.future))
      ..pageCache = oldCache;
    final load = api.get('/friends');
    api.pageCache = await cache('other');
    response.complete(http.Response('[{"username":"old-account"}]', 200));
    await load;
    expect(api.pageCache!.read('/friends'), isNull);
    expect(oldCache.read('/friends'), isNull);
  });

  test('offline actions fail once and are not queued for automatic replay',
      () async {
    int attempts = 0;
    final api = ApiClient(client: MockClient((_) async {
      attempts++;
      throw const SocketException('offline');
    }));
    await expectLater(
        api.post('/huuds/sessions/h/start'), throwsA(isA<SocketException>()));
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 1);
  });

  test(
      'cached Huud state and chat hydrate immediately without enabling a match',
      () async {
    final api = ApiClient(
        client: MockClient((_) async => throw const SocketException('offline')))
      ..pageCache = await cache();
    await api.pageCache!.write('/huuds/sessions/huud-1', fixture());
    await api.pageCache!.write('/huuds/sessions/huud-1/chat', [
      {'text': 'Stay for another game'}
    ]);
    final controller =
        SocialHuudController(api, 'host', SocialHuud.fromJson(fixture()));
    expect(controller.messages.single['text'], 'Stay for another game');
    await controller.refresh();
    expect(controller.liveConfirmed, isFalse);
    expect(controller.huud.name, "Eric's Huud");
    controller.dispose();
  });

  testWidgets(
      'Home renders saved cards while all network requests are still pending',
      (tester) async {
    final response = Completer<http.Response>();
    final api = ApiClient(client: MockClient((_) => response.future))
      ..pageCache = await cache();
    await api.pageCache!.write('/huuds/sessions', [fixture()]);
    final state = AppState(api)
      ..user = const UserView(id: 'host', displayName: 'Eric')
      ..identity = Identity.account;
    await tester.pumpWidget(AppScope(
        state: state,
        child:
            MaterialApp(theme: NeonTheme.light, home: const SocialHuudHome())));
    expect(find.text("Eric's Huud"), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    response.complete(http.Response('[]', 200));
    await tester.pump();
    state.dispose();
  });

  testWidgets(
      'cold startup opens the app without waiting for /me or the saved game',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ta_access': 'saved-access',
      'ta_refresh': 'saved-refresh',
      'ta_cached_user':
          jsonEncode({'id': 'host', 'displayName': 'Eric', 'isGuest': false}),
      'ta_active_room': 'room-1',
      'ta_active_room_user': 'host',
      'ta_active_room_saved_at': DateTime.now().millisecondsSinceEpoch,
    });
    final response = Completer<http.Response>();
    final state =
        AppState(ApiClient(client: MockClient((_) => response.future)));
    await tester.runAsync(state.bootstrap);
    expect(state.identity, Identity.account);
    expect(state.activeRoomId, 'room-1');
    await tester.pumpWidget(TrueArenaApp(state: state));
    await tester.pump();
    expect(find.byType(SocialHuudHome), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    response.complete(http.Response('[]', 200));
    await tester.pump();
  });
}
