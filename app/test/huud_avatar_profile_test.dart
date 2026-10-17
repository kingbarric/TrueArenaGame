import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/huudspace/huud_avatar_models.dart';
import 'package:truearena/features/profile/huud_avatar_screen.dart';
import 'package:truearena/features/profile/profile_screen.dart';
import 'package:truearena/features/slayhuud/slay_stage.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  final options = jsonDecode(
      File('../backend/ta-api/src/main/resources/slay/huud-avatars.json')
          .readAsStringSync()) as Map;
  final slay =
      jsonDecode(File('assets/slay_renderer/catalog.json').readAsStringSync())
          as Map;
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SlayStage.debugPlaceholder = true;
    HuudAvatarScreen.debugSkipAssetServer = true;
    SlayStage.debugApplyLook = (_) => Future.value();
  });
  tearDown(() {
    SlayStage.debugPlaceholder = false;
    HuudAvatarScreen.debugSkipAssetServer = false;
    SlayStage.debugApplyLook = null;
  });
  test(
      'every one of the 50 choices is dressed and has the correct body and items',
      () {
    final model = HuudAvatarOptions.fromJson(options);
    for (final avatar in model.avatars)
      for (final outfit in model.outfits) {
        final look = model.look(avatar.id, outfit.id)!;
        expect(look.body, avatar.body);
        expect(look.avatarId, avatar.id);
        expect(look.isDressed, true);
        expect(look.items['hair'], avatar.hair);
        for (final id in look.items.values)
          expect((slay['items'] as List).any((i) => i['id'] == id), true);
      }
    expect(model.look('unknown', 'everyday'), null);
  });
  Future<List<Map>> pump(WidgetTester tester, {bool failSave = false, Widget home = const HuudAvatarScreen()}) async {
    final saved = <Map>[];
    final api = ApiClient(client: MockClient((request) async {
      if (request.url.path.endsWith('/slay/catalog'))
        return http.Response(jsonEncode(slay), 200);
      if (request.method == 'PATCH') {
        saved.add(jsonDecode(request.body));
        if (failSave) return http.Response('{}', 503);
      }
      return http.Response(
          jsonEncode({
            'avatarId': 'male',
            'outfitId': 'everyday',
            'saved': false,
            'catalog': options
          }),
          200);
    }));
    final state = AppState(api)
      ..identity = Identity.account
      ..user = const UserView(
          id: 'me', displayName: 'Me', username: 'me', isGuest: false);
    await tester.binding.setSurfaceSize(const Size(390, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
            theme: NeonTheme.light, home: home)));
    await tester.pumpAndSettle();
    return saved;
  }

  testWidgets('Profile opens the avatar picker', (tester) async {
    await pump(tester, home: const ProfileScreen());
    await tester.tap(find.byKey(const ValueKey('profile-huud-avatar')));
    await tester.pumpAndSettle();
    expect(find.byType(HuudAvatarScreen), findsOneWidget);
    expect(find.text('AVATARS · 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('huud-avatar-save')), findsOneWidget);
  });

  testWidgets(
      'avatar and outfit choices save only on Save and reload the selected body',
      (tester) async {
    final requests = await pump(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('huud-avatar-ella')));
    await tester.tap(find.byKey(const ValueKey('huud-avatar-ella')));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('huud-outfit-evening'))),
        alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('huud-outfit-evening')));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    await tester.tap(find.byKey(const ValueKey('huud-avatar-save')));
    await tester.pumpAndSettle();
    expect(requests, [
      {'avatarId': 'ella', 'outfitId': 'evening'}
    ]);
    expect(find.text('Saved'), findsOneWidget);
  });
  testWidgets('a failed save preserves the draft and allows retry',
      (tester) async {
    final requests = await pump(tester, failSave: true);
    await tester.tap(find.byKey(const ValueKey('huud-avatar-save')));
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(find.text('Saved'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('huud-avatar-save')))
            .onPressed,
        isNotNull);
    expect(find.text('Could not save your avatar. Please try again.'),
        findsOneWidget);
  });
}
