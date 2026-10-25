import 'package:flutter/material.dart';

import '../../theme/neon_theme.dart';
import 'huud_kit.dart';
import '../../widgets/huud_art.dart';
import '../../widgets/mode_art.dart';

/// Whot's two ways to play, as the wire names them.
const whotModes = ['classic', 'tell'];

/// "Whot", or "Whot · The Tell" — what a Huud calls its Whot game.
String whotModeName(String? mode) => mode == 'tell' ? 'Whot · The Tell' : 'Whot';

/// The Tell starts with 4, 6 or 8 players, including Cyber Agents.
String? tellStartProblem(int players) {
  if (![4, 6, 8].contains(players)) return 'The Tell needs 4, 6 or 8 players — teams of two';
  return null;
}

/// Before anyone sits down: which Whot? A short briefing of each, and the
/// host taps one. Null when they close the sheet without choosing.
Future<String?> askWhotMode(BuildContext context) => showHuudSheet<String>(
      context,
      builder: (context) {
        final n = context.neon;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Which Whot?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: n.ink)),
              const SizedBox(height: 4),
              Text('Pick one, then choose who plays.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: n.mid)),
              const SizedBox(height: 16),
              const HuudModeCard(
                mode: 'classic',
                emoji: '🃏',
                title: 'Classic',
                tagline: 'The Whot you know — everyone for themselves.',
                points: [
                  'Match the top card by shape or number. Can\'t? Go to market.',
                  '2 Pick Two · 14 General Market · 1 Hold On · 8 Skip.',
                  'First to empty their hand wins.',
                  '2 to 4 players · Cyber Agents can play.',
                ],
              ),
              const SizedBox(height: 12),
              const HuudModeCard(
                mode: 'tell',
                emoji: '🤫',
                title: 'The Tell',
                tagline: 'Team Whot with a secret signal.',
                points: [
                  'Teams of two. You and your partner secretly pick a signal.',
                  'Play normal Whot. When every card left in your hand matches — same shape or same number, 3 or more — flash your signal.',
                  'Your partner taps it to buzz and your team wins. Opponents can tap it first to steal the win.',
                  'Send decoys to bluff — but a wrong buzz knocks your team out.',
                  '4, 6 or 8 players · Cyber Agents can play. With 6 or 8, the first two teams through play a fresh final.',
                ],
              ),
            ]),
          ),
        );
      },
    );

/// One way to play a game, briefed, with a button to pick it. Shared by the
/// Whot and SlayHuud sheets.
class HuudModeCard extends StatelessWidget {
  const HuudModeCard({
    super.key,
    required this.mode,
    required this.emoji,
    required this.title,
    required this.tagline,
    required this.points,
    this.keyPrefix = 'whot-mode',
    this.art,
  });

  final String mode;
  final String emoji;
  final String title;
  final String tagline;
  final List<String> points;
  final String keyPrefix;

  /// The mode's own picture, faded behind the card's words.
  final String? art;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          HuudText(emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: n.ink)),
              Text(tagline, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: h.orangeText)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        for (final p in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('•  ', style: TextStyle(fontSize: 14, height: 1.35, color: n.mid)),
              Expanded(child: Text(p, style: TextStyle(fontSize: 14, height: 1.35, color: n.mid))),
            ]),
          ),
        const SizedBox(height: 8),
        HuudButton(
          key: ValueKey('$keyPrefix-$mode'),
          label: 'Play $title',
          icon: Icons.play_arrow_rounded,
          expand: true,
          onPressed: () => Navigator.of(context).pop(mode),
        ),
      ]);
    if (art == null) return HuudCard(padding: const EdgeInsets.all(16), child: body);
    // The picture fills the card right up to its border.
    return HuudCard(
      padding: EdgeInsets.zero,
      child: ModeArtBackdrop(
        asset: art,
        borderRadius: BorderRadius.circular(22.6),
        child: Padding(padding: const EdgeInsets.all(16), child: body),
      ),
    );
  }
}
