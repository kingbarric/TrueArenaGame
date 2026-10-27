import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/core/player_identity.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/core/invitation.dart';
import 'package:truearena/features/huud/huud_models.dart';
import 'package:truearena/features/invitations/invitation_share.dart';
import 'package:truearena/features/status/victory_status.dart';
import 'package:truearena/widgets/game_artwork.dart';

void main() {
  test('shares use first names and public identities use usernames', () {
    expect(firstName('  Ada   Lovelace '), 'Ada');
    expect(firstName('  '), 'Player');
    expect(playerHandle('ada_plays', displayName: 'Ada Lovelace'), 'ada_plays');
    expect(playerHandle(null, displayName: 'Ada Lovelace'), 'Ada');
    final member = RoomMember.fromJson({'userId': '1', 'username': 'ada_plays', 'nickname': 'Ada Lovelace'});
    expect(member.nickname, 'ada_plays');
    final person = HuudPerson.fromJson({'userId': '1', 'username': 'ada_plays', 'displayName': 'Ada Lovelace'});
    expect(person.name, 'ada_plays');
    final share = InvitationArtwork(invitation: const Invitation(InvitationKind.huud, 'ABC234'),
      name: 'Friday Crew', gameType: 'truearena', hostName: 'Ada Lovelace');
    expect(share.shareText, contains('Ada invites you'));
    expect(share.shareText, isNot(contains('Lovelace')));
    expect(share.shareText, contains('Trust nobody'));
    expect(share.shareText, contains('PlayHuud'));
    expect(share.shareText, contains(share.invitation.url));
    expect(gameArtworkAsset('truearena', mode: 'blood_moon'), endsWith('blood_moon.jpg'));
    expect(gameArtworkAsset('draughts'), endsWith('draft.png'));
  });

  testWidgets('victory artwork shows game art, first name, brand and challenge', (tester) async {
    await tester.runAsync(() async {
      await (FontLoader('MonopolySans')..addFont(rootBundle.load('assets/fonts/monopoly/Roboto-Regular.ttf'))).load();
      await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: 'MonopolySans'), home: Center(child: SizedBox(width: 300,
      child: RepaintBoundary(key: key, child: const VictoryCard(
        playerName: 'Ada Lovelace', gameType: 'truearena', detail: 'The Faithful win'))))));
    await tester.runAsync(() async {
      final context = tester.element(find.byType(VictoryCard));
      await precacheImage(AssetImage(gameArtworkAsset('truearena')), context);
      if (context.mounted) await precacheImage(const AssetImage('assets/images/branding/playhuud-wordmark-transparent.png'), context);
    });
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);
    expect(find.textContaining('Lovelace'), findsNothing);
    expect(find.text('Think you can beat me? Join the game.'), findsOneWidget);
    expect(find.text('Traitors'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('EXPORT_SHARE_PREVIEW')) {
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/playhuud-victory-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
