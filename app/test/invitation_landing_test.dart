import 'package:truearena/features/draughts/championships_screen.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/invitation.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/invitations/invitation_landing.dart';
import 'package:truearena/theme/neon_theme.dart';

http.Response json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json'});

class _App extends AppState {
  _App(super.api);
  String? guestName;
  @override
  Future<void> startGuest(String nickname) async {
    guestName = nickname;
    identity = Identity.guest;
    user = UserView(id: 'guest', displayName: nickname, isGuest: true);
    notifyListeners();
  }
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });
  Future<void> open(
      WidgetTester tester, _App app, Invitation invitation) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(app.dispose);
    await tester.pumpWidget(AppScope(
        state: app,
        child: MaterialApp(
            theme: NeonTheme.dark,
            home: InvitationLanding(invitation: invitation))));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Map<String, dynamic> cup({int joined = 2, String status = 'lobby'}) => {
        'id': 'cup',
        'code': 'ABCD2345',
        'name': 'Friday crown',
        'gameType': 'chess',
        'size': 8,
        'joined': joined,
        'status': status,
        'participants': []
      };
  testWidgets(
      'an anonymous invitee sees the actual competition and can continue as a guest',
      (t) async {
    final app = _App(ApiClient(client: MockClient((r) async => json(cup()))));
    await open(
        t, app, const Invitation(InvitationKind.championship, 'ABCD2345'));
    expect(find.text('Friday crown'), findsOneWidget);
    expect(find.byKey(const ValueKey('invite-guest')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('invite-guest')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Ada');
    await t.tap(find.text('Continue as guest').last);
    await t.pumpAndSettle();
    expect(app.guestName, 'Ada');
    expect(find.byKey(const ValueKey('invite-accept')), findsOneWidget);
    expect(await PendingInvitation.load(),
        const Invitation(InvitationKind.championship, 'ABCD2345'));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'full and closed competitions do not offer a misleading accept button',
      (t) async {
    final app =
        _App(ApiClient(client: MockClient((r) async => json(cup(joined: 8)))));
    await open(
        t, app, const Invitation(InvitationKind.championship, 'ABCD2345'));
    expect(find.text('All places are taken.'), findsOneWidget);
    expect(find.text('Already registered? Sign in'), findsOneWidget);
    expect(find.byKey(const ValueKey('invite-accept')), findsNothing);
    expect(find.byKey(const ValueKey('invite-guest')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'expired invitations show a useful state without losing the destination',
      (t) async {
    final app = _App(ApiClient(client: MockClient((r) async => json({}, 404))));
    await open(t, app, const Invitation(InvitationKind.huud, 'ABC234'));
    expect(
        find.text('This invitation is no longer available.'), findsOneWidget);
    expect(find.byKey(const ValueKey('invite-accept')), findsNothing);
    expect(await PendingInvitation.load(),
        const Invitation(InvitationKind.huud, 'ABC234'));
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('both invitation types persist while choosing registration',
      (t) async {
    final app = _App(ApiClient(
        client: MockClient((r) async => json({'name': 'Friday crew'}))));
    await open(t, app, const Invitation(InvitationKind.huud, 'ABC234'));
    await t.tap(find.byKey(const ValueKey('invite-sign-in')));
    await t.pump(const Duration(milliseconds: 400));
    expect(await PendingInvitation.load(),
        const Invitation(InvitationKind.huud, 'ABC234'));
    expect(app.pendingHuudCode, 'ABC234');
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'accepting as a guest calls the invitation endpoint and opens that competition',
      (t) async {
    final calls = <String>[];
    final app = _App(ApiClient(client: MockClient((r) async {
      calls.add('${r.method} ${r.url.path}');
      if (r.method == 'POST')
        return json({'championshipId': 'cup', 'huudSpaceId': null});
      if (r.url.path.endsWith('/championships/cup'))
        return json({
          ...cup(),
          'participants': [
            {'id': 'guest', 'name': 'Ada'}
          ]
        });
      return json(cup());
    })))
      ..identity = Identity.guest
      ..user = const UserView(id: 'guest', displayName: 'Ada', isGuest: true);
    await open(
        t, app, const Invitation(InvitationKind.championship, 'ABCD2345'));
    await t.tap(find.byKey(const ValueKey('invite-accept')));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(
        calls, contains('POST /api/v1/championships/invite/ABCD2345/accept'));
    expect(find.byType(ChampionshipDetailScreen), findsOneWidget);
    expect(await PendingInvitation.load(), isNull);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
