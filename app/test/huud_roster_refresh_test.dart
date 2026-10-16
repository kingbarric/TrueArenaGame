import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/huudspace/huud_roster.dart';
import 'package:truearena/features/huudspace/huud_space_models.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  for (final game in ['chess', 'draughts']) {
    testWidgets(
        'confirmed agent appears before refresh and repeated taps cannot overfill $game',
        (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      final response = Completer<http.Response>();
      final refresh = Completer<void>();
      var adds = 0;
      final state = AppState(ApiClient(client: MockClient((request) {
        adds++;
        return response.future;
      })));
      const host = HuudMember(
          userId: 'host',
          displayName: 'Host',
          username: 'host',
          host: true,
          here: true);
      final huud = HuudSpace(
          id: 'h1',
          name: 'Test',
          privacy: HuudPrivacy.private,
          status: 'active',
          members: const [
            host,
            HuudMember(userId: 'away', displayName: 'Away', username: 'away')
          ],
          currentGame: HuudGame(
              roomId: game,
              code: 'TEST',
              gameType: game,
              status: 'waiting',
              players: 1),
          host: host,
          youAreIn: true,
          youAreHost: true,
          voiceRoom: 'voice');
      await tester.pumpWidget(AppScope(
          state: state,
          child: MaterialApp(
              theme: NeonTheme.light,
              home: Scaffold(
                  body: HuudRoster(
                      huud: huud,
                      roomId: game,
                      seats: 2,
                      seated: const [HuudSeat(userId: 'host', name: 'Host')],
                      onChanged: () => refresh.future)))));
      final add = find.byKey(const ValueKey('roster-add-agent'));
      expect(
          tester.getTopLeft(add).dy,
          lessThan(
              tester.getTopLeft(find.byKey(const ValueKey('roster-away'))).dy));
      await tester.tap(add);
      await tester.pump();
      await tester.tap(add);
      expect(adds, 1);
      response.complete(http.Response(
          jsonEncode({'userId': 'bot', 'displayName': 'Cyber 1'}), 200,
          headers: {'content-type': 'application/json'}));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Cyber 1 (Cyber Agent)'), findsOneWidget);
      expect(find.text('2 / 2 playing'), findsOneWidget);
      expect(add, findsNothing);
      refresh.complete();
      await tester.pumpAndSettle();
      // The parent still has its old one-player snapshot.
      expect(add, findsNothing);
      expect(adds, 1);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    });
  }
}
