import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/invitation.dart';
import '../../core/share_origin.dart';

const invitationGameNames = {
  'chess': 'Chess',
  'draughts': 'Draughts',
  'whot': 'Whot',
  'ludo': 'Ludo',
  'goosi': 'Macala',
  'wordbluff': 'Word Bluff',
  'truearena': 'Traitors',
  'slayhuud': 'SlayHuud',
  'monopoly': 'Huudpoly'
};
String invitationGameAsset(String? game) =>
    'assets/images/game_icons/${switch (game) {
      'draughts' => 'draft',
      'wordbluff' => 'word_bluff',
      'truearena' => 'traitors',
      'monopoly' => 'huudpoly',
      _ => game ?? 'whot'
    }}.png';

class InvitationArtwork {
  const InvitationArtwork(
      {required this.invitation, required this.name, this.gameType});
  final Invitation invitation;
  final String name;
  final String? gameType;
  bool get championship => invitation.kind == InvitationKind.championship;
  String get game => invitationGameNames[gameType] ?? 'Games';
  String get prompt =>
      championship ? 'Can you take the crown?' : 'Good games. Better company.';
  String get shareText => championship
      ? '$prompt Join the $game championship "$name" on PlayHuud!\nPlay as a guest or sign in. Accept your invitation here:\n${invitation.url}'
      : 'You are invited to "$name" on PlayHuud! ${gameType == null ? 'Come hang out and play.' : 'Come play $game with us.'}\nJoin as a guest or sign in:\n${invitation.url}';
}

Future<ui.Image> _asset(String path) async {
  final bytes = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// The exported artwork is generated from the actual brand/game assets.
/// Landscape is also used to build the static Open Graph covers.
Future<ui.Image> renderInvitationArtwork(InvitationArtwork data,
    {bool landscape = false}) async {
  final size = Size(1200, landscape ? 630 : 1500);
  final brand =
      await _asset('assets/images/branding/playhuud-wordmark-transparent.png');
  ui.Image? game;
  final group = <ui.Image>[];
  if (data.gameType != null) {
    game = await _asset(invitationGameAsset(data.gameType));
  } else {
    for (final type in ['ludo', 'whot', 'chess']) {
      group.add(await _asset(invitationGameAsset(type)));
    }
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
            Offset.zero, Offset(size.width, size.height), [
          const Color(0xff101a26),
          const Color(0xff241124),
          const Color(0xff0d111b)
        ], [
          0,
          .55,
          1
        ]));
  canvas.drawCircle(
      Offset(landscape ? 970 : 600, landscape ? 300 : 560),
      landscape ? 330 : 430,
      Paint()
        ..color = const Color(0xffff9e26).withValues(alpha: .12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90));
  final border = Rect.fromLTWH(24, 24, size.width - 48, size.height - 48);
  canvas.drawRRect(
      RRect.fromRectAndRadius(border, const Radius.circular(36)),
      Paint()
        ..color = const Color(0xffdca95c).withValues(alpha: .4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
  void paintAsset(ui.Image image, Rect rect) => paintImage(
      canvas: canvas,
      rect: rect,
      image: image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high);
  paintAsset(
      brand,
      Rect.fromLTWH(landscape ? 70 : 280, landscape ? 55 : 80,
          landscape ? 360 : 640, landscape ? 100 : 160));
  if (game != null) {
    paintAsset(
        game,
        landscape
            ? const Rect.fromLTWH(790, 145, 330, 360)
            : const Rect.fromLTWH(350, 290, 500, 500));
  }
  for (var i = 0; i < group.length; i++) {
    paintAsset(
        group[i],
        landscape
            ? Rect.fromLTWH(795 + i * 30, 180 + i * 65, 250, 250)
            : Rect.fromLTWH(200 + i * 220, 330 + (i == 1 ? 80 : 0), 360, 360));
  }
  final width = landscape ? 680.0 : 1000.0;
  final x = landscape ? 72.0 : 100.0;
  void text(String value, double y, double font, Color color,
      {int lines = 2, FontWeight weight = FontWeight.w800}) {
    final painter = TextPainter(
        text: TextSpan(
            text: value,
            style: TextStyle(
                fontFamily: 'MonopolySans',
                fontSize: font,
                height: 1.13,
                fontWeight: weight,
                color: color)),
        textDirection: TextDirection.ltr,
        textAlign: landscape ? TextAlign.left : TextAlign.center,
        maxLines: lines,
        ellipsis: '…')
      ..layout(maxWidth: width);
    painter.paint(
        canvas, Offset(x + (landscape ? 0 : (width - painter.width) / 2), y));
  }

  const gold = Color(0xffffc56d);
  text(
      data.championship
          ? '${data.game.toUpperCase()} CHAMPIONSHIP'
          : 'YOUR INVITATION',
      landscape ? 185 : 815,
      landscape ? 25 : 32,
      gold,
      lines: 1);
  text(data.prompt, landscape ? 240 : 880, landscape ? 57 : 64, Colors.white);
  text(data.name, landscape ? 395 : 1060, landscape ? 32 : 39,
      const Color(0xffd5c8dc),
      lines: landscape ? 2 : 3);
  text('Play as a guest. Register whenever you want.', landscape ? 515 : 1280,
      landscape ? 21 : 28, gold,
      lines: 1);
  text(
      landscape
          ? 'Open your invitation on PlayHuud'
          : 'playhuud.com${data.invitation.path}',
      landscape ? 555 : 1355,
      landscape ? 20 : 25,
      Colors.white,
      lines: 1,
      weight: FontWeight.w500);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  picture.dispose();
  brand.dispose();
  game?.dispose();
  for (final item in group) {
    item.dispose();
  }
  return image;
}

Future<void> shareInvitation(
    BuildContext context, InvitationArtwork data) async {
  final origin = shareOrigin(context);
  try {
    final image = await renderInvitationArtwork(data);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) throw StateError('Image unavailable');
    final file = File(
        '${(await getTemporaryDirectory()).path}/playhuud-invitation-${data.invitation.code}.png');
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')],
        text: data.shareText,
        subject: data.championship
            ? 'You are invited to ${data.game}'
            : 'Join my Huud on PlayHuud',
        sharePositionOrigin: origin);
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: data.shareText));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Invitation copied — paste it to share.')));
    }
  }
}

class InvitationShareButton extends StatefulWidget {
  const InvitationShareButton({super.key, required this.data});
  final InvitationArtwork data;
  @override
  State<InvitationShareButton> createState() => _InvitationShareButtonState();
}

class _InvitationShareButtonState extends State<InvitationShareButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await shareInvitation(context, widget.data);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      icon: const Icon(Icons.ios_share_rounded),
      label: Text(_busy ? 'Preparing invitation…' : 'Share invitation'));
}
