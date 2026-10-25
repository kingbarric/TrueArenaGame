import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/invitation.dart';
import 'package:truearena/features/invitations/invitation_share.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('both invitation kinds accept canonical app and universal links', () {
    for (final path in ['/huud/ABC234', '/championships/ABCD2345']) {
      for (final prefix in [
        '',
        'https://playhuud.com',
        'https://www.playhuud.com',
        'playhuud://'
      ]) {
        final invitation = Invitation.fromUri(Uri.parse('$prefix$path'));
        expect(invitation, isNotNull);
        expect(invitation!.path, path);
      }
    }
    expect(
        Invitation.fromText(
            'Come play! https://playhuud.com/championships/abcd2345\nJoin us.'),
        const Invitation(InvitationKind.championship, 'ABCD2345'));
    expect(Invitation.fromUri(Uri.parse('playhuud://huud/ABC234'))!.kind,
        InvitationKind.huud);
  });
  test('configured deployment links round trip and retain their prefix', () {
    const invite = Invitation(InvitationKind.huud, 'ABC234');
    expect(Invitation.fromText(invite.url), invite);
    expect(Invitation.fromText('Come join! ${invite.url}.'), invite);
    final base = Uri.parse(Invitation.publicBase);
    if (base.path.isNotEmpty) {
      expect(Invitation.fromText('${base.origin}/huud/ABC234'), isNull);
      expect(Invitation.fromText('${base.origin}/other/huud/ABC234'), isNull);
    }
  });
  test('foreign hosts and malformed codes cannot become invitations', () {
    for (final text in [
      'https://evil.example/huud/ABC234',
      '//evil.example/huud/ABC234',
      'https://playhuud.com.evil.example/huud/ABC234',
      'https://playhuud.com/huud/ABC234X',
      'https://playhuud.com/championships/INVALID0',
      'https://playhuud.com/championships/ABCD23456',
      'https://evil.example/https://playhuud.com/huud/ABC234'
    ]) {
      expect(Invitation.fromText(text), isNull, reason: text);
    }
  });
  test(
      'a pending destination survives guest onboarding and restart until cleared',
      () async {
    const huud = Invitation(InvitationKind.huud, 'ABC234');
    const cup = Invitation(InvitationKind.championship, 'ABCD2345');
    await PendingInvitation.save(huud);
    expect(await PendingInvitation.load(), huud);
    await PendingInvitation.save(cup);
    expect(await PendingInvitation.load(), cup);
    await PendingInvitation.clear();
    expect(await PendingInvitation.load(), isNull);
  });
  test('a real app bootstrap restores the destination before signing in',
      () async {
    const invite = Invitation(InvitationKind.championship, 'ABCD2345');
    await PendingInvitation.save(invite);
    final app = AppState(ApiClient());
    await app.bootstrap();
    expect(app.identity, Identity.anonymous);
    expect(app.pendingChampionshipCode, invite.code);
    app.dispose();
  });
  test(
      'captions include the game, guest option and exact clickable destination',
      () {
    const data = InvitationArtwork(
        invitation: Invitation(InvitationKind.championship, 'ABCD2345'),
        name: 'Friday crown',
        gameType: 'chess');
    expect(data.shareText, contains('Chess championship'));
    expect(data.shareText, contains('Play as a guest'));
    expect(data.shareText,
        contains('${Invitation.publicBase}/championships/ABCD2345'));
  });
}
