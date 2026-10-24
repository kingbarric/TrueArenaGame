import 'package:flutter/material.dart';

import '../theme/neon_theme.dart';

/// Each built-in Traitors mode's own picture, by the slug the server keeps
/// it under. The game's icon stays the same; these sit behind its mode cards.
const traitorsModeArt = {
  'blood_moon': 'assets/images/traitors_modes/blood_moon.jpg',
  'midnight_heist': 'assets/images/traitors_modes/midnight_heist.jpg',
  'final_gambit': 'assets/images/traitors_modes/final_gambit.jpg',
  'classic_conspiracy': 'assets/images/traitors_modes/classic_conspiracy.jpg',
  'the_last_alibi': 'assets/images/traitors_modes/the_last_alibi.jpg',
};

/// A mode card's picture, filling the card behind its words. It's washed
/// over with the card's own colour — most where the words start, a little
/// less towards the far corner — so it sets the mood without getting in the
/// way of reading. No [asset]: just [child].
class ModeArtBackdrop extends StatelessWidget {
  const ModeArtBackdrop({super.key, required this.asset, required this.borderRadius, required this.child});

  final String? asset;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final art = asset;
    if (art == null) return child;
    final n = context.neon;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(children: [
        Positioned.fill(
          child: Image.asset(art, key: ValueKey('mode-art-$art'), fit: BoxFit.cover, excludeFromSemantics: true),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  n.panel.withValues(alpha: dark ? 0.8 : 0.85),
                  n.panel.withValues(alpha: dark ? 0.6 : 0.7),
                ],
              ),
            ),
          ),
        ),
        child,
      ]),
    );
  }
}
