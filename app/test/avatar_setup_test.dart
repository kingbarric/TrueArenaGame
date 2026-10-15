import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/onboarding/avatar_setup_screen.dart';
import 'package:truearena/features/onboarding/username_setup_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  for (final body in ['male', 'female']) {
    testWidgets(
        '$body selection saves the initial dressed avatar before continuing',
        (tester) async {
      final saved = <Map>[];
      var fail = true;
      final state = AppState(ApiClient(client: MockClient((request) async {
        saved.add(jsonDecode(request.body));
        return http.Response('{}', fail ? 503 : 200);
      })))
        ..identity = Identity.account
        ..user = const UserView(
            id: 'new',
            displayName: 'New',
            username: 'new_user',
            isGuest: false);
      await tester.binding.setSurfaceSize(const Size(390, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(AppScope(
          state: state,
          child: MaterialApp(
              theme: NeonTheme.light, home: const AvatarSetupScreen())));
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('onboarding-avatar-continue')))
              .onPressed,
          isNull);
      await tester.tap(find.byKey(ValueKey('onboarding-avatar-$body')));
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('onboarding-avatar-continue')));
      await tester.pumpAndSettle();
      expect(find.text('Could not save your avatar. Please try again.'),
          findsOneWidget);
      expect(find.byType(UsernameSetupScreen), findsNothing);
      fail = false;
      await tester
          .tap(find.byKey(const ValueKey('onboarding-avatar-continue')));
      await tester.pumpAndSettle();
      expect(
          saved,
          everyElement({
            'avatarId': body == 'female' ? 'ella' : 'male',
            'outfitId': 'everyday'
          }));
      expect(find.byType(UsernameSetupScreen), findsOneWidget);
    });
  }
}
