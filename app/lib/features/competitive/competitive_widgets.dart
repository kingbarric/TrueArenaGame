import 'package:flutter/material.dart';

import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import 'competitive_models.dart';

/// Another player's avatar. `avatarUrl` is either a bare preset emoji or an
/// image (inline `data:` or http) — routed to the right [Avatar] slot so an
/// emoji never gets fetched as a URL.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({super.key, required this.name, this.avatarUrl, this.size = 36});

  final String name;
  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    final isImage = url != null && (url.startsWith('data:image/') || url.startsWith('http'));
    return Avatar(name,
        size: size,
        imageUrl: isImage ? url : null,
        emoji: !isImage && url != null && url.isNotEmpty ? url : null);
  }
}

/// "FOUNDING 1,000" — early-adopter status, permanent, derived from the
/// PlayHuud number. Gold, because it's the one thing nobody can earn later.
class FoundingBadge extends StatelessWidget {
  const FoundingBadge(this.tier, {super.key, this.compact = false});

  final FoundingTier tier;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: n.gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: n.gold.withValues(alpha: 0.7)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.workspace_premium_rounded, size: compact ? 11 : 14, color: n.gold),
        SizedBox(width: compact ? 3 : 5),
        Text(tier.label.toUpperCase(),
            style: TextStyle(
                color: n.gold,
                fontWeight: FontWeight.w900,
                fontSize: compact ? 8.5 : 10.5,
                letterSpacing: compact ? 0.6 : 1.1)),
      ]),
    );
  }
}

/// "PLAYHUUD #000127" in a monospaced, ID-card style.
class PlayhuudIdLabel extends StatelessWidget {
  const PlayhuudIdLabel(this.id, {super.key, this.fontSize = 12});

  final String id;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Text.rich(
      TextSpan(children: [
        TextSpan(
            text: 'PLAYHUUD ',
            style: TextStyle(color: n.mute, fontWeight: FontWeight.w800, letterSpacing: 1.4, fontSize: fontSize * 0.8)),
        TextSpan(
            text: id,
            style: TextStyle(
                color: n.ink,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                fontSize: fontSize,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

/// One rank on one board. A real rank is the hero — big and gold; anything
/// else explains what's missing rather than showing a meaningless number.
class RankTile extends StatelessWidget {
  const RankTile({
    super.key,
    required this.label,
    required this.rank,
    this.onTap,
    this.onCompleteProfile,
    this.placement,
  });

  final String label;
  final RankInfo rank;
  final VoidCallback? onTap;
  final VoidCallback? onCompleteProfile;

  /// "5 / 10" while provisional.
  final String? placement;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = Theme.of(context).textTheme;
    final Widget value;
    switch (rank.status) {
      case RankInfo.ranked:
        value = Text('#${_grouped(rank.rank ?? 0)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.displayLarge?.copyWith(fontSize: 24, color: n.gold));
      case RankInfo.locationRequired:
        value = Text('Complete profile',
            style: t.labelSmall?.copyWith(color: n.brand, fontWeight: FontWeight.w800));
      case RankInfo.provisional:
        value = Text(placement == null ? 'Placement' : 'Placement $placement',
            style: t.labelSmall?.copyWith(color: n.mid, fontWeight: FontWeight.w800));
      default:
        value = Text('Unranked', style: t.labelSmall?.copyWith(color: n.mute, fontWeight: FontWeight.w800));
    }
    final tap = rank.status == RankInfo.locationRequired ? onCompleteProfile : onTap;
    return NeonCard(
      onTap: tap,
      accent: rank.isRanked ? n.gold : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: n.mute, fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 1)),
        const SizedBox(height: 6),
        SizedBox(height: 30, child: Align(alignment: Alignment.centerLeft, child: value)),
      ]),
    );
  }
}

/// Small labelled number, matching the profile's existing stat tiles.
class StatTile extends StatelessWidget {
  const StatTile(this.label, this.value, {super.key, this.accent});

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final color = accent ?? n.ink;
    return NeonCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: n.mute, fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 1)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              maxLines: 1, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 20, color: color)),
        ),
      ]),
    );
  }
}

/// "+14" in green, "−9" in red, nothing for an unrated game.
class RatingDelta extends StatelessWidget {
  const RatingDelta(this.delta, {super.key, this.fontSize = 13});

  final int? delta;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    if (d == null) return const SizedBox.shrink();
    final n = context.neon;
    final color = d > 0 ? n.jade : (d < 0 ? n.danger : n.mute);
    final text = d > 0 ? '+$d' : (d < 0 ? '−${-d}' : '±0');
    return Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: fontSize));
  }
}

/// A row of earned badges, highest-prestige first.
class AchievementShelf extends StatelessWidget {
  const AchievementShelf({super.key, required this.achievements});

  final List<Achievement> achievements;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final a in achievements)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: (a.isFounding ? n.gold : n.panel).withValues(alpha: a.isFounding ? 0.12 : 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _rarityColor(n, a.rarity).withValues(alpha: 0.75)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(a.icon, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text(a.label,
                style: TextStyle(color: n.ink, fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
        ),
    ]);
  }

  static Color _rarityColor(NeonColors n, String rarity) => switch (rarity) {
        'legendary' => n.gold,
        'epic' => n.brand,
        'rare' => n.jade,
        _ => n.line,
      };
}

/// `12421 -> "12,421"`.
String _grouped(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String groupedNumber(int n) => _grouped(n);
