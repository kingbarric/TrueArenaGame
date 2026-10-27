import 'package:flutter/material.dart';
import 'mode_art.dart';

String gameArtworkAsset(String? game, {String? mode}) {
  if (game == 'truearena') {
    return traitorsModeArt[mode] ?? traitorsModeArt['classic_conspiracy']!;
  }
  final slug = switch (game) {
    'draughts' => 'draft',
    'wordbluff' || 'bluff' => 'word_bluff',
    'monopoly' => 'huudpoly',
    null => 'whot',
    _ => game,
  };
  return 'assets/images/game_icons/$slug.png';
}

String gameInvitationHook(String? game) => switch (game) {
  'truearena' => 'Trust nobody. Bring your best alibi.',
  'whot' => 'Stack the drama. Play your last card.',
  'draughts' => 'Set the trap. Take the crown.',
  'chess' => 'One bold move can change everything.',
  'ludo' => 'Roll in. Race home. Settle the rivalry.',
  'goosi' => 'Sow a little strategy. Steal the win.',
  'wordbluff' || 'bluff' => 'Make it sound true. Call their bluff.',
  'monopoly' => 'Build your empire. Own the Huud.',
  'slayhuud' => 'Bring the look. Steal the spotlight.',
  _ => 'Your next great game starts with good company.',
};

/// Softly blended mode artwork behind readable game surfaces.
class GameArtworkBackdrop extends StatelessWidget {
  const GameArtworkBackdrop({super.key, required this.gameType, this.mode});
  final String gameType;
  final String? mode;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).scaffoldBackgroundColor;
    return IgnorePointer(child: Stack(fit: StackFit.expand, children: [
      Image.asset(gameArtworkAsset(gameType, mode: mode),
        fit: BoxFit.cover, excludeFromSemantics: true),
      DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [base.withValues(alpha: dark ? .72 : .84),
          base.withValues(alpha: dark ? .88 : .94), base],
      ))),
    ]));
  }
}
