import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/huudspace/huud_space_screen.dart';
import 'package:truearena/features/huudspace/huud_voice.dart';
import 'package:truearena/core/hangout_state.dart';
import 'package:truearena/features/huudspace/leave_game.dart';
import 'package:truearena/features/notifications/notifications_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _member(String id, String name, {bool host = false}) =>
    {'userId': id, 'displayName': name, 'username': name.toLowerCase(), 'host': host, 'here': true};

final _huud = {
  'id': 'h1',
  'code': 'KTB7QX',
  'name': "Ada's Whot Club",
  'privacy': 'friends',
  'status': 'active',
  'host': _member('ada', 'Ada', host: true),
  'members': [_member('ada', 'Ada', host: true), _member('me', 'Eric')],
  'youAreIn': true,
  'youAreHost': false,
  'voiceRoom': 'huud-h1',
  'live': true,
  'memberCount': 2,
  'liveCount': 2,
};

final _navKey = GlobalKey<NavigatorState>();

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    HuudVoice.instance.reset();
    HangoutState.instance.clear();
  });

  Future<List<String>> pump(
      WidgetTester tester, Widget home, Future<http.Response> Function(http.Request) routes) async {
    final calls = <String>[];
    final api = ApiClient(client: MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      return routes(request);
    }))
      ..bearer = 'token';
    final state = AppState(api)
      ..user = UserView(id: 'me', displayName: 'Eric Barima', username: 'eric', isGuest: false)
      ..identity = Identity.account;
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        AppScope(state: state, child: MaterialApp(navigatorKey: _navKey, theme: NeonTheme.light, home: home)));
    await tester.pump(const Duration(milliseconds: 300));
    return calls;
  }

  testWidgets('leaving a game played in a Huud goes back into that Huud', (tester) async {
    final calls = await pump(tester, const Scaffold(body: Text('home')), (r) async {
      if (r.url.path.endsWith('/messages')) return _json([]);
      return _json(_huud);
    });
    final nav = _navKey.currentState!;
    nav.push(huudRoute('h1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    nav.push(MaterialPageRoute(
        builder: (context) => Scaffold(
            body: Center(
                child: TextButton(
                    key: const ValueKey('game-over'),
                    onPressed: () => leaveGame(context, 'room1'),
                    child: const Text('Back'))))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const ValueKey('game-over')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(calls, contains('GET /api/v1/huud-spaces/by-room/room1'));
    expect(find.byKey(const ValueKey('game-over')), findsNothing);
    expect(find.byType(HuudSpaceScreen), findsOneWidget);
    expect(find.text("Ada's Whot Club"), findsWidgets);
  });

  testWidgets('swiping a notification deletes it', (tester) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final calls = await pump(tester, const NotificationsScreen(), (r) async {
      if (r.method == 'DELETE') return http.Response('', 200);
      return _json([
        {'id': 'n1', 'type': 'HUUD_SPACE', 'title': 'PlayHuud', 'body': 'Ada is live', 'data': {}, 'createdAt': now},
        {'id': 'n2', 'type': 'YOUR_TURN', 'title': 'Your turn', 'body': 'Whot with Tobi', 'data': {}, 'createdAt': now},
      ]);
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Swipe one sideways to delete it'), findsOneWidget);
    expect(find.text('Ada is live'), findsOneWidget);

    await tester.drag(find.byKey(const ValueKey('notification-n1')), const Offset(-500, 0));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Ada is live'), findsNothing);
    expect(find.text('Whot with Tobi'), findsOneWidget);
    expect(calls, contains('DELETE /api/v1/notifications/n1'));
  });
}
