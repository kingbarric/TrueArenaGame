import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/neon_theme.dart';

/// The game's artwork in a theme-specific badge with its name below.
class GameBadge extends StatelessWidget {
  const GameBadge(
      {super.key, required this.gameId, this.size = 72, this.dimmed = false});

  /// 'truearena' | 'bluff' | 'draughts' | 'goosi' | 'whot'
  final String gameId;
  final double size;
  final bool dimmed;

  static const _bg = {
    'truearena': Color(0xff2e0a1c),
    'bluff': Color(0xff0e2a3a),
    'draughts': Color(0xff3a2408),
    'goosi': Color(0xff0e2e1c),
    'whot': Color(0xff52202b),
    'ludo': Color(0xff351639),
  };

  static const _ring = {
    'truearena': Color(0xffff5da2),
    'bluff': Color(0xff6ee7ff),
    'draughts': Color(0xffffd24d),
    'goosi': Color(0xff5eead4),
    'whot': Color(0xffe9b963),
    'ludo': Color(0xffffcf66),
  };

  static const _names = {
    'truearena': 'TRAITORS',
    'bluff': 'WORD BLUFF',
    'draughts': 'DRAFT',
    'goosi': 'OWARE',
    'whot': 'WHOT',
    'ludo': 'LUDO',
  };

  static const _artwork = {
    'truearena': 'assets/images/game_icons/traitors.png',
    'bluff': 'assets/images/game_icons/word_bluff.png',
    'draughts': 'assets/images/game_icons/draft.png',
    'goosi': 'assets/images/game_icons/goosi.png',
    'whot': 'assets/images/game_icons/whot.png',
    'ludo': 'assets/images/game_icons/ludo.png',
  };

  static String? artworkFor(String gameId) => _artwork[gameId];

  static const _goosiIcon = '''
      <ellipse cx="50" cy="62" rx="34" ry="22" fill="none" stroke="COLOR" stroke-width="5"/>
      <circle cx="36" cy="52" r="8" fill="COLOR"/>
      <circle cx="56" cy="46" r="9" fill="COLOR"/>
      <circle cx="68" cy="58" r="7" fill="COLOR"/>
      <circle cx="46" cy="62" r="6.5" fill="COLOR"/>
    ''';

  @override
  Widget build(BuildContext context) {
    final design = context.neonDesign.kind;
    final n = context.neon;
    final bg = _bg[gameId] ?? _bg['truearena']!;
    final ring = _ring[gameId] ?? _ring['truearena']!;
    final label = _names[gameId] ?? gameId.toUpperCase();
    final artwork = artworkFor(gameId);

    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      // Width is fixed (the disc defines it) but height is intrinsic: a
      // pinned `size * 1.18` overflowed as soon as a ribbon wrapped to two
      // lines, because `Transform.translate` shifts the ribbon at paint
      // time without giving the Column any of that height back.
      child: SizedBox(
        width: size,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: size,
            height: size,
            padding: EdgeInsets.all(size * 0.06),
            decoration: switch (design) {
              NeonDesignKind.cabinet => BoxDecoration(
                  shape: BoxShape.circle,
                  color: bg,
                  border: Border.all(color: Colors.white, width: size * 0.07),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: size * 0.14,
                        offset: Offset(0, size * 0.05))
                  ],
                ),
              NeonDesignKind.nebula => BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(size * 0.26),
                  border: Border.all(color: ring, width: size * 0.045),
                  boxShadow: [
                    BoxShadow(
                        color: ring.withValues(alpha: 0.42),
                        blurRadius: size * 0.22)
                  ],
                ),
              NeonDesignKind.supercar => ShapeDecoration(
                  color: bg,
                  shape: BeveledRectangleBorder(
                    borderRadius: BorderRadius.circular(size * 0.22),
                    side: BorderSide(color: n.gold, width: size * 0.045),
                  ),
                  shadows: [
                    BoxShadow(
                        color: n.gold.withValues(alpha: 0.28),
                        blurRadius: size * 0.15)
                  ],
                ),
            },
            child: artwork == null
                ? SvgPicture.string(
                    '<svg viewBox="0 0 100 100">${_goosiIcon.replaceAll('COLOR', '#5eead4')}</svg>')
                : Image.asset(artwork, fit: BoxFit.contain),
          ),
          Transform.translate(
            offset: Offset(0, -size * 0.1),
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: size * 0.11, vertical: size * 0.035),
              decoration: design == NeonDesignKind.supercar
                  ? ShapeDecoration(
                      color: ring,
                      shape: BeveledRectangleBorder(
                          borderRadius: BorderRadius.circular(size * 0.12)),
                    )
                  : BoxDecoration(
                      color: ring,
                      borderRadius: BorderRadius.circular(
                          design == NeonDesignKind.nebula
                              ? size * 0.25
                              : size * 0.14)),
              child: Text(
                label,
                style: (design == NeonDesignKind.cabinet
                        ? GoogleFonts.baloo2()
                        : GoogleFonts.archivo())
                    .copyWith(
                  color: const Color(0xff1e1012),
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.135,
                  height: 1,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
