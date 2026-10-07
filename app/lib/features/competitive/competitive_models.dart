/// Wire models for the competitive API (`/me/competitive`, `/leaderboards`,
/// `/me/matches`). Everything here is computed server-side — the app only
/// ever reads ratings, ranks and achievements, it never sends them.
library;

import '../games/game_select_screen.dart' show gameCatalog;

/// The player-facing name for a game id ('draughts' is branded "Draft").
String gameDisplayName(String gameType) {
  // Word Bluff is `wordbluff` on the server, `bluff` in the catalog.
  if (gameType == 'wordbluff') gameType = 'bluff';
  for (final g in gameCatalog) {
    if (g.id == gameType) return g.name;
  }
  return gameType.isEmpty ? gameType : gameType[0].toUpperCase() + gameType.substring(1);
}

/// `127 -> "#000127"` — the same format the server sends as `playhuudId`,
/// for the rare place the app only has the number.
String formatPlayhuudNumber(int? n) => n == null ? '' : '#${n.toString().padLeft(6, '0')}';

class FoundingTier {
  const FoundingTier({required this.code, required this.label});
  final String code;
  final String label;

  static FoundingTier? fromJson(Object? j) {
    if (j is! Map) return null;
    return FoundingTier(code: j['code'] as String? ?? '', label: j['label'] as String? ?? '');
  }
}

class CompetitiveLocation {
  const CompetitiveLocation({
    this.countryCode,
    this.countryName,
    this.regionCode,
    this.regionName,
    this.city,
    this.cityPublic = false,
  });

  final String? countryCode;
  final String? countryName;
  final String? regionCode;
  final String? regionName;
  final String? city;
  final bool cityPublic;

  static CompetitiveLocation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    return CompetitiveLocation(
      countryCode: j['countryCode'] as String?,
      countryName: j['countryName'] as String?,
      regionCode: j['regionCode'] as String?,
      regionName: j['regionName'] as String?,
      city: j['city'] as String?,
      cityPublic: j['cityPublic'] as bool? ?? false,
    );
  }
}

/// One rank on one board. [rank] is only set when [status] is `ranked`;
/// otherwise [status] says what's missing so the UI can explain it instead of
/// showing a misleading number.
class RankInfo {
  const RankInfo({this.rank, this.status = unrated});

  static const ranked = 'ranked';
  static const provisional = 'provisional';
  static const locationRequired = 'location_required';
  static const unrated = 'unrated';

  final int? rank;
  final String status;

  bool get isRanked => status == ranked && rank != null;

  factory RankInfo.fromJson(Object? raw) {
    if (raw is! Map) return const RankInfo();
    return RankInfo(rank: (raw['rank'] as num?)?.toInt(), status: raw['status'] as String? ?? unrated);
  }
}

class GameRanks {
  const GameRanks({this.global = const RankInfo(), this.country = const RankInfo(), this.region = const RankInfo()});
  final RankInfo global;
  final RankInfo country;
  final RankInfo region;

  factory GameRanks.fromJson(Object? raw) {
    if (raw is! Map) return const GameRanks();
    return GameRanks(
      global: RankInfo.fromJson(raw['global']),
      country: RankInfo.fromJson(raw['country']),
      region: RankInfo.fromJson(raw['region']),
    );
  }
}

class GameStats {
  const GameStats({
    this.gamesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.winRate = 0,
    this.currentWinStreak = 0,
    this.bestWinStreak = 0,
    this.top100Wins = 0,
    this.tournamentWins = 0,
    this.casualGames = 0,
  });

  /// Ranked games only — W/L/D and streaks are the competitive stat line.
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final double winRate;
  final int currentWinStreak;
  final int bestWinStreak;
  final int top100Wins;
  final int tournamentWins;
  final int casualGames;

  factory GameStats.fromJson(Object? raw) {
    if (raw is! Map) return const GameStats();
    final j = raw.cast<String, dynamic>();
    int i(String k) => (j[k] as num?)?.toInt() ?? 0;
    return GameStats(
      gamesPlayed: i('gamesPlayed'),
      wins: i('wins'),
      losses: i('losses'),
      draws: i('draws'),
      winRate: (j['winRate'] as num?)?.toDouble() ?? 0,
      currentWinStreak: i('currentWinStreak'),
      bestWinStreak: i('bestWinStreak'),
      top100Wins: i('top100Wins'),
      tournamentWins: i('tournamentWins'),
      casualGames: i('casualGames'),
    );
  }
}

class GameRecord {
  const GameRecord({
    required this.gameType,
    this.rating,
    this.peakRating,
    this.provisional = true,
    this.placementGamesPlayed = 0,
    this.placementGamesRequired = 10,
    this.ranks = const GameRanks(),
    this.stats = const GameStats(),
  });

  final String gameType;
  final int? rating;
  final int? peakRating;
  final bool provisional;
  final int placementGamesPlayed;
  final int placementGamesRequired;
  final GameRanks ranks;
  final GameStats stats;

  bool get hasRating => rating != null;
  String get name => gameDisplayName(gameType);

  factory GameRecord.fromJson(Map<String, dynamic> j) => GameRecord(
        gameType: j['gameType'] as String,
        rating: (j['rating'] as num?)?.toInt(),
        peakRating: (j['peakRating'] as num?)?.toInt(),
        provisional: j['provisional'] as bool? ?? true,
        placementGamesPlayed: (j['placementGamesPlayed'] as num?)?.toInt() ?? 0,
        placementGamesRequired: (j['placementGamesRequired'] as num?)?.toInt() ?? 10,
        ranks: GameRanks.fromJson(j['ranks']),
        stats: GameStats.fromJson(j['stats']),
      );
}

class Achievement {
  const Achievement({
    required this.type,
    required this.label,
    required this.icon,
    this.gameType,
    this.earnedAt,
    this.rarity = 'common',
  });

  final String type;
  final String label;
  final String icon;
  final String? gameType;
  final DateTime? earnedAt;
  final String rarity;

  bool get isFounding => type.startsWith('FOUNDING_');

  factory Achievement.fromJson(Map<String, dynamic> j) => Achievement(
        type: j['type'] as String,
        label: j['label'] as String? ?? j['type'] as String,
        icon: j['icon'] as String? ?? '🏅',
        gameType: j['gameType'] as String?,
        earnedAt: DateTime.tryParse(j['earnedAt'] as String? ?? ''),
        rarity: j['rarity'] as String? ?? 'common',
      );
}

class CompetitiveProfile {
  const CompetitiveProfile({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.playhuudNumber,
    this.playhuudId,
    this.founding,
    this.location,
    this.profileComplete = false,
    this.locationLockedUntil,
    this.profilePublic = true,
    this.restricted = false,
    this.games = const [],
    this.achievements = const [],
  });

  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final int? playhuudNumber;

  /// Server-formatted, e.g. "#000127".
  final String? playhuudId;
  final FoundingTier? founding;
  final CompetitiveLocation? location;

  /// Country and state both set — unlocks every scoped leaderboard.
  final bool profileComplete;
  final DateTime? locationLockedUntil;

  /// The owner lets other players see this profile (the default).
  final bool profilePublic;

  /// You're looking at someone's private profile: identity only.
  final bool restricted;
  final List<GameRecord> games;
  final List<Achievement> achievements;

  bool get hasCountry => location?.countryCode != null;

  GameRecord? game(String gameType) {
    for (final g in games) {
      if (g.gameType == gameType) return g;
    }
    return null;
  }

  factory CompetitiveProfile.fromJson(Map<String, dynamic> j) => CompetitiveProfile(
        userId: j['userId'] as String,
        username: j['username'] as String? ?? '',
        displayName: j['displayName'] as String? ?? 'Player',
        avatarUrl: j['avatarUrl'] as String?,
        playhuudNumber: (j['playhuudNumber'] as num?)?.toInt(),
        playhuudId: j['playhuudId'] as String?,
        founding: FoundingTier.fromJson(j['founding']),
        location: CompetitiveLocation.fromJson(j['location']),
        profileComplete: j['profileComplete'] as bool? ?? false,
        locationLockedUntil: DateTime.tryParse(j['locationLockedUntil'] as String? ?? ''),
        profilePublic: j['profilePublic'] as bool? ?? true,
        restricted: j['restricted'] as bool? ?? false,
        games: ((j['games'] as List?) ?? const [])
            .map((e) => GameRecord.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        achievements: ((j['achievements'] as List?) ?? const [])
            .map((e) => Achievement.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

enum LeaderboardScope {
  global('global', 'Global'),
  country('country', 'Country'),
  region('region', 'State'),
  friends('friends', 'Friends');

  const LeaderboardScope(this.wire, this.label);
  final String wire;
  final String label;
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.playhuudId,
    this.founding,
    required this.rating,
    this.peakRating = 0,
    this.gamesPlayed = 0,
    this.winRate = 0,
    this.tournamentWins = 0,
    this.provisional = false,
  });

  /// 0 means "not on this board yet" (still in placement).
  final int rank;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? playhuudId;
  final FoundingTier? founding;
  final int rating;
  final int peakRating;
  final int gamesPlayed;
  final double winRate;
  final int tournamentWins;
  final bool provisional;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        userId: j['userId'] as String,
        username: j['username'] as String? ?? '',
        displayName: j['displayName'] as String? ?? 'Player',
        avatarUrl: j['avatarUrl'] as String?,
        playhuudId: j['playhuudId'] as String?,
        founding: FoundingTier.fromJson(j['founding']),
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        peakRating: (j['peakRating'] as num?)?.toInt() ?? 0,
        gamesPlayed: (j['gamesPlayed'] as num?)?.toInt() ?? 0,
        winRate: (j['winRate'] as num?)?.toDouble() ?? 0,
        tournamentWins: (j['tournamentWins'] as num?)?.toInt() ?? 0,
        provisional: j['provisional'] as bool? ?? false,
      );
}

class Leaderboard {
  const Leaderboard({
    required this.gameType,
    required this.scope,
    this.scopeKey,
    this.scopeName,
    this.offset = 0,
    this.entries = const [],
    this.me,
    this.unavailableReason,
  });

  final String gameType;
  final String scope;
  final String? scopeKey;
  final String? scopeName;
  final int offset;
  final List<LeaderboardEntry> entries;
  final LeaderboardEntry? me;
  final String? unavailableReason;

  factory Leaderboard.fromJson(Map<String, dynamic> j) => Leaderboard(
        gameType: j['gameType'] as String,
        scope: j['scope'] as String? ?? 'global',
        scopeKey: j['scopeKey'] as String?,
        scopeName: j['scopeName'] as String?,
        offset: (j['offset'] as num?)?.toInt() ?? 0,
        entries: ((j['entries'] as List?) ?? const [])
            .map((e) => LeaderboardEntry.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        me: j['me'] is Map ? LeaderboardEntry.fromJson((j['me'] as Map).cast<String, dynamic>()) : null,
        unavailableReason: j['unavailableReason'] as String?,
      );
}

class MatchOpponent {
  const MatchOpponent({required this.userId, required this.displayName, this.username, this.isBot = false, this.ratingBefore});
  final String userId;
  final String displayName;
  final String? username;
  final bool isBot;
  final int? ratingBefore;

  factory MatchOpponent.fromJson(Map<String, dynamic> j) => MatchOpponent(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String? ?? 'Player',
        username: j['username'] as String?,
        isBot: j['isBot'] as bool? ?? false,
        ratingBefore: (j['ratingBefore'] as num?)?.toInt(),
      );
}

class MatchHistoryEntry {
  const MatchHistoryEntry({
    required this.matchId,
    required this.gameType,
    required this.ranked,
    required this.outcome,
    this.unrankedReason,
    this.completedAt,
    this.ratingAfter,
    this.ratingDelta,
    this.opponents = const [],
    this.championship = false,
  });

  final String matchId;
  final String gameType;
  final bool ranked;
  final String? unrankedReason;

  /// 'won' | 'lost' | 'tied'
  final String outcome;
  final DateTime? completedAt;
  final int? ratingAfter;
  final int? ratingDelta;
  final List<MatchOpponent> opponents;
  final bool championship;

  factory MatchHistoryEntry.fromJson(Map<String, dynamic> j) => MatchHistoryEntry(
        matchId: j['matchId'] as String,
        gameType: j['gameType'] as String,
        ranked: j['ranked'] as bool? ?? false,
        unrankedReason: j['unrankedReason'] as String?,
        outcome: j['outcome'] as String? ?? 'lost',
        completedAt: DateTime.tryParse(j['completedAt'] as String? ?? ''),
        ratingAfter: (j['ratingAfter'] as num?)?.toInt(),
        ratingDelta: (j['ratingDelta'] as num?)?.toInt(),
        championship: j['championshipId'] != null,
        opponents: ((j['opponents'] as List?) ?? const [])
            .map((e) => MatchOpponent.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class CountryOption {
  const CountryOption(this.code, this.name, {this.catalogued = false});
  final String code;
  final String name;

  /// Has a fixed list of states; otherwise the state is typed in.
  final bool catalogued;
}

class RegionOption {
  const RegionOption(this.code, this.name);
  final String code;
  final String name;
}
