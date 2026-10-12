import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart' show userErrorMessage;
import '../../theme/neon_theme.dart';
import '../../widgets/champion_badge.dart';
import '../../widgets/neon.dart';
import 'card_share.dart' show kStorySize;

/// One championship won — `GET /championships/badges/mine` or `…/badges/user/{id}`.
class ChampionBadgeData {
  const ChampionBadgeData({
    required this.championshipId,
    required this.name,
    required this.awardedAt,
    this.gameType,
    this.players,
  });

  final String championshipId, name;
  final DateTime? awardedAt;
  final String? gameType;
  final int? players;

  String get title => '$name Champion';

  factory ChampionBadgeData.fromJson(Map<String, dynamic> j) => ChampionBadgeData(
        championshipId: j['championshipId'].toString(),
        name: j['name'] as String? ?? 'Championship',
        awardedAt: DateTime.tryParse(j['awardedAt']?.toString() ?? '')?.toLocal(),
        gameType: j['gameType'] as String?,
        players: (j['size'] as num?)?.toInt(),
      );

  static List<ChampionBadgeData> listFrom(Object? raw) =>
      raw is List ? raw.map((e) => ChampionBadgeData.fromJson((e as Map).cast<String, dynamic>())).toList() : const [];
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _won(DateTime d) => 'Won ${d.day} ${_months[d.month - 1]} ${d.year}';

/// The champion badges on a profile — yours or someone else's. Nothing
/// shows until there's a badge to show. Tap one to see it big and share it.
class ChampionBadgesShelf extends StatelessWidget {
  const ChampionBadgesShelf({super.key, required this.badges, required this.handle, required this.own});

  final List<ChampionBadgeData> badges;

  /// The champion's username, for the share caption.
  final String handle;
  final bool own;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    final n = context.neon;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('CHAMPION BADGES', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.gold)),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final b in badges)
            Semantics(
              button: true,
              label: b.title,
              child: InkWell(
                key: ValueKey('champion-badge-${b.championshipId}'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => showChampionBadgeSheet(context, badge: b, handle: handle, own: own),
                child: SizedBox(
                  width: 112,
                  child: Column(children: [
                    ChampionBadge(gameType: b.gameType, players: b.players, width: 104),
                    const SizedBox(height: 4),
                    Text(b.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: n.ink)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }
}

/// The badge up close, with a Share button.
Future<void> showChampionBadgeSheet(BuildContext context,
        {required ChampionBadgeData badge, required String handle, required bool own}) =>
    showNeonSheet<void>(context, builder: (_) => _BadgeSheet(badge: badge, handle: handle, own: own));

class _BadgeSheet extends StatefulWidget {
  const _BadgeSheet({required this.badge, required this.handle, required this.own});
  final ChampionBadgeData badge;
  final String handle;
  final bool own;

  @override
  State<_BadgeSheet> createState() => _BadgeSheetState();
}

class _BadgeSheetState extends State<_BadgeSheet> {
  final _badgeKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _sharing = true);
    try {
      await shareChampionBadge(_badgeKey, widget.badge, handle: widget.handle, own: widget.own, origin: origin);
    } catch (_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text(userErrorMessage)));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final b = widget.badge;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: RepaintBoundary(
              key: _badgeKey,
              child: ChampionBadge(gameType: b.gameType, players: b.players, width: 220),
            ),
          ),
          const SizedBox(height: 8),
          Text(b.title,
              textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: n.gold)),
          if (b.players != null) ...[
            const SizedBox(height: 4),
            Text(ChampionBadge.describe(b.players!, b.gameType),
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: n.mid)),
          ],
          if (b.awardedAt != null) ...[
            const SizedBox(height: 2),
            Text(_won(b.awardedAt!), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: n.mute)),
          ],
          const SizedBox(height: 20),
          NeonButton(
            _sharing ? 'Getting it ready…' : 'Share',
            key: const ValueKey('champion-badge-share'),
            onPressed: _sharing ? null : _share,
          ),
        ]),
      ),
    );
  }
}

/// The words that go with the image.
String championBadgeShareText(ChampionBadgeData b, {required String handle, required bool own}) {
  final field = b.players == null ? '' : ' — ${ChampionBadge.describe(b.players!, b.gameType)}';
  final who = own ? "I'm" : '@$handle is';
  return '$who the ${b.name} champion on PlayHuud 🏆$field. Come play: https://playhuud.com';
}

/// Captures the badge under [badgeKey] (a RepaintBoundary), sets it in a
/// story-sized image — the size WhatsApp Status, Instagram and TikTok expect —
/// and opens the share sheet.
Future<void> shareChampionBadge(GlobalKey badgeKey, ChampionBadgeData badge,
    {required String handle, required bool own, Rect? origin}) async {
  final boundary = badgeKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw StateError('the badge is not on screen');
  final badgeImage = await boundary.toImage(pixelRatio: 4);
  final story = await composeChampionBadgeStory(badgeImage, badge, handle: handle);
  badgeImage.dispose();
  final bytes = await story.toByteData(format: ui.ImageByteFormat.png);
  story.dispose();
  if (bytes == null) throw StateError('the badge could not be captured');
  final file = File('${(await getTemporaryDirectory()).path}/playhuud-champion-'
      '${DateTime.now().millisecondsSinceEpoch}.png');
  await file.writeAsBytes(bytes.buffer.asUint8List());
  await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')],
      text: championBadgeShareText(badge, handle: handle, own: own), sharePositionOrigin: origin);
}

const _storyGold = Color(0xFFF7C948);

Future<ui.Image> composeChampionBadgeStory(ui.Image badgeImage, ChampionBadgeData b, {required String handle}) {
  final w = kStorySize.width;
  final h = kStorySize.height;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & kStorySize);
  canvas.drawRect(Offset.zero & kStorySize,
      Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(w, h), const [Color(0xFF2B2108), Colors.black]));
  // A warm glow behind the shield.
  canvas.drawCircle(
      Offset(w / 2, h * 0.45),
      w * 0.48,
      Paint()
        ..color = _storyGold.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 140));

  final badgeWidth = w * 0.82;
  final badgeHeight = badgeWidth * badgeImage.height / badgeImage.width;
  canvas.drawImageRect(
    badgeImage,
    Rect.fromLTWH(0, 0, badgeImage.width.toDouble(), badgeImage.height.toDouble()),
    Rect.fromCenter(center: Offset(w / 2, h * 0.43), width: badgeWidth, height: badgeHeight),
    Paint()..filterQuality = FilterQuality.high,
  );

  _text(canvas, 'PLAYHUUD', y: 130, size: 72, color: _storyGold, spacing: 16, weight: FontWeight.w900);
  _text(canvas, 'CHAMPION', y: 225, size: 40, color: Colors.white70, spacing: 12, weight: FontWeight.w800);
  _text(canvas, b.name, y: h - 520, size: 64, color: Colors.white, weight: FontWeight.w900);
  if (b.players != null) {
    _text(canvas, ChampionBadge.describe(b.players!, b.gameType),
        y: h - 430, size: 40, color: Colors.white70, weight: FontWeight.w700);
  }
  if (handle.isNotEmpty) _text(canvas, '@$handle', y: h - 290, size: 50, color: _storyGold, weight: FontWeight.w800);
  _text(canvas, 'playhuud.com', y: h - 210, size: 40, color: Colors.white70, spacing: 4, weight: FontWeight.w700);
  return recorder.endRecording().toImage(w.toInt(), h.toInt());
}

void _text(Canvas canvas, String text,
    {required double y, required double size, required Color color, double spacing = 0, FontWeight? weight}) {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, maxLines: 1, ellipsis: '…'))
    ..pushStyle(ui.TextStyle(color: color, fontSize: size, letterSpacing: spacing, fontWeight: weight))
    ..addText(text);
  final paragraph = builder.build()..layout(ui.ParagraphConstraints(width: kStorySize.width - 80));
  canvas.drawParagraph(paragraph, Offset(40, y));
}
