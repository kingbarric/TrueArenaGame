/// Wire shapes for Huud spaces — see `HuudSpaceDtos` on the backend. A Huud
/// space is the place people hang out and play game after game in; the game
/// inside it comes and goes, the Huud stays.
library;

enum HuudPrivacy { friends, private, public }

extension HuudPrivacyInfo on HuudPrivacy {
  String get wire => name;

  String get label => switch (this) {
        HuudPrivacy.friends => 'Friends',
        HuudPrivacy.private => 'Private',
        HuudPrivacy.public => 'Public',
      };

  String get emoji => switch (this) {
        HuudPrivacy.friends => '👫',
        HuudPrivacy.private => '🔒',
        HuudPrivacy.public => '🌍',
      };

  /// One short line a ten-year-old can read at a glance.
  String get explain => switch (this) {
        HuudPrivacy.friends => 'Your friends can find it and join',
        HuudPrivacy.private => 'Only people you give the code to',
        HuudPrivacy.public => 'Anyone on PlayHuud can find it',
      };

  static HuudPrivacy parse(String? wire) =>
      HuudPrivacy.values.firstWhere((p) => p.name == wire, orElse: () => HuudPrivacy.friends);
}

class HuudMember {
  const HuudMember({
    required this.userId,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    this.host = false,
    this.here = false,
  });

  final String userId;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final bool host;
  final bool here;

  String get name => displayName.isNotEmpty ? displayName : username;
  String get firstName => name.split(' ').first;

  factory HuudMember.fromJson(Map<String, dynamic> j) => HuudMember(
        userId: j['userId'].toString(),
        displayName: j['displayName'] as String? ?? '',
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        host: j['host'] == true,
        here: j['here'] == true,
      );
}

/// waiting → playing → finished.
class HuudGame {
  const HuudGame({
    required this.roomId,
    required this.code,
    required this.gameType,
    required this.status,
    required this.players,
  });

  final String roomId;
  final String code;
  final String gameType;
  final String status;
  final int players;

  bool get waiting => status == 'waiting';
  bool get playing => status == 'playing';
  bool get finished => status == 'finished';

  factory HuudGame.fromJson(Map<String, dynamic> j) => HuudGame(
        roomId: j['roomId'].toString(),
        code: j['code'] as String? ?? '',
        gameType: j['gameType'] as String? ?? 'draughts',
        status: j['status'] as String? ?? 'waiting',
        players: (j['players'] as num?)?.toInt() ?? 0,
      );
}

class HuudSpace {
  const HuudSpace({
    required this.id,
    required this.name,
    required this.privacy,
    required this.status,
    required this.members,
    required this.youAreIn,
    required this.youAreHost,
    required this.voiceRoom,
    this.code,
    this.host,
    this.currentGame,
  });

  final String id;

  /// Only people inside the Huud get its code.
  final String? code;
  final String name;
  final HuudPrivacy privacy;
  final String status;
  final HuudMember? host;
  final List<HuudMember> members;
  final HuudGame? currentGame;
  final bool youAreIn;
  final bool youAreHost;
  final String voiceRoom;

  bool get active => status == 'active';
  int get hereCount => members.where((m) => m.here).length;

  factory HuudSpace.fromJson(Map<String, dynamic> j) => HuudSpace(
        id: j['id'].toString(),
        code: j['code'] as String?,
        name: j['name'] as String? ?? 'Huud',
        privacy: HuudPrivacyInfo.parse(j['privacy'] as String?),
        status: j['status'] as String? ?? 'active',
        host: j['host'] == null ? null : HuudMember.fromJson((j['host'] as Map).cast<String, dynamic>()),
        members: [
          for (final m in (j['members'] as List? ?? const [])) HuudMember.fromJson((m as Map).cast<String, dynamic>()),
        ],
        currentGame:
            j['currentGame'] == null ? null : HuudGame.fromJson((j['currentGame'] as Map).cast<String, dynamic>()),
        youAreIn: j['youAreIn'] == true,
        youAreHost: j['youAreHost'] == true,
        voiceRoom: j['voiceRoom'] as String? ?? 'huud-${j['id']}',
      );
}

/// A card on the Live tab.
class LiveHuud {
  const LiveHuud({
    required this.id,
    required this.name,
    required this.privacy,
    required this.memberCount,
    required this.members,
    required this.youAreIn,
    this.host,
    this.gameType,
    this.gameStatus,
  });

  final String id;
  final String name;
  final HuudPrivacy privacy;
  final HuudMember? host;
  final int memberCount;
  final List<HuudMember> members;
  final String? gameType;
  final String? gameStatus;
  final bool youAreIn;

  factory LiveHuud.fromJson(Map<String, dynamic> j) => LiveHuud(
        id: j['id'].toString(),
        name: j['name'] as String? ?? 'Huud',
        privacy: HuudPrivacyInfo.parse(j['privacy'] as String?),
        host: j['host'] == null ? null : HuudMember.fromJson((j['host'] as Map).cast<String, dynamic>()),
        memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
        members: [
          for (final m in (j['members'] as List? ?? const [])) HuudMember.fromJson((m as Map).cast<String, dynamic>()),
        ],
        gameType: j['gameType'] as String?,
        gameStatus: j['gameStatus'] as String?,
        youAreIn: j['youAreIn'] == true,
      );
}

/// A card in "Your Huuds".
class HuudHistoryEntry {
  const HuudHistoryEntry({
    required this.id,
    required this.name,
    required this.privacy,
    required this.status,
    required this.youCreated,
    required this.youAreHost,
    required this.participants,
    required this.games,
    required this.gamesPlayed,
    required this.createdAt,
    this.endedAt,
    this.host,
  });

  final String id;
  final String name;
  final HuudPrivacy privacy;
  final String status;
  final bool youCreated;
  final bool youAreHost;
  final HuudMember? host;
  final List<HuudMember> participants;
  final List<String> games;
  final int gamesPlayed;
  final DateTime createdAt;
  final DateTime? endedAt;

  bool get live => status == 'active';

  factory HuudHistoryEntry.fromJson(Map<String, dynamic> j) => HuudHistoryEntry(
        id: j['id'].toString(),
        name: j['name'] as String? ?? 'Huud',
        privacy: HuudPrivacyInfo.parse(j['privacy'] as String?),
        status: j['status'] as String? ?? 'ended',
        youCreated: j['youCreated'] == true,
        youAreHost: j['youAreHost'] == true,
        host: j['host'] == null ? null : HuudMember.fromJson((j['host'] as Map).cast<String, dynamic>()),
        participants: [
          for (final m in (j['participants'] as List? ?? const []))
            HuudMember.fromJson((m as Map).cast<String, dynamic>()),
        ],
        games: [for (final g in (j['games'] as List? ?? const [])) g.toString()],
        gamesPlayed: (j['gamesPlayed'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        endedAt: DateTime.tryParse(j['endedAt']?.toString() ?? '')?.toLocal(),
      );
}

/// "Today", "Yesterday", "3 days ago", "12 Mar" — friendly, not a timestamp.
String huudWhen(DateTime when, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final day = _dateOnly(when);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${when.day} ${months[when.month - 1]}';
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
