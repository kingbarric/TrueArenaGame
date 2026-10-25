import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/invite_players_sheet.dart';

void main() {
  testWidgets(
      'invites put online friends first and keep selection when presence changes',
      (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final state = AppState(ApiClient(
        client: MockClient((_) async => http.Response(
            jsonEncode([
              {'userId': 'ada', 'displayName': 'Ada', 'username': 'ada'},
              {'userId': 'zed', 'displayName': 'Zed', 'username': 'zed'},
            ]),
            200,
            headers: {'content-type': 'application/json'}))));
    state.onlineFriends.value = {'zed'};
    await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
            theme: NeonTheme.light,
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () =>
                            showInvitePlayersSheet(context, roomId: 'room1'),
                        child: const Text('Invite')))))));
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Zed')).dy,
        lessThan(tester.getTopLeft(find.text('Ada')).dy));
    await tester.tap(find.text('Zed'));
    await tester.pumpAndSettle();
    state.onlineFriends.value = {'ada'};
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Ada')).dy,
        lessThan(tester.getTopLeft(find.text('Zed')).dy));
    final zed = tester.widget<CheckboxListTile>(find.ancestor(
        of: find.text('Zed'), matching: find.byType(CheckboxListTile)));
    expect(zed.value, isTrue);
    expect(find.text('@ada · Online'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
