import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/calls/incoming_call_screen.dart';
import 'package:truearena/features/friends/friends_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('an incoming call shows who is calling, and Decline tells them',
      (tester) async {
    final posted = <String>[];
    final mock = MockClient((request) async {
      posted.add('${request.method} ${request.url.path}');
      return http.Response('', 200);
    });
    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient(client: mock)),
      child: MaterialApp(
        theme: NeonTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const IncomingCallScreen(
                    callerId: 'u-ama', callerName: 'Ama Mensah'))),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Ama Mensah'), findsOneWidget);
    expect(find.text('is calling you…'), findsOneWidget);
    expect(find.byKey(const ValueKey('incoming-accept')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('incoming-decline')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(posted, contains('POST /api/v1/calls/dm/u-ama/decline'));
    await tester.pump(const Duration(milliseconds: 600)); // closing transition
    expect(find.text('Ama Mensah'), findsNothing);
  });

  testWidgets('a call nobody answers counts as missed', (tester) async {
    await tester.pumpWidget(AppScope(
      state: AppState(
          ApiClient(client: MockClient((_) async => http.Response('', 200)))),
      child: MaterialApp(
        theme: NeonTheme.dark,
        home: const IncomingCallScreen(callerId: 'u-ama', callerName: 'Ama'),
      ),
    ));
    await tester.pump(IncomingCallScreen.ringFor);
    await tester.pump();
    expect(find.text('Missed call'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the nudge sits by a friend\'s name and buzzes them',
      (tester) async {
    final posted = <String>[];
    final mock = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET' && path == '/api/v1/friends') {
        return _json([
          {'userId': 'u-ama', 'displayName': 'Ama Mensah', 'username': 'ama'}
        ]);
      }
      if (request.method == 'GET' && path == '/api/v1/friends/requests') {
        return _json({'incoming': [], 'outgoing': []});
      }
      if (request.method == 'POST') posted.add(path);
      return http.Response('', 200);
    });
    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient(client: mock)),
      child: MaterialApp(theme: NeonTheme.dark, home: const FriendsScreen()),
    ));
    await tester.pumpAndSettle();

    final nudge = find.byKey(const ValueKey('nudge-u-ama'));
    expect(nudge, findsOneWidget);
    // Right next to the name, on the same line.
    expect(
        (tester.getCenter(nudge).dy -
                tester.getCenter(find.text('Ama Mensah')).dy)
            .abs(),
        lessThan(4));

    await tester.tap(nudge);
    await tester.pumpAndSettle();
    expect(posted, ['/api/v1/friends/u-ama/nudge']);
    expect(find.textContaining('Nudged Ama Mensah'), findsOneWidget);
  });
}
