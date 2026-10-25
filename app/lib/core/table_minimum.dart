/// Whether a table has enough people to start — people and Cyber Agents
/// together. Null when it does; otherwise what to tell the host, which is
/// always to add someone, never "try again".
String? tableStartProblem(String game, int players, int minPlayers) {
  final need = minPlayers - players;
  if (need <= 0) return null;
  if (need == 1) return 'Add a player or a Cyber Agent to start $game.';
  return '$game needs at least $minPlayers players. Add $need more — players or Cyber Agents.';
}

/// What a game answers Start with when its table is too small.
const tableTooSmallCodes = {'NEEDS_TWO_PLAYERS', 'BAD_PLAYER_COUNT', 'NOT_ENOUGH_PLAYERS', 'ROSTER'};

/// Said when Start is turned down for the table's size and the screen can't
/// work out exactly how many more are needed.
const tableTooSmallMessage = 'Not enough players yet — add a player or a Cyber Agent to start.';

/// The fewest players a game starts with, for a server too old to say.
/// The server's own figure (TableSizes) wins whenever it's there.
int defaultMinPlayers(String gameType, {String? mode}) => switch (gameType) {
      'wordbluff' => 4,
      'whot' => mode == 'tell' ? 4 : 2,
      'truearena' => 6,
      _ => 2,
    };
