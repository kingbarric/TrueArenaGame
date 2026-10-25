import 'package:shared_preferences/shared_preferences.dart';

enum InvitationKind { huud, championship }

class Invitation {
  const Invitation(this.kind, this.code);
  final InvitationKind kind;
  final String code;
  String get path =>
      '/${kind == InvitationKind.huud ? 'huud' : 'championships'}/$code';
  String get url => 'https://playhuud.com$path';
  String get appUrl => 'playhuud://$path';

  static Invitation? fromUri(Uri uri) {
    if (uri.scheme.isEmpty && uri.host.isNotEmpty) return null;
    if (uri.scheme.isNotEmpty &&
        uri.scheme != 'playhuud' &&
        !((uri.scheme == 'https' || uri.scheme == 'http') &&
            ['playhuud.com', 'www.playhuud.com'].contains(uri.host))) {
      return null;
    }
    var path = uri.path;
    if (uri.scheme == 'playhuud' && uri.host.isNotEmpty) {
      path = '/${uri.host}$path';
    }
    final huud = RegExp(r'^/huud/([A-Z0-9]{6})/?$', caseSensitive: false)
        .firstMatch(path);
    if (huud != null) {
      return Invitation(InvitationKind.huud, huud[1]!.toUpperCase());
    }
    final cup =
        RegExp(r'^/championships/([A-HJ-NP-Z2-9]{8})/?$', caseSensitive: false)
            .firstMatch(path);
    return cup == null
        ? null
        : Invitation(InvitationKind.championship, cup[1]!.toUpperCase());
  }

  static Invitation? fromText(String? text) {
    if (text == null) return null;
    final uri = Uri.tryParse(text.trim());
    final direct = uri == null ? null : fromUri(uri);
    if (direct != null) return direct;
    for (final match in RegExp(
            r'https://(?:www\.)?playhuud\.com/(?:huud|championships)/[A-Za-z0-9]+/?',
            caseSensitive: false)
        .allMatches(text)) {
      if (match.start > 0 &&
          RegExp(r'[\w./-]').hasMatch(text[match.start - 1])) {
        continue;
      }
      final invite = fromUri(Uri.parse(match[0]!));
      if (invite != null) return invite;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is Invitation && kind == other.kind && code == other.code;
  @override
  int get hashCode => Object.hash(kind, code);
}

class PendingInvitation {
  static const _key = 'ta_pending_invitation';
  static Future<void> save(Invitation invitation) async =>
      (await SharedPreferences.getInstance()).setString(_key, invitation.url);
  static Future<Invitation?> load() async => Invitation.fromText(
      (await SharedPreferences.getInstance()).getString(_key));
  static Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}
