import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';
import 'huud_space_screen.dart';

/// A Huud's invite link: playhuud.com/huud/CODE. Opens the Huud in the app
/// (iOS universal link / Android app link); without the app the page offers
/// it, and after sign-up the app brings you straight in.
String huudLink(String code) => 'https://playhuud.com/huud/${code.toUpperCase()}';

final _linkPattern = RegExp(r'playhuud\.com/huud/([A-Za-z0-9]{6})\b');

/// The code in a playhuud.com/huud/… link (or link text), if there is one.
String? huudCodeFromLink(String? text) => text == null ? null : _linkPattern.firstMatch(text)?.group(1)?.toUpperCase();

/// The text a share sends: who, what, and the link.
String huudInviteText(HuudSpace huud) =>
    'Come hang out with me in "${huud.name}" on PlayHuud! 🎮\n${huudLink(huud.code ?? '')}';

/// Share the Huud's link. The share sheet needs to know where on screen it
/// came from (current iOS won't show it otherwise), so pass the button's
/// [context]. If it can't open, the link is copied instead.
Future<void> shareHuud(BuildContext context, HuudSpace huud) async {
  final code = huud.code;
  if (code == null) return;
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
  try {
    await Share.share(huudInviteText(huud), subject: 'Join my Huud on PlayHuud', sharePositionOrigin: origin);
  } catch (_) {
    await copyHuudLink(context, huud);
  }
}

Future<void> copyHuudLink(BuildContext context, HuudSpace huud) async {
  final code = huud.code;
  if (code == null) return;
  await Clipboard.setData(ClipboardData(text: huudLink(code)));
  if (context.mounted) huudSnack(context, 'Link copied — paste it to your friends 🔗');
}

/// Join the Huud a link points at, then go in. Rules still apply: a private
/// Huud asks the host first.
Future<void> joinHuudFromLink(BuildContext context, String code) async {
  final app = AppScope.of(context);
  try {
    final raw = await app.api.post('/huud-spaces/join', {'code': code.toUpperCase()}) as Map<String, dynamic>;
    if (!context.mounted) return;
    final huud = HuudSpace.fromJson(raw);
    await openHuudSpace(context, huud.id, initial: huud);
  } on ApiException catch (e) {
    if (context.mounted) huudSnack(context, e.status == 404 ? "That Huud isn't around any more." : e.message);
  } catch (_) {
    if (context.mounted) huudSnack(context, "We couldn't reach PlayHuud. Check your internet.");
  }
}

/// Once the app is up and you're signed in: a link you opened before signing
/// up, or — on a fresh install — one the invite page left on the clipboard.
Future<void> consumeHuudInvite(BuildContext context) async {
  final app = AppScope.of(context);
  if (app.identity == Identity.anonymous) return;
  var code = app.pendingHuudCode;
  app.pendingHuudCode = null;
  if (code == null && app.freshInstall) {
    app.freshInstall = false;
    code = await _codeOnClipboard();
  }
  if (code != null && context.mounted) await joinHuudFromLink(context, code);
}

/// Looked at once, and only if there's text there at all (checking doesn't
/// ask permission; reading might, which is why it's only on a fresh install).
Future<String?> _codeOnClipboard() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kClipboardChecked) ?? false) return null;
    await prefs.setBool(_kClipboardChecked, true);
    if (!await Clipboard.hasStrings()) return null;
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    final code = huudCodeFromLink(text);
    if (code != null) await Clipboard.setData(const ClipboardData(text: ''));
    return code;
  } catch (_) {
    return null;
  }
}

const _kClipboardChecked = 'ta_huud_link_clipboard_checked';

/// Where an invite link lands while you're signed in: a moment of "Opening
/// the Huud…", then the Huud itself in its place.
class HuudLinkLanding extends StatefulWidget {
  const HuudLinkLanding({super.key, required this.code});
  final String code;

  @override
  State<HuudLinkLanding> createState() => _HuudLinkLandingState();
}

class _HuudLinkLandingState extends State<HuudLinkLanding> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  Future<void> _go() async {
    final app = AppScope.of(context);
    app.pendingHuudCode = null; // handled here
    final nav = Navigator.of(context);
    try {
      final raw = await app.api.post('/huud-spaces/join', {'code': widget.code}) as Map<String, dynamic>;
      final huud = HuudSpace.fromJson(raw);
      nav.pushReplacement(huudRoute(huud.id, initial: huud));
    } on ApiException catch (e) {
      if (!mounted) return;
      huudSnack(context, e.status == 404 ? "That Huud isn't around any more." : e.message);
      nav.maybePop();
    } catch (_) {
      if (!mounted) return;
      huudSnack(context, "We couldn't reach PlayHuud. Check your internet.");
      nav.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text('Opening the Huud…', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ])),
      );
}
