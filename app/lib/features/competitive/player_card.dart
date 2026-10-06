import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/neon_theme.dart';
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
    'truearena': PlayerCardTheme(
        top: Color(0xff5c1029), bottom: Color(0xff1f0510), accent: Color(0xffff5da2),
        secondary: Color(0xffb0264f), ink: Colors.white, icon: '🎭'),
    'bluff': PlayerCardTheme(
        top: Color(0xff0f3b5c), bottom: Color(0xff061624), accent: Color(0xff6ee7ff),
        secondary: Color(0xff2b7fb8), ink: Colors.white, icon: '🗣️'),
    'chess': PlayerCardTheme(
        top: Color(0xff3d2a1a), bottom: Color(0xff150d07), accent: Color(0xffffe1a8),
        secondary: Color(0xff9c6b3c), ink: Colors.white, icon: '♟️'),
  };

  static PlayerCardTheme forGame(String gameType) =>
      _byGame[gameType] ??
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
}

/// The cards for a profile: Overall first, then one per rated game.
///
/// Overall is deliberately NOT a blended skill rating — there is no universal
/// rating by design. Its corner shows the player's best game rating, labelled
/// with that game, and the rest is career totals.
List<PlayerCardData> buildPlayerCards(CompetitiveProfile p, {List<String> ratedGames = const ['draughts']}) {
  final records = <GameRecord>[
    ...p.games,
    for (final g in ratedGames)
      if (p.game(g) == null) GameRecord(gameType: g),
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
    for (final r in records) _gameCard(p, r, name),
  ];
}

PlayerCardData _gameCard(CompetitiveProfile p, GameRecord r, String name) {
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
  const PlayerCard({super.key, required this.data, this.shine = 0});

  final PlayerCardData data;

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
          painter: _ShieldGlowPainter(t.accent),
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
                left: w * 0.09,
                top: h * 0.10,
                width: w * 0.36,
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
                ]),
              ),
              // Small title tab at the top centre.
              Positioned(
                top: h * 0.035,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(data.title,
                      style: TextStyle(
                          color: t.accent.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w900,
                          fontSize: w * 0.038,
                          letterSpacing: 2.4)),
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
              // Footer: founding status (if any) over the PlayHuud number.
              Positioned(
                left: w * 0.2,
                right: w * 0.2,
                bottom: h * 0.06,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (data.founding != null)
                    FittedBox(
                      child: Text(data.founding!.label.toUpperCase(),
                          key: ValueKey('card-founding-${data.title}'),
                          style: TextStyle(
                              color: t.accent,
                              fontWeight: FontWeight.w900,
                              fontSize: w * 0.036,
                              letterSpacing: 1.6)),
                    ),
                  FittedBox(
                    child: Text(data.playhuudId == null ? 'PLAYHUUD' : 'PLAYHUUD ${data.playhuudId}',
                        style: TextStyle(
                            color: t.ink.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w800,
                            fontSize: w * 0.032,
                            letterSpacing: 1.4)),
                  ),
                ]),
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

/// Swipeable cards: the focused card faces you, the previous one tilts away
/// on the left and the next on the right, both dropped slightly so the row
/// sits on an arc rather than a flat line. Each card glints once as it lands.
class PlayerCardCarousel extends StatefulWidget {
  const PlayerCardCarousel({super.key, required this.cards, this.onOpen});

  final List<PlayerCardData> cards;

  /// Tapping the focused card — e.g. to open that game's details.
  final void Function(PlayerCardData card)? onOpen;

  @override
  State<PlayerCardCarousel> createState() => _PlayerCardCarouselState();
}

class _PlayerCardCarouselState extends State<PlayerCardCarousel> with SingleTickerProviderStateMixin {
  final _controller = PageController(viewportFraction: 0.68);
  late final AnimationController _shine =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _shine.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    _shine.dispose();
    super.dispose();
  }

  void _onPage(int page) {
    setState(() => _page = page);
    _shine.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return LayoutBuilder(builder: (context, box) {
      final cardWidth = box.maxWidth * 0.68 * 0.92;
      final height = cardWidth / kPlayerCardAspect + 36;
      return Column(children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            key: const ValueKey('player-card-carousel'),
            controller: _controller,
            // Neighbouring cards may paint past this box into the page's
            // padding, so they still peek in from the screen edges.
            clipBehavior: Clip.none,
            itemCount: widget.cards.length,
            onPageChanged: _onPage,
            itemBuilder: (context, i) {
              return AnimatedBuilder(
                animation: Listenable.merge([_controller, _shine]),
                builder: (context, child) {
                  final position = _controller.position.hasContentDimensions
                      ? (_controller.page ?? _page.toDouble())
                      : _page.toDouble();
                  final d = (position - i).clamp(-1.5, 1.5);
                  final abs = d.abs();
                  final transform = Matrix4.identity()
                    ..setEntry(3, 2, 0.0014) // perspective
                    ..translateByDouble(0, abs * 26, 0, 1) // neighbours sit lower: the arc
                    ..rotateY(d * 0.55) // and turn away from the centre
                    ..scaleByDouble(1 - abs * 0.12, 1 - abs * 0.12, 1, 1);
                  return Opacity(
                    opacity: (1 - abs * 0.35).clamp(0.0, 1.0),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: transform,
                      child: Center(
                        child: SizedBox(
                          width: cardWidth,
                          child: GestureDetector(
                            onTap: () {
                              if (i != _page) {
                                _controller.animateToPage(i,
                                    duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
                              } else {
                                widget.onOpen?.call(widget.cards[i]);
                              }
                            },
                            child: PlayerCard(
                              key: ValueKey('player-card-${widget.cards[i].title}'),
                              data: widget.cards[i],
                              shine: i == _page ? _shine.value : 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < widget.cards.length; i++)
            GestureDetector(
              onTap: () => _controller.animateToPage(i,
                  duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: i == _page ? widget.cards[i].theme.accent.withValues(alpha: 0.18) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: i == _page ? widget.cards[i].theme.accent : n.line.withValues(alpha: 0.6)),
                ),
                child: Text(widget.cards[i].title,
                    style: TextStyle(
                        color: i == _page ? n.ink : n.mute,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 1)),
              ),
            ),
        ]),
      ]);
    });
  }
}
