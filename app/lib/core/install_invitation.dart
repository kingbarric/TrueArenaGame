import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'invitation.dart';

/// Google Play preserves the invitation in its install referrer. For an
/// explicitly copied invitation, iOS may ask the person to allow pasting.
Future<Invitation?> installationInvitation({required bool firstInstall}) async {
  final prefs = await SharedPreferences.getInstance();
  if (firstInstall &&
      !(prefs.getBool('ta_install_referrer_checked') ?? false) &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android) {
    try {
      final raw = await const MethodChannel('playhuud/install_referrer')
          .invokeMethod<String>('read')
          .timeout(const Duration(seconds: 3));
      await prefs.setBool('ta_install_referrer_checked', true);
      if (raw != null) {
        final params = Uri.splitQueryString(raw);
        final invite = Invitation.fromText(params['invitation']);
        if (invite != null) {
          await PendingInvitation.save(invite);
          return invite;
        }
      }
    } catch (_) {
      /* APK installs and unavailable Play services use the link fallback. */
    }
  }
  if (!firstInstall ||
      (prefs.getBool('ta_invitation_clipboard_checked') ?? false)) {
    return null;
  }
  await prefs.setBool('ta_invitation_clipboard_checked', true);
  try {
    if (!await Clipboard.hasStrings()) return null;
    final invite = Invitation.fromText(
        (await Clipboard.getData(Clipboard.kTextPlain))?.text);
    if (invite == null) return null;
    await PendingInvitation.save(invite);
    return invite;
  } catch (_) {
    return null;
  }
}
