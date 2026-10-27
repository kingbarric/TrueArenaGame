import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/core/invitation.dart';
import 'package:truearena/features/invitations/invitation_share.dart';

void main() {
  testWidgets(
      'branded exports render for each championship game and Huud invitations',
      (tester) async {
    await tester.runAsync(() async {
      final loader = FontLoader('MonopolySans')
        ..addFont(rootBundle.load('assets/fonts/monopoly/Roboto-Regular.ttf'));
      await loader.load();
      for (final game in [null, 'chess', 'draughts', 'slayhuud', 'truearena', 'whot', 'ludo', 'goosi', 'wordbluff', 'monopoly']) {
        final data = InvitationArtwork(
            invitation: Invitation(
                game == null
                    ? InvitationKind.huud
                    : InvitationKind.championship,
                game == null ? 'ABC234' : 'ABCD2345'),
            name: game == null
                ? 'The Friday Crew'
                : 'Friday Night ${invitationGameNames[game]} Championship',
            gameType: game);
        for (final landscape in [true, false]) {
          final cover = landscape
              ? InvitationArtwork(
                  invitation: data.invitation,
                  name: game == null
                      ? 'Bring your people. Make it a game.'
                      : 'A knockout competition. A crown to claim.',
                  gameType: game)
              : data;
          final image =
              await renderInvitationArtwork(cover, landscape: landscape);
          expect(image.width, 1200);
          expect(image.height, landscape ? 630 : 1500);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(bytes!.lengthInBytes, greaterThan(10000));
          if (const bool.fromEnvironment('EXPORT_INVITATION_ARTWORK')) {
            final path = landscape
                ? '../website/assets/invite-${game ?? 'huud'}.png'
                : '../output/invitation-validation/share-${game ?? 'huud'}.png';
            final file = File(path);
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes.buffer.asUint8List());
          }
          if (const bool.fromEnvironment('EXPORT_SHARE_PREVIEW')) {
            if (game == 'truearena' && !landscape) {
              await File('/tmp/playhuud-invitation-preview.png').writeAsBytes(bytes.buffer.asUint8List());
            }
          }
          image.dispose();
        }
      }
    });
  });
}
