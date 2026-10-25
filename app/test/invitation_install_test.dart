import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/install_invitation.dart';
import 'package:truearena/core/invitation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('playhuud/install_referrer'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  test('Google Play can carry either invitation into the first app launch',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    for (final url in [
      'https://playhuud.com/huud/ABC234',
      'https://playhuud.com/championships/ABCD2345'
    ]) {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('playhuud/install_referrer'),
              (_) async => Uri(queryParameters: {'invitation': url}).query);
      expect(await installationInvitation(firstInstall: true),
          Invitation.fromText(url));
      expect(await PendingInvitation.load(), Invitation.fromText(url));
    }
  });
  test(
      'an explicitly copied iPhone invitation survives first launch without registering',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.hasStrings') return {'value': true};
      if (call.method == 'Clipboard.getData') {
        reads++;
        return {'text': 'https://playhuud.com/championships/ABCD2345'};
      }
      return null;
    });
    expect(await installationInvitation(firstInstall: true),
        const Invitation(InvitationKind.championship, 'ABCD2345'));
    expect(await installationInvitation(firstInstall: true), isNull);
    expect(reads, 1);
  });
  test(
      'ordinary app updates do not read clipboard or reopen an old install referrer',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('playhuud/install_referrer'), (_) async {
      calls++;
      return '';
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async {
      calls++;
      return null;
    });
    expect(await installationInvitation(firstInstall: false), isNull);
    expect(calls, 0);
  });
}
