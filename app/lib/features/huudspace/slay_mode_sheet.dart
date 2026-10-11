import 'package:flutter/material.dart';

import '../../theme/neon_theme.dart';
import 'huud_kit.dart';
import 'whot_mode_sheet.dart';

/// SlayHuud's two ways to play in a Huud, as the wire names them.
const slayModes = ['battle', 'group'];

/// "SlayHuud · Style Battle" or "SlayHuud · Group Show" — what a Huud calls its SlayHuud game.
String slayModeName(String? mode) => mode == 'group' ? 'SlayHuud · Group Show' : 'SlayHuud · Style Battle';

/// Games that ask a question before anyone sits down: which Whot, which SlayHuud.
bool huudGameHasModes(String? gameType) => gameType == 'whot' || gameType == 'slayhuud';

/// The question for [gameType]. Null when the sheet is closed without choosing.
Future<String?> askHuudGameMode(BuildContext context, String gameType) =>
    gameType == 'slayhuud' ? askSlayMode(context) : askWhotMode(context);

/// What the Huud calls the game on its card: the mode where there is one.
String huudGameTitle(String gameType, String? mode) => switch (gameType) {
      'whot' => whotModeName(mode),
      'slayhuud' => slayModeName(mode),
      _ => huudGameName(gameType),
    };

/// Before anyone sits down: a Style Battle or a Group Show? The theme is a
/// surprise, revealed when the styling starts.
Future<String?> askSlayMode(BuildContext context) => showHuudSheet<String>(
      context,
      builder: (context) {
        final n = context.neon;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Which SlayHuud?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: n.ink)),
              const SizedBox(height: 4),
              Text('Pick one, then take your seats in the studio.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: n.mid)),
              const SizedBox(height: 16),
              const HuudModeCard(
                keyPrefix: 'slay-mode',
                mode: 'battle',
                emoji: '⚡',
                title: 'Style Battle',
                tagline: 'You vs one stylist.',
                points: [
                  'You both get the same theme and the same clock.',
                  'Dress your star from the wardrobe, then walk the runway.',
                  'Votes and the style score pick the better look.',
                  '2 players · verified accounts.',
                ],
              ),
              const SizedBox(height: 12),
              const HuudModeCard(
                keyPrefix: 'slay-mode',
                mode: 'group',
                emoji: '👯',
                title: 'Group Show',
                tagline: 'The whole Huud on one runway.',
                points: [
                  'One theme for everyone, one clock.',
                  'Style your look and walk it.',
                  'Votes and the style score crown the winner.',
                  '4 to 8 players · starts once 4 are in.',
                ],
              ),
            ]),
          ),
        );
      },
    );
