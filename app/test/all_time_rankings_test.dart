import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/competitive/all_time_rankings_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

Map<String, dynamic> _player(int rank, String id, int strength) => {
      'rank': rank,
      'userId': id,
      'username': id,
      'displayName': id.toUpperCase(),
      'strength': strength,
      'gamesPlayed': 5,
      'wins': 3,
      'draws': 1,
      'losses': 1,
    };

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('top 20 per game with medals, and your own place when you are further down', (tester) async {
    final calls = <String>[];
    final api = ApiClient(client: MockClient((r) async {
      calls.add('${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''}');
      return http.Response(
          jsonEncode({
            'gameType': r.url.queryParameters['gameType'],
            'top': [for (var i = 1; i <= 20; i++) _player(i, 'p$i', 500 - i * 10)],
            'you': _player(42, 'me', 61),
          }),
          200,
          headers: {'content-type': 'application/json'});
    }))
      ..bearer = 'token';
    final state = AppState(api)
      ..user = const UserView(id: 'me', displayName: 'Eric Barima', username: 'eric')
      ..identity = Identity.account;
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        AppScope(state: state, child: MaterialApp(theme: NeonTheme.dark, home: const AllTimeRankingsScreen())));
    await tester.pumpAndSettle();

    expect(calls.first, '/api/v1/rankings/all-time');
    expect(find.text('🥇'), findsOneWidget);
    expect(find.text('p1'), findsOneWidget);
    expect(find.byKey(const ValueKey('rank-you')), findsOneWidget);
    expect(find.text('#42'), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const ValueKey('rank-game-whot')), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const ValueKey('rank-game-whot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rank-game-whot')));
    await tester.pumpAndSettle();
    expect(calls, contains('/api/v1/rankings/all-time?gameType=whot'), reason: calls.join(' | '));
  });
}
