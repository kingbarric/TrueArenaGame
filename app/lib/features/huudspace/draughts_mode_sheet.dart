import 'package:flutter/material.dart';

import '../../theme/neon_theme.dart';
import 'huud_kit.dart';
import 'whot_mode_sheet.dart';

/// "Draughts · Seizure" — what a Huud calls its Draughts game.
String draughtsModeName(String? mode) => switch (mode) {
      'seizure' => 'Draughts · Seizure',
      'official' => 'Draughts · Official',
      _ => 'Draughts',
    };

/// Before anyone sits down: which capture rules? Null when closed.
Future<String?> askDraughtsMode(BuildContext context) => showHuudSheet<String>(
      context,
      builder: (context) {
        final n = context.neon;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Which Draughts?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: n.ink)),
              const SizedBox(height: 4),
              Text('Pick the capture rules, then choose who plays.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: n.mid)),
              const SizedBox(height: 16),
              const HuudModeCard(
                keyPrefix: 'draughts-mode',
                mode: 'casual',
                emoji: '⚫',
                title: 'Casual',
                tagline: 'Taking is up to you.',
                points: [
                  'Jump an opponent\'s piece if you like — or don\'t.',
                  'A jump you start has to be played out.',
                ],
              ),
              const SizedBox(height: 12),
              const HuudModeCard(
                keyPrefix: 'draughts-mode',
                mode: 'seizure',
                emoji: '⚡',
                title: 'Seizure',
                tagline: 'Miss a kill, lose the piece.',
                points: [
                  'Taking is optional, but watch the board.',
                  'If your opponent could have captured and didn\'t, tap that piece on your turn to seize it.',
                  'Seizing comes before your move, and shows in VAR.',
                ],
              ),
              const SizedBox(height: 12),
              const HuudModeCard(
                keyPrefix: 'draughts-mode',
                mode: 'official',
                emoji: '🏆',
                title: 'Official',
                tagline: 'International rules.',
                points: [
                  'If you can take, you must — and take the most pieces on offer.',
                ],
              ),
            ]),
          ),
        );
      },
    );
