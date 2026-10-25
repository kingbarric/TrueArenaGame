import '../../core/table_minimum.dart';
import 'huud_kit.dart';
import 'traitors_mode_sheet.dart';
import 'whot_mode_sheet.dart';

/// The game as the Huud calls it: "Traitors · Blood Moon", "Whot · The
/// Tell", "Draughts".
String huudTableName(String gameType, String? mode) => switch (gameType) {
      'truearena' => traitorsModeName(mode),
      'whot' => whotModeName(mode),
      _ => huudGameName(gameType),
    };

/// What stops the host starting this game with [players] at the table: too
/// few (add a player or a Cyber Agent), or The Tell's teams not adding up.
/// Null when it can start.
String? huudStartProblem(String gameType, String? mode, int players, int minPlayers) =>
    tableStartProblem(huudTableName(gameType, mode), players, minPlayers) ??
    (gameType == 'whot' && mode == 'tell' ? tellStartProblem(players) : null);
