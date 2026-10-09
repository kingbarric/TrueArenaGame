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
        HuudPrivacy.friends => 'Your friends can come straight in',
        HuudPrivacy.private => 'Only people you invite or let in',
        HuudPrivacy.public => 'Anyone on PlayHuud can come in',
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
    this.canSpeak = false,
    this.owner = false,
  });

  /// Whose Huud it is, for good (the host may be someone covering for them).
  final bool owner;

  final String userId;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final bool host;
  final bool here;
  final bool canSpeak;

  /// Full name — only for their profile card.
  String get name => displayName.isNotEmpty ? displayName : username;

  /// How they're shown everywhere else: their username.
  String get handle => username.isNotEmpty ? username : name.split(' ').first;

  factory HuudMember.fromJson(Map<String, dynamic> j) => HuudMember(
        userId: j['userId'].toString(),
        displayName: j['displayName'] as String? ?? '',
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        host: j['host'] == true,
        here: j['here'] == true,
        canSpeak: j['canSpeak'] == true,
        owner: j['owner'] == true,
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
    this.seats = 2,
    this.playerIds = const [],
    this.youArePlaying = false,
    this.readyIds = const [],
    this.table = const [],
  });

  /// Seated players who've pressed Ready.
  final List<String> readyIds;

  /// Everyone seated — people from the Huud and Cyber Agents.
  final List<HuudSeat> table;

  int get seatsLeft => (seats - players).clamp(0, seats);

  final String roomId;
  final String code;
  final String gameType;
  final String status;
  final int players;
  final int seats;
  final List<String> playerIds;

  /// In the Huud isn't in the game: this is having a seat.
  final bool youArePlaying;

  bool get full => players >= seats;

  bool get waiting => status == 'waiting';
  bool get playing => status == 'playing';
  bool get finished => status == 'finished';

  factory HuudGame.fromJson(Map<String, dynamic> j) => HuudGame(
        roomId: j['roomId'].toString(),
        code: j['code'] as String? ?? '',
        gameType: j['gameType'] as String? ?? 'draughts',
        status: j['status'] as String? ?? 'waiting',
        players: (j['players'] as num?)?.toInt() ?? 0,
        seats: (j['seats'] as num?)?.toInt() ?? 2,
        playerIds: [for (final id in (j['playerIds'] as List? ?? const [])) id.toString()],
        youArePlaying: j['youArePlaying'] == true,
        readyIds: [for (final id in (j['readyIds'] as List? ?? const [])) id.toString()],
        table: [
          for (final t in (j['table'] as List? ?? const [])) HuudSeat.fromJson((t as Map).cast<String, dynamic>()),
        ],
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
    this.youCanSpeak = false,
    this.joinRequest,
    this.playRequest,
    this.micRequest,
    this.requests = const [],
    this.shared = false,
    this.feedMessage,
    this.watching = 0,
    this.background,
    this.live = true,
    this.youOwn = false,
    this.muted = false,
    this.memberCount = 0,
    this.liveCount = 0,
  });

  /// Live right now (a hangout is on) — or offline, waiting for the owner.
  final bool live;

  /// It's your Huud, for good.
  final bool youOwn;

  /// You've muted this Huud's "it's live" notifications.
  final bool muted;

  /// Everyone who belongs to the Huud, and how many are in the Live hangout.
  final int memberCount;
  final int liveCount;

  /// The host's backdrop: "lounge", "poolside", "club" — null for none.
  final String? background;

  final bool youCanSpeak;

  /// People looking in without joining.
  final int watching;

  /// Your own asks: "pending", "accepted", "declined" or null.
  final String? joinRequest, playRequest, micRequest;

  /// What the host has to answer (empty for everyone else).
  final List<HuudRequest> requests;
  final bool shared;
  final String? feedMessage;

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
        youCanSpeak: j['youCanSpeak'] == true,
        joinRequest: j['joinRequest'] as String?,
        playRequest: j['playRequest'] as String?,
        micRequest: j['micRequest'] as String?,
        requests: [
          for (final r in (j['requests'] as List? ?? const []))
            HuudRequest.fromJson((r as Map).cast<String, dynamic>()),
        ],
        shared: j['shared'] == true,
        feedMessage: j['feedMessage'] as String?,
        watching: (j['watching'] as num?)?.toInt() ?? 0,
        background: j['background'] as String?,
        live: j['live'] != false,
        youOwn: j['youOwn'] == true,
        muted: j['muted'] == true,
        memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
        liveCount: (j['liveCount'] as num?)?.toInt() ?? 0,
      );
}

/// Someone asking the host: to come in ("join"), to play ("play"), or to talk ("mic").
class HuudRequest {
  const HuudRequest({required this.from, required this.kind});
  final HuudMember from;
  final String kind;

  String get ask => switch (kind) {
        'join' => 'wants to come in',
        'play' => 'wants to play',
        _ => 'wants to talk',
      };

  String get emoji => switch (kind) {
        'join' => '🚪',
        'play' => '🎮',
        _ => '🎙️',
      };

  factory HuudRequest.fromJson(Map<String, dynamic> j) => HuudRequest(
        from: HuudMember.fromJson((j['from'] as Map).cast<String, dynamic>()),
        kind: j['kind'] as String? ?? 'join',
      );
}

class HuudChatMessage {
  const HuudChatMessage({required this.id, required this.from, required this.body, required this.at});
  final int id;
  final HuudMember from;
  final String body;
  final DateTime at;

  factory HuudChatMessage.fromJson(Map<String, dynamic> j) => HuudChatMessage(
        id: (j['id'] as num).toInt(),
        from: HuudMember.fromJson((j['from'] as Map).cast<String, dynamic>()),
        body: j['body'] as String? ?? '',
        at: DateTime.tryParse(j['at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
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
    this.watching = 0,
  });

  final int watching;

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
        watching: (j['watching'] as num?)?.toInt() ?? 0,
      );
}

/// A Huud you belong to, for the Huud tab.
class MyHuud {
  const MyHuud({
    required this.id,
    required this.name,
    required this.privacy,
    required this.live,
    required this.youOwn,
    required this.memberCount,
    required this.liveCount,
    required this.members,
    this.host,
    this.gameType,
    this.gameStatus,
    this.background,
    this.muted = false,
  });

  final String id;
  final String name;
  final HuudPrivacy privacy;
  final bool live;
  final bool youOwn;
  final HuudMember? host;
  final int memberCount;
  final int liveCount;
  final List<HuudMember> members;
  final String? gameType;
  final String? gameStatus;
  final String? background;
  final bool muted;

  factory MyHuud.fromJson(Map<String, dynamic> j) => MyHuud(
        id: j['id'].toString(),
        name: j['name'] as String? ?? 'Huud',
        privacy: HuudPrivacyInfo.parse(j['privacy'] as String?),
        live: j['live'] == true,
        youOwn: j['youOwn'] == true,
        host: j['host'] == null ? null : HuudMember.fromJson((j['host'] as Map).cast<String, dynamic>()),
        memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
        liveCount: (j['liveCount'] as num?)?.toInt() ?? 0,
        members: [
          for (final m in (j['members'] as List? ?? const [])) HuudMember.fromJson((m as Map).cast<String, dynamic>()),
        ],
        gameType: j['gameType'] as String?,
        gameStatus: j['gameStatus'] as String?,
        background: j['background'] as String?,
        muted: j['muted'] == true,
      );
}

/// "Live now · 8 in Huud · Playing Whot" — or "Offline · 12 members".
String huudStatusLine(
    {required bool live, required int liveCount, required int memberCount, String? game, String? gameStatus}) {
  if (!live) return memberCount == 1 ? 'Offline · 1 member' : 'Offline · $memberCount members';
  final doing = game == null
      ? null
      : switch (gameStatus) {
          'playing' => 'Playing $game',
          'waiting' => '$game starting soon',
          _ => null,
        };
  return ['Live now', '$liveCount in Huud', if (doing != null) doing].join(' · ');
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

/// Someone at the game's table and whether they're ready.
class HuudSeat {
  const HuudSeat({required this.userId, required this.name, this.avatarUrl, this.bot = false, this.ready = false});
  final String userId;
  final String name;
  final String? avatarUrl;
  final bool bot;
  final bool ready;

  String get handle => name;

  factory HuudSeat.fromJson(Map<String, dynamic> j) => HuudSeat(
        userId: j['userId'].toString(),
        name: j['displayName'] as String? ?? 'Player',
        avatarUrl: j['avatarUrl'] as String?,
        bot: j['bot'] == true,
        ready: j['ready'] == true,
      );
}
