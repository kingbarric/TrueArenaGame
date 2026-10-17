import 'package:flutter/material.dart';

import 'game_badge.dart';

/// A championship winner's badge: the gold shield in its laurels, with the
/// game on the shield and, when there's room to read it, how many players
/// the champion came through.
class ChampionBadge extends StatelessWidget {
  const ChampionBadge({super.key, this.gameType, this.players, this.width = 96});

  final String? gameType;
  final int? players;
  final double width;

  static const asset = 'assets/images/badges/champion_shield.png';

  /// The art is 640 × 585.
  static const _aspect = 585 / 640;

  static const _gold = Color(0xFFF7C948);

  static const _games = {'chess': 'Chess', 'draughts': 'Draughts', 'slayhuud': 'SlayHuud'};

  /// `64, 'chess'` → "64-player Chess championship".
  static String describe(int players, String? gameType) =>
      ['$players-player', if (_games[gameType] != null) _games[gameType]!, 'championship'].join(' ');

  @override
  Widget build(BuildContext context) {
    final height = width * _aspect;
    final art = gameType == null ? null : GameBadge.artworkFor(gameType!);
    final showPlayers = players != null && width >= 72;
    return Semantics(
      label: ['Champion badge', if (players != null) '$players players'].join(', '),
      image: true,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                asset,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Center(
                  child: Text('🏆', style: TextStyle(fontSize: width * 0.6)),
                ),
              ),
            ),
            // The shield's black face: wide at the top, narrowing to its point.
            Positioned(
              left: width * 0.31,
              right: width * 0.31,
              top: height * 0.17,
              bottom: height * 0.36,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (art != null)
                    Flexible(
                      flex: 3,
                      child: Image.asset(art, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox()),
                    ),
                  if (showPlayers)
                    Flexible(
                      flex: 2,
                      child: FittedBox(
                        child: Text(
                          '$players',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _gold,
                            height: 1,
                            shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
