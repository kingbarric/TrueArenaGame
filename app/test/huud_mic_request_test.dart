import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/hangout_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/huudspace/huud_mic_request_host.dart';
import 'package:truearena/features/huudspace/huud_voice.dart';
import 'package:truearena/features/ludo/ludo_game_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

import 'whot_game_test.dart' show TestSocket;

const _id = '00000000-0000-0000-0000-000000000002';
Map<String, dynamic> _view(
        {List<String> pending = const [],
        bool host = true,
        bool permitted = true}) =>
    {
      'id': _id,
      'name': "Eric's Huud",
      'status': 'active',
      'live': true,
      'youAreIn': true,
      'youAreHost': host,
      'youCanManageMic': permitted,
      'host': {'userId': host ? 'me' : 'admin', 'username': 'eric'},
      'requests': [
        for (final name in pending)
          {
            'kind': 'mic',
            'from': {'userId': name, 'username': name}
          }
      ],
    };
http.Response _json(Object? value) =>
    http.Response(value == null ? '' : jsonEncode(value), 200);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    HuudVoice.instance.reset();
    HangoutState.instance.clear();
  });

  Future<AppState> open(
      WidgetTester tester, Future<http.Response> Function(http.Request) routes,
      {Widget? home}) async {
    final state =
        AppState(ApiClient(client: MockClient(routes))..bearer = 'token')
          ..user =
              const UserView(id: 'me', displayName: 'Eric', username: 'eric')
          ..identity = Identity.account;
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
          navigatorKey: key,
          theme: NeonTheme.light,
          builder: (_, child) => HuudMicRequestHost(
              state: state, navigatorKey: key, child: child!),
          home: home ?? const Scaffold(body: Text('Game is still here')),
        )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    });
    return state;
  }

  Future<void> request(WidgetTester tester, AppState state,
      {String event = 'request'}) async {
    state.debugHuudSpaceEvent({
      'type': 'HUUD_SPACE',
      'data': {'huudSpaceId': _id, 'event': event, 'by': 'ada'}
    });
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
      'bold request dialog appears over Ludo and accepts without leaving the game',
      (tester) async {
    var pending = <String>[];
    final posts = <http.Request>[];
    final socket = TestSocket();
    final state = await open(tester, (r) async {
      if (r.method == 'POST') {
        posts.add(r);
        pending = [];
      }
      return _json(_view(pending: pending));
    },
        home: LudoGameScreen(
            socket: socket,
            selfId: 'me',
            roomCode: '7K3M',
            nicknames: const {}));
    pending = ['ada'];
    await request(tester, state);
    expect(tester.widget<Text>(find.text('Mic request')).style?.fontWeight,
        FontWeight.w900);
    expect(find.text('ada wants to speak'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(posts.single.url.path, '/api/v1/huud-spaces/$_id/requests/ada/mic');
    expect(jsonDecode(posts.single.body), {'accept': true});
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(LudoGameScreen), findsOneWidget);
  });

  testWidgets('recovers a pending request when opening the app',
      (tester) async {
    await open(tester, (_) async => _json(_view(pending: ['ada'])));
    expect(find.text('ada wants to speak'), findsOneWidget);
  });

  testWidgets(
      'duplicate events do not duplicate dialogs and queued requests can be declined or accepted',
      (tester) async {
    var pending = <String>[];
    final posts = <http.Request>[];
    final state = await open(tester, (r) async {
      if (r.method == 'POST') {
        posts.add(r);
        pending.remove(r.url.pathSegments[r.url.pathSegments.length - 2]);
      }
      return _json(_view(pending: pending));
    });
    pending = ['ada', 'chidi'];
    await request(tester, state);
    await request(tester, state);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Decline'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('chidi wants to speak'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(posts.map((r) => jsonDecode(r.body)), [
      {'accept': false},
      {'accept': true}
    ]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
      'eligible fallback participant sees requests even without owning a Huud',
      (tester) async {
    final state = await open(
        tester,
        (r) async => _json(r.url.path.endsWith('/current')
            ? null
            : _view(host: false, pending: ['ada'])));
    await request(tester, state);
    expect(find.text('ada wants to speak'), findsOneWidget);
    await tester.pump(const Duration(seconds: 16));
    expect(find.text('ada wants to speak'), findsOneWidget);
  });

  testWidgets('ordinary listener has no approval dialog', (tester) async {
    final state = await open(
        tester,
        (_) async =>
            _json(_view(host: false, permitted: false, pending: ['ada'])));
    await request(tester, state);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
      'losing approval authority closes a pending dialog without answering',
      (tester) async {
    var permitted = true;
    var posts = 0;
    final state = await open(tester, (r) async {
      if (r.method == 'POST') posts++;
      return _json(_view(host: false, permitted: permitted, pending: ['ada']));
    });
    expect(find.byType(AlertDialog), findsOneWidget);
    permitted = false;
    await request(tester, state, event: 'host');
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(posts, 0);
  });

  testWidgets('failed approval stays visible for a retry', (tester) async {
    var attempts = 0;
    final state = await open(tester, (r) async {
      if (r.method == 'POST') {
        attempts++;
        if (attempts == 1) throw const SocketException('offline');
        return _json(_view());
      }
      return _json(_view(pending: ['ada']));
    });
    expect(state.user?.id, 'me');
    await tester.tap(find.text('Accept'));
    await tester.pump();
    expect(find.text(userErrorMessage), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(attempts, 2);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
