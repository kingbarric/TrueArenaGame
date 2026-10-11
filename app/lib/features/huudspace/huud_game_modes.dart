import 'package:flutter/material.dart';

import '../slayhuud/slay_hub_screen.dart';
import 'draughts_mode_sheet.dart';
import 'huud_kit.dart';
import 'slay_mode_sheet.dart';
import 'traitors_mode_sheet.dart';
import 'whot_mode_sheet.dart';

/// Games that ask a question before anyone sits down: which Traitors, which
/// Whot, which SlayHuud, which Draughts rules.
bool huudGameHasModes(String? gameType) =>
    gameType == 'truearena' || gameType == 'whot' || gameType == 'slayhuud' || gameType == 'draughts';

/// The question for [gameType]. Null when the sheet is closed without
/// choosing — or when the player chose SlayHuud solo, which opens its hub.
Future<String?> askHuudGameMode(BuildContext context, String gameType) async {
  switch (gameType) {
    case 'truearena':
      return askTraitorsMode(context);
    case 'draughts':
      return askDraughtsMode(context);
    case 'slayhuud':
      final mode = await askSlayMode(context);
      if (mode != slaySolo) return mode;
      if (context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SlayHubScreen()));
      }
      return null;
    default:
      return askWhotMode(context);
  }
}

/// What the Huud calls the game on its card: the mode where there is one.
String huudGameTitle(String gameType, String? mode) => switch (gameType) {
      'truearena' => traitorsModeName(mode),
      'whot' => whotModeName(mode),
      'draughts' => draughtsModeName(mode),
      'slayhuud' => slayModeName(mode),
      _ => huudGameName(gameType),
    };
