/// The Huud feed's wire shapes — see `HuudDtos` on the backend. One
/// [HuudItem] per card; its [HuudItem.kind] says which detail block is set.
library;

/// "Your Huud" is you and your friends; "For you" is the whole public lobby.
enum HuudTab { friends, forYou }

/// The chip row under the search bar.
enum HuudFilter { all, open, wins, tournaments }

extension HuudTabWire on HuudTab {
  String get wire => this == HuudTab.friends ? 'friends' : 'for_you';
}

extension HuudFilterWire on HuudFilter {
  String get wire => name;

  String get label => switch (this) {
        HuudFilter.all => 'All',
        HuudFilter.open => 'Open games',
        HuudFilter.wins => 'Wins',
        HuudFilter.tournaments => 'Tournaments',
      };
}

const huudGameNames = {
  'truearena': 'Traitors',
  'wordbluff': 'Word Bluff',
  'draughts': 'Draughts',
  'chess': 'Chess',
  'goosi': 'Macala',
  'whot': 'Whot',
  'ludo': 'Ludo',
};

/// The game art lookup (`GameBadge.artworkFor`) keys Word Bluff as "bluff".
String huudArtworkId(String gameType) => gameType == 'wordbluff' ? 'bluff' : gameType;

class HuudPerson {
  const HuudPerson({
    required this.userId,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    this.friend = false,
  });
  final String userId;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final bool friend;

  String get name => displayName.isNotEmpty ? displayName : username;
  String get firstName => name.split(' ').first;

  factory HuudPerson.fromJson(Map<String, dynamic> j) => HuudPerson(
        userId: j['userId'].toString(),
        displayName: j['displayName'] as String? ?? '',
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        friend: j['friend'] == true,
      );
}

/// An open game request or a challenge, backed by a lobby room.
class HuudOpenGame {
  const HuudOpenGame({
    required this.postId,
    required this.roomId,
    required this.roomCode,
    required this.ranked,
    required this.seatsTaken,
    required this.seats,
    required this.players,
    required this.expiresAt,
    required this.joined,
    required this.mine,
    this.target,
    this.lastOutcome,
  });
  final String postId, roomId, roomCode;
  final bool ranked, joined, mine;
  final int seatsTaken, seats;
  final List<HuudPerson> players;
  final DateTime expiresAt;

  /// Set on a challenge: who it's addressed to.
  final HuudPerson? target;

  /// The viewer's result the last time these two played this game — what
  /// turns a challenge into a rematch.
  final String? lastOutcome;

  int get seatsLeft => (seats - seatsTaken).clamp(0, seats);

  factory HuudOpenGame.fromJson(Map<String, dynamic> j) => HuudOpenGame(
        postId: j['postId'].toString(),
        roomId: j['roomId'].toString(),
        roomCode: j['roomCode'] as String? ?? '',
        ranked: j['ranked'] == true,
        seatsTaken: (j['seatsTaken'] as num?)?.toInt() ?? 0,
        seats: (j['seats'] as num?)?.toInt() ?? 2,
        players: ((j['players'] as List?) ?? const [])
            .map((e) => HuudPerson.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        expiresAt: DateTime.parse(j['expiresAt'].toString()),
        joined: j['joined'] == true,
        mine: j['mine'] == true,
        target: j['target'] == null
            ? null
            : HuudPerson.fromJson((j['target'] as Map).cast<String, dynamic>()),
        lastOutcome: j['lastOutcome'] as String?,
      );
}

/// A win straight from match history.
class HuudWin {
  const HuudWin({
    required this.matchId,
    required this.ranked,
    required this.streak,
    required this.recent,
    this.rating,
    this.weekDelta,
    required this.beaten,
  });
  final String matchId;
  final bool ranked;
  final int streak;

  /// Newest first: "won" / "lost" / "tied".
  final List<String> recent;
  final double? rating;
  final double? weekDelta;
  final List<String> beaten;

  factory HuudWin.fromJson(Map<String, dynamic> j) => HuudWin(
        matchId: j['matchId'].toString(),
        ranked: j['ranked'] == true,
        streak: (j['streak'] as num?)?.toInt() ?? 0,
        recent: ((j['recent'] as List?) ?? const []).map((e) => e.toString()).toList(),
        rating: (j['rating'] as num?)?.toDouble(),
        weekDelta: (j['weekDelta'] as num?)?.toDouble(),
        beaten: ((j['beaten'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
}

class HuudTournament {
  const HuudTournament({
    required this.championshipId,
    required this.code,
    required this.name,
    required this.size,
    required this.joined,
    this.scheduledAt,
    required this.status,
    this.champion,
    required this.viewerJoined,
  });
  final String championshipId, code, name, status;
  final int size, joined;
  final DateTime? scheduledAt;
  final HuudPerson? champion;
  final bool viewerJoined;

  factory HuudTournament.fromJson(Map<String, dynamic> j) => HuudTournament(
        championshipId: j['championshipId'].toString(),
        code: j['code'] as String? ?? '',
        name: j['name'] as String? ?? '',
        size: (j['size'] as num?)?.toInt() ?? 0,
        joined: (j['joined'] as num?)?.toInt() ?? 0,
        scheduledAt: DateTime.tryParse(j['scheduledAt']?.toString() ?? ''),
        status: j['status'] as String? ?? '',
        champion: j['champion'] == null
            ? null
            : HuudPerson.fromJson((j['champion'] as Map).cast<String, dynamic>()),
        viewerJoined: j['viewerJoined'] == true,
      );
}

class HuudItem {
  const HuudItem({
    required this.kind,
    required this.id,
    required this.at,
    required this.actor,
    required this.gameType,
    this.message,
    this.game,
    this.win,
    this.tournament,
  });

  /// game_request | challenge | win | tournament | champion
  final String kind;
  final String id;
  final DateTime at;
  final HuudPerson actor;
  final String gameType;
  final String? message;
  final HuudOpenGame? game;
  final HuudWin? win;
  final HuudTournament? tournament;

  String get gameName => huudGameNames[gameType] ?? gameType;

  factory HuudItem.fromJson(Map<String, dynamic> j) => HuudItem(
        kind: j['kind'] as String,
        id: j['id'].toString(),
        at: DateTime.parse(j['at'].toString()),
        actor: HuudPerson.fromJson((j['actor'] as Map).cast<String, dynamic>()),
        gameType: j['gameType'] as String? ?? '',
        message: j['message'] as String?,
        game: j['game'] == null
            ? null
            : HuudOpenGame.fromJson((j['game'] as Map).cast<String, dynamic>()),
        win: j['win'] == null ? null : HuudWin.fromJson((j['win'] as Map).cast<String, dynamic>()),
        tournament: j['tournament'] == null
            ? null
            : HuudTournament.fromJson((j['tournament'] as Map).cast<String, dynamic>()),
      );
}

/// "2m", "1h", "3d" — the timeline's compact age.
String huudAgo(DateTime at, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// "8 min left", or null once it's gone.
String? huudTimeLeft(DateTime expiresAt, {DateTime? now}) {
  final left = expiresAt.difference(now ?? DateTime.now());
  if (left.isNegative) return null;
  if (left.inMinutes < 1) return 'under a minute left';
  return '${left.inMinutes} min left';
}

/// 1612 → "1,612".
String huudGrouped(num value) {
  final digits = value.round().abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
