import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/neon_theme.dart';
import '../games/game_select_screen.dart' show gameCatalog;
import 'competitive_models.dart';
import 'competitive_widgets.dart';

/// Each game's card livery. Overall is black and gold; every game gets its
/// own pair so a player's cards read as a set, not as one card recoloured.
class PlayerCardTheme {
  const PlayerCardTheme({
    required this.top,
    required this.bottom,
    required this.accent,
    required this.secondary,
    required this.ink,
    required this.icon,
  });

  final Color top;
  final Color bottom;

  /// Numbers, name, border — the colour the card is remembered by.
  final Color accent;

  /// The swoosh and pattern behind the player.
  final Color secondary;
  final Color ink;
  final String icon;

  static const overall = PlayerCardTheme(
      top: Color(0xff1d1d24), bottom: Color(0xff07070a), accent: Color(0xfff5c542),
      secondary: Color(0xff8a6d1f), ink: Colors.white, icon: '👑');

  static const _byGame = <String, PlayerCardTheme>{
    // Teal and electric yellow.
    'draughts': PlayerCardTheme(
        top: Color(0xff12606a), bottom: Color(0xff062a30), accent: Color(0xfff2e41a),
        secondary: Color(0xff2fd3c6), ink: Colors.white, icon: '⚫'),
    // Shattered black and lime.
    'whot': PlayerCardTheme(
        top: Color(0xff2a2a2a), bottom: Color(0xff0b0b0b), accent: Color(0xffb6ff2e),
        secondary: Color(0xff5f6b4a), ink: Colors.white, icon: '🔴'),
    'ludo': PlayerCardTheme(
        top: Color(0xff4a1a6b), bottom: Color(0xff1a0827), accent: Color(0xffff6fd8),
        secondary: Color(0xff9b4dff), ink: Colors.white, icon: '🎲'),
    'goosi': PlayerCardTheme(
        top: Color(0xff175a35), bottom: Color(0xff072014), accent: Color(0xffffb84d),
        secondary: Color(0xff3fbf7f), ink: Colors.white, icon: '🫘'),
    // Blood red — distinct from Ludo's pink.
    'truearena': PlayerCardTheme(
        top: Color(0xff6b0f14), bottom: Color(0xff1c0406), accent: Color(0xffff3b30),
        secondary: Color(0xffa3161d), ink: Colors.white, icon: '🎭'),
    'bluff': PlayerCardTheme(
        top: Color(0xff0f3b5c), bottom: Color(0xff061624), accent: Color(0xff6ee7ff),
        secondary: Color(0xff2b7fb8), ink: Colors.white, icon: '🗣️'),
    'chess': PlayerCardTheme(
        top: Color(0xff3d2a1a), bottom: Color(0xff150d07), accent: Color(0xffffe1a8),
        secondary: Color(0xff9c6b3c), ink: Colors.white, icon: '♟️'),
  };

  /// Word Bluff is `bluff` in the app's catalog and `wordbluff` on the server.
  static PlayerCardTheme forGame(String gameType) =>
      _byGame[gameType == 'wordbluff' ? 'bluff' : gameType] ??
      const PlayerCardTheme(
          top: Color(0xff2b3140), bottom: Color(0xff0e1117), accent: Color(0xff9ecbff),
          secondary: Color(0xff4d6a8f), ink: Colors.white, icon: '🎮');
}

/// One stat line on the card: "68% WIN".
class CardStat {
  const CardStat(this.value, this.label);
  final String value;
  final String label;
}

/// Everything a card face shows. Built from a [CompetitiveProfile] by
/// [buildPlayerCards]; a blank card is just one whose values are "—".
class PlayerCardData {
  const PlayerCardData({
    required this.title,
    required this.theme,
    required this.bigValue,
    required this.bigLabel,
    required this.name,
    required this.stats,
    this.gameType,
    this.avatarUrl,
    this.playhuudId,
    this.founding,
    this.blank = false,
    this.ranked = false,
  });

  /// "OVERALL", "DRAFT"…
  final String title;
  final PlayerCardTheme theme;

  /// The corner number (rating) and the line under it (rank / status).
  final String bigValue;
  final String bigLabel;
  final String name;

  /// Six, laid out as two columns of three.
  final List<CardStat> stats;

  /// Null for the Overall card.
  final String? gameType;
  final String? avatarUrl;
  final String? playhuudId;
  final FoundingTier? founding;
  final bool blank;

  /// The game has a skill rating and rankings (only some do so far), so the
  /// card can open a detail page. Overall is always openable-free.
  final bool ranked;
}

/// The cards for a profile: Overall first, then one per rated game.
///
/// Overall is deliberately NOT a blended skill rating — there is no universal
/// rating by design. Its corner shows the player's best game rating, labelled
/// with that game, and the rest is career totals.
///
/// Every game gets a card, played or not — a game with no data shows its
/// card blank, in its own colours. Ranked games come first (Draughts leads),
/// then the rest in catalog order.
List<PlayerCardData> buildPlayerCards(CompetitiveProfile p,
    {List<String> ratedGames = const ['draughts'], List<String>? allGames}) {
  final catalog = allGames ?? [for (final g in gameCatalog) if (g.available) g.id];
  final order = <String>[
    for (final g in ratedGames) g,
    for (final g in catalog)
      if (!ratedGames.contains(g) && !(g == 'bluff' && ratedGames.contains('wordbluff'))) g,
  ];
  GameRecord? recordFor(String id) => p.game(id) ?? (id == 'bluff' ? p.game('wordbluff') : null);
  final records = <GameRecord>[
    for (final id in order) recordFor(id) ?? GameRecord(gameType: id),
    // Anything rated the catalog doesn't list (yet) still shows.
    for (final r in p.games)
      if (!order.contains(r.gameType) && !(r.gameType == 'wordbluff' && order.contains('bluff'))) r,
  ];
  final name = p.displayName;

  final rated = records.where((r) => r.hasRating).toList()
    ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
  final best = rated.isEmpty ? null : rated.first;
  final games = records.fold<int>(0, (s, r) => s + r.stats.gamesPlayed);
  final wins = records.fold<int>(0, (s, r) => s + r.stats.wins);
  final titles = records.fold<int>(0, (s, r) => s + r.stats.tournamentWins);
  final bestStreak = records.fold<int>(0, (s, r) => math.max(s, r.stats.bestWinStreak));
  final badges = p.achievements.where((a) => !a.isFounding).length;
  int? bestCountryRank;
  for (final r in records) {
    final rank = r.ranks.country.isRanked ? r.ranks.country.rank : null;
    if (rank != null && (bestCountryRank == null || rank < bestCountryRank)) bestCountryRank = rank;
  }

  final overall = PlayerCardData(
    title: 'OVERALL',
    theme: PlayerCardTheme.overall,
    bigValue: best?.rating?.toString() ?? '—',
    bigLabel: best == null ? 'OVR' : _code(best.gameType),
    name: name,
    avatarUrl: p.avatarUrl,
    playhuudId: p.playhuudId,
    founding: p.founding,
    blank: best == null && games == 0,
    stats: [
      CardStat(games == 0 ? '—' : _compact(games), 'GMS'),
      CardStat(games == 0 ? '—' : '${(wins * 100 / games).round()}%', 'WIN'),
      CardStat(titles == 0 ? '—' : '$titles', 'TTL'),
      CardStat(bestStreak == 0 ? '—' : '$bestStreak', 'BST'),
      CardStat(badges == 0 ? '—' : '$badges', 'BDG'),
      CardStat(bestCountryRank == null ? '—' : '#${_compact(bestCountryRank)}', 'RNK'),
    ],
  );

  return [
    overall,
    for (final r in records)
      _gameCard(p, r, name,
          ranked: ratedGames.contains(r.gameType) || (r.gameType == 'bluff' && ratedGames.contains('wordbluff'))),
  ];
}

PlayerCardData _gameCard(CompetitiveProfile p, GameRecord r, String name, {required bool ranked}) {
  final s = r.stats;
  final String label;
  if (!r.hasRating) {
    label = 'UNRATED';
  } else if (r.provisional) {
    label = 'PROV ${r.placementGamesPlayed}/${r.placementGamesRequired}';
  } else if (r.ranks.country.isRanked && p.location?.countryCode != null) {
    label = '${p.location!.countryCode} #${_compact(r.ranks.country.rank!)}';
  } else if (r.ranks.global.isRanked) {
    label = 'GLB #${_compact(r.ranks.global.rank!)}';
  } else {
    label = 'RATED';
  }
  final played = s.gamesPlayed > 0;
  return PlayerCardData(
    title: r.name.toUpperCase(),
    theme: PlayerCardTheme.forGame(r.gameType),
    gameType: r.gameType,
    bigValue: r.rating?.toString() ?? '—',
    bigLabel: label,
    name: name,
    avatarUrl: p.avatarUrl,
    playhuudId: p.playhuudId,
    founding: p.founding,
    blank: !r.hasRating,
    ranked: ranked,
    stats: [
      CardStat(played ? _compact(s.gamesPlayed) : '—', 'GMS'),
      CardStat(played ? '${(s.winRate * 100).round()}%' : '—', 'WIN'),
      CardStat(played ? '${s.currentWinStreak}' : '—', 'STK'),
      CardStat(r.peakRating?.toString() ?? '—', 'PEK'),
      CardStat(played ? '${s.bestWinStreak}' : '—', 'BST'),
      CardStat(s.tournamentWins == 0 ? '—' : '${s.tournamentWins}', 'TTL'),
    ],
  );
}

/// 'draughts' -> 'DRA'.
String _code(String gameType) {
  final name = gameDisplayName(gameType).replaceAll(RegExp('[^A-Za-z]'), '');
  return (name.length >= 3 ? name.substring(0, 3) : name).toUpperCase();
}

/// 127 -> "127", 12421 -> "12.4K", 1250000 -> "1.3M".
String _compact(int n) {
  if (n < 10000) return groupedNumber(n);
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(n < 100000 ? 1 : 0)}K';
  return '${(n / 1000000).toStringAsFixed(1)}M';
}

// ---------------------------------------------------------------- the card

/// Card proportions — the shield is taller than wide, like a trading card.
const double kPlayerCardAspect = 0.68;

/// A FUT-style shield card. Sized by its parent's width.
class PlayerCard extends StatelessWidget {
  const PlayerCard({super.key, required this.data, this.shine = 0, this.glow = true});

  final PlayerCardData data;

  /// The soft halo round the shield. Off when the card is captured for
  /// sharing: the capture is a rectangle, so the halo would end in hard
  /// square edges — the story image draws its own glow instead.
  final bool glow;

  /// 0..1 progress of a light sweep across the face (0 = none).
  final double shine;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: kPlayerCardAspect,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final t = data.theme;
        final dim = data.blank;
        final numberStyle = TextStyle(
          color: t.accent.withValues(alpha: dim ? 0.55 : 1),
          fontWeight: FontWeight.w900,
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        return CustomPaint(
          painter: glow ? _ShieldGlowPainter(t.accent) : null,
          child: ClipPath(
            clipper: const ShieldClipper(),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _CardArtPainter(t))),
              // The player — big, right of centre, like the photo slot on a FUT card.
              Positioned(
                right: w * 0.06,
                top: h * 0.12,
                width: w * 0.52,
                height: w * 0.52,
                child: Opacity(
                  opacity: dim ? 0.8 : 1,
                  child: _CardPortrait(data: data, size: w * 0.52),
                ),
              ),
              // Corner: rating and what it means.
              Positioned(
                left: w * 0.08,
                top: h * 0.10,
                // Stops short of the portrait (which starts at 0.42w), so a long
                // rank line scales down instead of running under the circle.
                width: w * 0.32,
                child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  FittedBox(
                    child: Text(data.bigValue,
                        key: ValueKey('card-big-${data.title}'), style: numberStyle.copyWith(fontSize: w * 0.17)),
                  ),
                  SizedBox(height: h * 0.006),
                  FittedBox(
                    child: Text(data.bigLabel,
                        style: TextStyle(
                            color: t.accent, fontWeight: FontWeight.w800, fontSize: w * 0.058, letterSpacing: 0.5)),
                  ),
                  SizedBox(height: h * 0.012),
                  Text(t.icon, style: TextStyle(fontSize: w * 0.07)),
                  if (data.founding != null) ...[
                    SizedBox(height: h * 0.01),
                    _FoundingMark(label: data.founding!.label, theme: t, width: w * 0.28,
                        key: ValueKey('card-founding-${data.title}')),
                  ],
                ]),
              ),
              // Small title tab at the top centre.
              Positioned(
                top: h * 0.035,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: w * 0.6,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(data.title,
                          maxLines: 1,
                          style: TextStyle(
                              color: t.accent.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w900,
                              fontSize: w * 0.038,
                              letterSpacing: 2.4)),
                    ),
                  ),
                ),
              ),
              // Name plate.
              Positioned(
                left: w * 0.08,
                right: w * 0.08,
                top: h * 0.55,
                child: Column(children: [
                  FittedBox(
                    child: Text(data.name.toUpperCase(),
                        maxLines: 1,
                        style: TextStyle(
                            color: t.accent,
                            fontWeight: FontWeight.w900,
                            fontSize: w * 0.105,
                            letterSpacing: 1.2,
                            shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 6)])),
                  ),
                  SizedBox(height: h * 0.008),
                  Container(height: 1.4, color: t.accent.withValues(alpha: 0.55)),
                ]),
              ),
              // Stats: two columns of three, split by a hairline.
              Positioned(
                left: w * 0.1,
                right: w * 0.1,
                top: h * 0.66,
                height: h * 0.19,
                child: Row(children: [
                  Expanded(child: _statColumn(data.stats.take(3).toList(), numberStyle, w, t)),
                  Container(width: 1.2, margin: EdgeInsets.symmetric(horizontal: w * 0.03),
                      color: t.accent.withValues(alpha: 0.45)),
                  Expanded(child: _statColumn(data.stats.skip(3).take(3).toList(), numberStyle, w, t)),
                ]),
              ),
              // Footer: the PlayHuud number as one compact pill. The shield
              // narrows to a point here, so the pill is held well inside it
              // (it used to carry two lines that ran off the edges).
              if (data.playhuudId != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: h * 0.868,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: w * 0.42, maxHeight: h * 0.05),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                          key: ValueKey('card-number-${data.title}'),
                          padding: EdgeInsets.symmetric(horizontal: w * 0.03, vertical: w * 0.006),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(w * 0.04),
                            border: Border.all(color: t.accent.withValues(alpha: 0.55), width: 1),
                          ),
                          child: Text(data.playhuudId!,
                              maxLines: 1,
                              style: TextStyle(
                                  color: t.ink,
                                  fontWeight: FontWeight.w900,
                                  fontSize: w * 0.04,
                                  letterSpacing: 1,
                                  fontFeatures: const [FontFeature.tabularFigures()])),
                        ),
                      ),
                    ),
                  ),
                ),
              if (shine > 0 && shine < 1)
                Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _ShinePainter(shine)))),
            ]),
          ),
        );
      }),
    );
  }

  Widget _statColumn(List<CardStat> stats, TextStyle numberStyle, double w, PlayerCardTheme t) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in stats)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(s.value, style: numberStyle.copyWith(fontSize: w * 0.068, color: t.ink)),
              SizedBox(width: w * 0.02),
              Text(s.label,
                  style: TextStyle(
                      color: t.accent, fontWeight: FontWeight.w800, fontSize: w * 0.06, letterSpacing: 0.5)),
            ]),
          ),
      ],
    );
  }
}

/// Founding status as a small two-line mark under the corner rating — the
/// slot a FUT card uses for nation/club — so the footer only has to hold
/// the number.
class _FoundingMark extends StatelessWidget {
  const _FoundingMark({super.key, required this.label, required this.theme, required this.width});

  final String label;
  final PlayerCardTheme theme;
  final double width;

  @override
  Widget build(BuildContext context) {
    // "Founding 1,000" → "FOUNDING" over "1,000".
    final parts = label.toUpperCase().split(' ');
    final tier = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    return SizedBox(
      width: width,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: width * 0.08, vertical: width * 0.03),
          decoration: BoxDecoration(
            color: theme.accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(width * 0.08),
            border: Border.all(color: theme.accent.withValues(alpha: 0.8)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(parts.first,
                style: TextStyle(color: theme.accent, fontWeight: FontWeight.w900,
                    fontSize: width * 0.13, letterSpacing: 1, height: 1.1)),
            if (tier.isNotEmpty)
              Text(tier,
                  style: TextStyle(color: theme.ink, fontWeight: FontWeight.w900,
                      fontSize: width * 0.17, height: 1.1)),
          ]),
        ),
      ),
    );
  }
}

/// The player's slot. A photo or preset emoji when they have one; otherwise
/// their initial on a medallion tinted to the card, so a new account's card
/// still looks finished rather than like a placeholder.
class _CardPortrait extends StatelessWidget {
  const _CardPortrait({required this.data, required this.size});

  final PlayerCardData data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = data.theme;
    final url = data.avatarUrl;
    final hasPicture = url != null && url.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [
          t.secondary.withValues(alpha: 0.55),
          t.bottom.withValues(alpha: 0.9),
        ]),
        border: Border.all(color: t.accent, width: size * 0.025),
        boxShadow: [BoxShadow(color: t.accent.withValues(alpha: 0.35), blurRadius: size * 0.18)],
      ),
      alignment: Alignment.center,
      child: hasPicture
          ? Padding(
              padding: EdgeInsets.all(size * 0.025),
              child: PlayerAvatar(name: data.name, avatarUrl: url, size: size * 0.95),
            )
          : Text(
              data.name.isEmpty ? '?' : data.name.characters.first.toUpperCase(),
              style: TextStyle(
                color: t.accent,
                fontWeight: FontWeight.w900,
                fontSize: size * 0.48,
                height: 1,
                shadows: [Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: size * 0.08)],
              ),
            ),
    );
  }
}

/// The shield: notched shoulders at the top, straight flanks, and a softly
/// pointed base — a trading-card silhouette rather than a rectangle.
class ShieldClipper extends CustomClipper<Path> {
  const ShieldClipper();

  static Path pathFor(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(0, h * 0.10)
      ..quadraticBezierTo(w * 0.01, h * 0.03, w * 0.11, h * 0.028)
      ..quadraticBezierTo(w * 0.28, h * 0.026, w * 0.37, 0)
      ..lineTo(w * 0.63, 0)
      ..quadraticBezierTo(w * 0.72, h * 0.026, w * 0.89, h * 0.028)
      ..quadraticBezierTo(w * 0.99, h * 0.03, w, h * 0.10)
      ..lineTo(w, h * 0.80)
      ..quadraticBezierTo(w * 0.99, h * 0.875, w * 0.82, h * 0.915)
      ..quadraticBezierTo(w * 0.60, h * 0.955, w * 0.5, h)
      ..quadraticBezierTo(w * 0.40, h * 0.955, w * 0.18, h * 0.915)
      ..quadraticBezierTo(w * 0.01, h * 0.875, 0, h * 0.80)
      ..close();
  }

  @override
  Path getClip(Size size) => pathFor(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Glow and rim around the shield, painted outside the clip.
class _ShieldGlowPainter extends CustomPainter {
  _ShieldGlowPainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final path = ShieldClipper.pathFor(size);
    canvas.drawPath(
        path,
        Paint()
          ..color = accent.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 14));
  }

  @override
  bool shouldRepaint(covariant _ShieldGlowPainter old) => old.accent != accent;
}

/// The card's artwork: gradient field, two sweeping bands, a halftone patch,
/// a few speed streaks and an inner rim — all in the game's colours.
class _CardArtPainter extends CustomPainter {
  _CardArtPainter(this.t);
  final PlayerCardTheme t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [t.top, t.bottom],
          ).createShader(rect));

    // Wide swoosh band behind the player.
    final band = Path()
      ..moveTo(-w * 0.1, h * 0.62)
      ..quadraticBezierTo(w * 0.35, h * 0.30, w * 1.1, h * 0.12)
      ..lineTo(w * 1.1, h * 0.28)
      ..quadraticBezierTo(w * 0.45, h * 0.42, -w * 0.1, h * 0.74)
      ..close();
    canvas.drawPath(band, Paint()..color = t.secondary.withValues(alpha: 0.32));

    // Thin bright stroke riding the band.
    final stroke = Path()
      ..moveTo(-w * 0.05, h * 0.58)
      ..quadraticBezierTo(w * 0.38, h * 0.30, w * 1.05, h * 0.16);
    canvas.drawPath(
        stroke,
        Paint()
          ..color = t.accent.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.012);

    // Lower sweep, under the name plate.
    final lower = Path()
      ..moveTo(-w * 0.1, h * 0.56)
      ..quadraticBezierTo(w * 0.55, h * 0.44, w * 1.1, h * 0.50)
      ..lineTo(w * 1.1, h * 0.54)
      ..quadraticBezierTo(w * 0.55, h * 0.48, -w * 0.1, h * 0.60)
      ..close();
    canvas.drawPath(lower, Paint()..color = t.accent.withValues(alpha: 0.55));

    // Halftone dots, fading toward the edge.
    final dot = Paint()..color = t.accent.withValues(alpha: 0.35);
    final step = w * 0.045;
    for (double y = h * 0.30; y < h * 0.50; y += step) {
      for (double x = w * 0.45; x < w; x += step) {
        final fade = ((x - w * 0.45) / (w * 0.55)).clamp(0.0, 1.0);
        canvas.drawCircle(Offset(x, y), w * 0.006 * (0.4 + fade), dot);
      }
    }

    // Speed streaks, top left.
    final streak = Paint()
      ..color = t.accent.withValues(alpha: 0.5)
      ..strokeWidth = w * 0.008
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final y = h * (0.07 + i * 0.022);
      canvas.drawLine(Offset(w * (0.62 + i * 0.05), y), Offset(w * (0.80 + i * 0.04), y - h * 0.03), streak);
    }

    // Darken the stats area so numbers stay readable on any livery.
    canvas.drawRect(
        Rect.fromLTWH(0, h * 0.62, w, h * 0.38),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.45)],
          ).createShader(Rect.fromLTWH(0, h * 0.62, w, h * 0.38)));

    // Inner rim, just inside the clip edge.
    canvas.save();
    canvas.translate(w * 0.025, h * 0.018);
    canvas.scale(0.95, 0.964);
    canvas.drawPath(
        ShieldClipper.pathFor(size),
        Paint()
          ..color = t.accent.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.01);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CardArtPainter old) => old.t != t;
}

/// A diagonal foil glint that crosses the card once.
class _ShinePainter extends CustomPainter {
  _ShinePainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final x = -size.width + progress * size.width * 3;
    final rect = Rect.fromLTWH(x, 0, size.width * 0.5, size.height);
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.22),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0.3, 0.5, 0.7],
          ).createShader(rect)
          ..blendMode = BlendMode.plus);
  }

  @override
  bool shouldRepaint(covariant _ShinePainter old) => old.progress != progress;
}

// ---------------------------------------------------------------- the carousel

/// The cards on a ring: the current card faces you at the front, its
/// neighbours turn away on either side and sink back, further cards fade
/// out behind. Drag or flick to spin it; it always settles with one card
/// squarely at the front, which glints once as it lands.
///
/// Not a PageView: a PageView paints the next card over the current one,
/// and a ring needs the front card on top. Here the cards are drawn far to
/// near, so the front one is always last (and is the one you tap).
class PlayerCardCarousel extends StatefulWidget {
  const PlayerCardCarousel({super.key, required this.cards, this.onOpen, this.onShare});

  final List<PlayerCardData> cards;

  /// Tapping the front card — e.g. to open that game's details.
  final void Function(PlayerCardData card)? onOpen;

  /// Shows a Share button for the front card. Gets the card's capture key
  /// and the button's rect (the iPad share sheet anchors to it).
  final Future<void> Function(PlayerCardData card, GlobalKey cardKey, Rect? origin)? onShare;

  @override
  State<PlayerCardCarousel> createState() => _PlayerCardCarouselState();
}

class _PlayerCardCarouselState extends State<PlayerCardCarousel> with TickerProviderStateMixin {
  /// Continuous position on the ring: 0 = first card at the front, 1.5 =
  /// halfway between the second and third.
  late final AnimationController _position = AnimationController.unbounded(vsync: this);
  late final AnimationController _shine =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late List<GlobalKey> _captureKeys = _keysFor(widget.cards.length);
  int _current = 0;
  double _cardWidth = 200;
  bool _sharing = false;

  static List<GlobalKey> _keysFor(int n) => [for (var i = 0; i < n; i++) GlobalKey()];

  @override
  void initState() {
    super.initState();
    _position.addListener(_track);
    _shine.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant PlayerCardCarousel old) {
    super.didUpdateWidget(old);
    if (old.cards.length != widget.cards.length) {
      _captureKeys = _keysFor(widget.cards.length);
      final last = (widget.cards.length - 1).clamp(0, 1 << 20).toDouble();
      if (_position.value > last) _position.value = last;
    }
  }

  @override
  void dispose() {
    _position.dispose();
    _shine.dispose();
    super.dispose();
  }

  int get _last => widget.cards.length - 1;

  void _track() {
    final i = _position.value.round().clamp(0, _last);
    if (i != _current) setState(() => _current = i);
  }

  void _settle(int target) {
    final to = target.clamp(0, _last).toDouble();
    _position
        .animateTo(to, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic)
        .whenComplete(() {
      if (mounted && (_position.value - to).abs() < 0.001) _shine.forward(from: 0);
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _position.stop();
    _position.value = (_position.value - (d.primaryDelta ?? 0) / (_cardWidth * 0.8))
        .clamp(-0.35, _last + 0.35);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final at = _position.value;
    final target = v < -250 ? at.floor() + 1 : (v > 250 ? at.ceil() - 1 : at.round());
    _settle(target);
  }

  Future<void> _share(BuildContext buttonContext) async {
    final onShare = widget.onShare;
    if (onShare == null || _sharing) return;
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _sharing = true); // no glint in the exported image
    try {
      await WidgetsBinding.instance.endOfFrame;
      await onShare(widget.cards[_current], _captureKeys[_current], origin);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _cardOnRing(int i, double position, double cardWidth) {
    final d = i - position;
    final angle = (d * 0.55).clamp(-1.35, 1.35); // radians round the ring per card
    final depth = math.cos(angle); // 1 at the front, ~0.2 at the sides
    final x = math.sin(angle) * cardWidth * 0.92;
    final scale = 0.58 + 0.42 * depth;
    final sink = (1 - depth) * 26;
    final opacity = ((depth - 0.2) / 0.8).clamp(0.0, 1.0);
    final card = widget.cards[i];
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0013) // perspective
      ..translateByDouble(x, sink, 0, 1)
      ..rotateY(-angle * 0.85) // turn to face the centre of the ring
      ..scaleByDouble(scale, scale, 1, 1);
    return Transform(
      key: ValueKey('ring-$i'),
      alignment: Alignment.center,
      transform: transform,
      child: Opacity(
        opacity: opacity,
        child: SizedBox(
          width: cardWidth,
          child: GestureDetector(
            onTap: () {
              if (i == _current && (position - i).abs() < 0.05) {
                widget.onOpen?.call(card);
              } else {
                _settle(i);
              }
            },
            child: RepaintBoundary(
              key: _captureKeys[i],
              child: PlayerCard(
                key: ValueKey('player-card-${card.title}'),
                data: card,
                shine: i == _current && !_sharing ? _shine.value : 0,
                glow: !(i == _current && _sharing),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    if (widget.cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      final cardWidth = math.min(box.maxWidth * 0.6, 300.0);
      _cardWidth = cardWidth;
      final height = cardWidth / kPlayerCardAspect + 36;
      return Column(children: [
        GestureDetector(
          key: const ValueKey('player-card-carousel'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _position.stop(),
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: Listenable.merge([_position, _shine]),
              builder: (context, _) {
                final position = _position.value;
                // Far cards first, the front card last — so it sits on top.
                final order = [for (var i = 0; i < widget.cards.length; i++) i]
                  ..removeWhere((i) => (i - position).abs() > 3.2)
                  ..sort((a, b) => (b - position).abs().compareTo((a - position).abs()));
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [for (final i in order) _cardOnRing(i, position, cardWidth)],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (var i = 0; i < widget.cards.length; i++)
                GestureDetector(
                  onTap: () => _settle(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: i == _current ? widget.cards[i].theme.accent.withValues(alpha: 0.18) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: i == _current ? widget.cards[i].theme.accent : n.line.withValues(alpha: 0.6)),
                    ),
                    child: Text(widget.cards[i].title,
                        style: TextStyle(
                            color: i == _current ? n.ink : n.mute,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 1)),
                  ),
                ),
            ],
          ),
        ),
        if (widget.onShare != null)
          Builder(
            builder: (buttonContext) => TextButton.icon(
              key: const ValueKey('share-player-card'),
              onPressed: _sharing ? null : () => _share(buttonContext),
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(_sharing ? 'Preparing…' : 'Share ${widget.cards[_current].title.toLowerCase()} card'),
            ),
          ),
      ]);
    });
  }
}
