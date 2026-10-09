import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/friends/friends_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'typing searches as-you-type and offers the top matches to add',
      (tester) async {
    final posted = <String>[];
    final mock = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET' && path == '/api/v1/friends') {
        return _json([]);
      }
      if (request.method == 'GET' && path == '/api/v1/friends/requests') {
        return _json({'incoming': [], 'outgoing': []});
      }
      if (request.method == 'GET' && path == '/api/v1/friends/search') {
        expect(request.url.queryParameters['q'], 'bo');
        return _json([
          {
            'userId': 'u-friend',
            'displayName': 'Bo Friend',
            'username': 'bofriend',
            'isFriend': true,
            'requestPending': false,
          },
          {
            'userId': 'u-pending',
            'displayName': 'Bo Pending',
            'username': 'bopending',
            'isFriend': false,
            'requestPending': true,
          },
          {
            'userId': 'u-stranger',
            'displayName': 'Bo Stranger',
            'username': 'bostranger',
            'isFriend': false,
            'requestPending': false,
          },
        ]);
      }
      if (request.method == 'POST' &&
          path == '/api/v1/friends/requests/user/u-stranger') {
        posted.add(path);
        return http.Response('', 201);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient(client: mock)),
      child: MaterialApp(theme: NeonTheme.dark, home: const FriendsScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'bo');
    await tester.pump(const Duration(milliseconds: 350)); // past the debounce
    await tester.pumpAndSettle();

    expect(find.text('Bo Friend'), findsOneWidget);
    expect(find.text('FRIENDS'), findsOneWidget);
    expect(find.text('Bo Pending'), findsOneWidget);
    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('Bo Stranger'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(posted, ['/api/v1/friends/requests/user/u-stranger']);
  });

  testWidgets('a sent request can be cancelled', (tester) async {
    final posted = <String>[];
    var outgoingCleared = false;
    final mock = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET' && path == '/api/v1/friends') {
        return _json([]);
      }
      if (request.method == 'GET' && path == '/api/v1/friends/requests') {
        return _json({
          'incoming': [],
          'outgoing': outgoingCleared
              ? []
              : [
                  {
                    'id': 'req-1',
                    'from': {
                      'userId': 'u-other',
                      'displayName': 'Other Person',
                      'username': 'other',
                    },
                    'createdAt': '2026-10-05T12:00:00Z',
                  },
                ],
        });
      }
      if (request.method == 'POST' &&
          path == '/api/v1/friends/requests/req-1/cancel') {
        posted.add(path);
        outgoingCleared = true;
        return http.Response('', 204);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient(client: mock)),
      child: MaterialApp(theme: NeonTheme.dark, home: const FriendsScreen()),
    ));
    await tester.pumpAndSettle();
    // Sent and received requests live under the Requests tab.
    await tester.tap(find.byKey(const ValueKey('friends-tab-requests')));
    await tester.pumpAndSettle();

    expect(find.text('Waiting on @other'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    expect(posted, ['/api/v1/friends/requests/req-1/cancel']);
    expect(find.text('Waiting on @other'), findsNothing);
  });
}
