import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'player_card.dart';

/// Story size: 9:16 at 1080 wide — what WhatsApp Status, Instagram and
/// Facebook stories, and TikTok all expect, so the card isn't cropped.
const ui.Size kStorySize = ui.Size(1080, 1920);

const _site = 'https://playhuud.com';

/// The words that go with the image (most apps show them as the caption).
String playerCardShareText(PlayerCardData card) {
  final id = card.playhuudId == null ? '' : ' ${card.playhuudId}';
  if (card.gameType == null) {
    return 'My PlayHuud player card$id. Come play me: $_site';
  }
  final game = card.title.split(' ').map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase()).join(' ');
  if (card.blank) {
    return 'Come play $game with me on PlayHuud$id: $_site';
  }
  return 'My $game card on PlayHuud — rating ${card.bigValue}, ${card.bigLabel}. Find me:$id $_site';
}

/// Captures the card under [cardKey] (a RepaintBoundary) and composes it
/// into a story-sized image: the card big in the middle on its own colours,
/// PlayHuud branding above, how to find the player below.
Future<ui.Image> composePlayerCardStory(ui.Image cardImage, PlayerCardData card) async {
  final w = kStorySize.width;
  final h = kStorySize.height;
  final t = card.theme;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & kStorySize);

  canvas.drawRect(
      Offset.zero & kStorySize,
      Paint()
        ..shader = ui.Gradient.linear(
            Offset.zero, Offset(w, h), [Color.lerp(t.top, Colors.black, 0.2)!, Colors.black]));
  // A soft glow in the card's colour behind it.
  canvas.drawCircle(
      Offset(w / 2, h * 0.47),
      w * 0.5,
      Paint()
        ..color = t.accent.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 140));

  final cardWidth = w * 0.74;
  final cardHeight = cardWidth * cardImage.height / cardImage.width;
  canvas.drawImageRect(
    cardImage,
    Rect.fromLTWH(0, 0, cardImage.width.toDouble(), cardImage.height.toDouble()),
    Rect.fromCenter(center: Offset(w / 2, h * 0.47), width: cardWidth, height: cardHeight),
    Paint()..filterQuality = FilterQuality.high,
  );

  _text(canvas, 'PLAYHUUD', y: 130, size: 72, color: t.accent, spacing: 16, weight: FontWeight.w900);
  _text(canvas, card.gameType == null ? 'PLAYER CARD' : '${card.title} CARD',
      y: 225, size: 34, color: Colors.white70, spacing: 8, weight: FontWeight.w700);
  _text(canvas, card.playhuudId == null ? 'Play me on PlayHuud' : 'Find me: ${card.playhuudId}',
      y: h - 290, size: 46, color: Colors.white, weight: FontWeight.w800);
  _text(canvas, 'playhuud.com', y: h - 210, size: 40, color: t.accent, spacing: 4, weight: FontWeight.w700);

  return recorder.endRecording().toImage(w.toInt(), h.toInt());
}

void _text(Canvas canvas, String text,
    {required double y, required double size, required Color color, double spacing = 0, FontWeight? weight}) {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, maxLines: 1))
    ..pushStyle(ui.TextStyle(color: color, fontSize: size, letterSpacing: spacing, fontWeight: weight))
    ..addText(text);
  final paragraph = builder.build()..layout(ui.ParagraphConstraints(width: kStorySize.width));
  canvas.drawParagraph(paragraph, Offset(0, y));
}

/// Exports the card as a story image and opens the system share sheet, so it
/// can go to WhatsApp Status, Facebook, Instagram, X, TikTok — anything the
/// phone can share to.
Future<void> sharePlayerCard(GlobalKey cardKey, PlayerCardData card, {Rect? origin}) async {
  final boundary = cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw StateError('the card is not on screen');
  final cardImage = await boundary.toImage(pixelRatio: 4);
  final story = await composePlayerCardStory(cardImage, card);
  cardImage.dispose();
  final bytes = await story.toByteData(format: ui.ImageByteFormat.png);
  story.dispose();
  if (bytes == null) throw StateError('the card could not be captured');
  final slug = (card.gameType ?? 'overall').replaceAll(RegExp('[^a-z]'), '');
  final file = File('${(await getTemporaryDirectory()).path}/playhuud-$slug-card-'
      '${DateTime.now().millisecondsSinceEpoch}.png');
  await file.writeAsBytes(bytes.buffer.asUint8List());
  await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')],
      text: playerCardShareText(card), sharePositionOrigin: origin);
}
