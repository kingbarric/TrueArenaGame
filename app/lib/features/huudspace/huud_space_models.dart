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

  static HuudPrivacy parse(String? wire) => HuudPrivacy.values
      .firstWhere((p) => p.name == wire, orElse: () => HuudPrivacy.friends);
}

class HuudMember {
  const HuudMember({
    required this.userId,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    this.huudAvatarId,
    this.huudOutfitId,
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
  final String? avatarUrl, huudAvatarId, huudOutfitId;
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
        huudAvatarId: j['huudAvatarId'] as String?,
        huudOutfitId: j['huudOutfitId'] as String?,
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
    this.mode,
  });

  /// Whot's "classic" or "tell"; null for every other game.
  final String? mode;

  bool get tell => gameType == 'whot' && mode == 'tell';

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
        playerIds: [
          for (final id in (j['playerIds'] as List? ?? const [])) id.toString()
        ],
        youArePlaying: j['youArePlaying'] == true,
        readyIds: [
          for (final id in (j['readyIds'] as List? ?? const [])) id.toString()
        ],
        table: [
          for (final t in (j['table'] as List? ?? const []))
            HuudSeat.fromJson((t as Map).cast<String, dynamic>()),
        ],
        mode: j['mode'] as String?,
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
    this.youCanManageMic = false,
    required this.voiceRoom,
    this.code,
    this.host,
    this.currentGame,
    this.youCanSpeak = false,
    this.joinRequest,
    this.playRequest,
    this.micRequest,
    this.requests = const [],
    this.findingPlayers = false,
    this.shared = false,
    this.feedMessage,
    this.watching = 0,
    this.background,
    this.live = true,
    this.youOwn = false,
    this.muted = false,
    this.memberCount = 0,
    this.liveCount = 0,
    this.championshipId,
    this.quiet = false,
    this.elsewhere,
  });

  /// Live, but nobody in the hangout has had the app open for a while — it
  /// shows amber and is kept off the Live tab until someone's back.
  final bool quiet;

  /// You belong here and it's Live, but you're in another Huud's hangout —
  /// you're in one at a time. Opening this one leaves you there; Join brings
  /// you over.
  final HuudElsewhere? elsewhere;

  /// The championship on in the Huud (registering, being played, or just
  /// finished and still showing its bracket) — null when it's hanging out.
  final String? championshipId;

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
  final bool findingPlayers;
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
  final bool youCanManageMic;
  final String voiceRoom;

  bool get active => status == 'active';
  int get hereCount => members.where((m) => m.here).length;

  factory HuudSpace.fromJson(Map<String, dynamic> j) => HuudSpace(
        id: j['id'].toString(),
        code: j['code'] as String?,
        name: j['name'] as String? ?? 'Huud',
        privacy: HuudPrivacyInfo.parse(j['privacy'] as String?),
        status: j['status'] as String? ?? 'active',
        host: j['host'] == null
            ? null
            : HuudMember.fromJson((j['host'] as Map).cast<String, dynamic>()),
        members: [
          for (final m in (j['members'] as List? ?? const []))
            HuudMember.fromJson((m as Map).cast<String, dynamic>()),
        ],
        currentGame: j['currentGame'] == null
            ? null
            : HuudGame.fromJson(
                (j['currentGame'] as Map).cast<String, dynamic>()),
        youAreIn: j['youAreIn'] == true,
        youAreHost: j['youAreHost'] == true,
        youCanManageMic: j['youCanManageMic'] == true ||
            (j['youAreHost'] == true && !j.containsKey('youCanManageMic')),
        voiceRoom: j['voiceRoom'] as String? ?? 'huud-${j['id']}',
        youCanSpeak: j['youCanSpeak'] == true,
        joinRequest: j['joinRequest'] as String?,
        playRequest: j['playRequest'] as String?,
        micRequest: j['micRequest'] as String?,
        requests: [
          for (final r in (j['requests'] as List? ?? const []))
            HuudRequest.fromJson((r as Map).cast<String, dynamic>()),
        ],
        findingPlayers: j['findingPlayers'] == true,
        shared: j['shared'] == true,
        feedMessage: j['feedMessage'] as String?,
        watching: (j['watching'] as num?)?.toInt() ?? 0,
        background: j['background'] as String?,
        live: j['live'] != false,
        youOwn: j['youOwn'] == true,
        muted: j['muted'] == true,
        memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
        liveCount: (j['liveCount'] as num?)?.toInt() ?? 0,
        championshipId: j['championshipId']?.toString(),
        quiet: j['quiet'] == true,
        elsewhere: HuudElsewhere.fromJson(j['elsewhere']),
      );
}

/// The Live hangout you're in somewhere else. [playing]: you're in a game
/// there, so you finish that before coming over.
class HuudElsewhere {
  const HuudElsewhere({required this.id, required this.name, this.playing = false});
  final String id;
  final String name;
  final bool playing;

  static HuudElsewhere? fromJson(Object? j) => j is Map
      ? HuudElsewhere(id: j['id'].toString(), name: j['name'] as String? ?? 'another Huud', playing: j['playing'] == true)
      : null;
}

/// Huuds one person can have — one for each circle: family, friends, everyone.
const kMaxHuuds = 5;

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
  const HuudChatMessage(
      {required this.id,
      required this.from,
      required this.body,
      required this.at});
  final int id;
  final HuudMember from;
  final String body;
  final DateTime at;

  factory HuudChatMessage.fromJson(Map<String, dynamic> j) => HuudChatMessage(
        id: (j['id'] as num).toInt(),
        from: HuudMember.fromJson((j['from'] as Map).cast<String, dynamic>()),
        body: j['body'] as String? ?? '',
        at: DateTime.tryParse(j['at']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

/// What a Huud card says while a championship is on in it.
class HuudCupLine {
  const HuudCupLine(
      {required this.name,
      required this.gameType,
      required this.status,
      this.roundName});

  final String name;
  final String gameType;

  /// registering · playing · finished
  final String status;

  /// While playing: "Quarter Finals", "Semi Finals", "Final"…
  final String? roundName;

  /// "🏆 Chess Championship · Quarter Finals"
  String get text => switch (status) {
        'registering' => '🏆 $name · sign up now',
        'playing' => roundName == null
            ? '🏆 $name'
            : '🏆 $name · ${roundName == 'Final' ? 'the Final' : roundName}',
        'finished' => '🏆 $name · finished',
        _ => '🏆 $name',
      };

  static HuudCupLine? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    return HuudCupLine(
      name: j['name'] as String? ?? 'Championship',
      gameType: j['gameType'] as String? ?? 'chess',
      status: j['status'] as String? ?? 'playing',
      roundName: j['roundName'] as String?,
    );
  }
}

/// Something that just happened in a Live Huud: a move in the game on now
/// (`play`), a `win`, someone who `joined`, the Huud going `live`, or — for
/// its own members — a `chat` line. [who] is empty when the game itself is
/// talking; [at] is empty for a play, which is happening now.
class HuudMoment {
  const HuudMoment({required this.kind, required this.text, this.who, this.at});

  final String kind;
  final String text;
  final HuudMember? who;
  final DateTime? at;

  /// The little picture beside the line.
  String get symbol => switch (kind) {
        'win' => '🏆',
        'joined' => '👋',
        'live' => '📡',
        'chat' => '💬',
        _ => '🎮',
      };

  factory HuudMoment.fromJson(Map<String, dynamic> j) => HuudMoment(
        kind: j['kind'] as String? ?? 'play',
        text: j['text'] as String? ?? '',
        who: j['who'] == null ? null : HuudMember.fromJson((j['who'] as Map).cast<String, dynamic>()),
        at: DateTime.tryParse(j['at'] as String? ?? ''),
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
    this.findingPlayers = false,
    this.host,
    this.gameType,
    this.gameStatus,
    this.watching = 0,
    this.championship,
    this.background,
    this.moments = const [],
    this.gamesPlayed = 0,
    this.recentMessages = 0,
  });

  final bool findingPlayers;
  final int watching;

  /// The picture behind the card's top, as the host chose it.
  final String? background;

  /// What's going on in there, newest first.
  final List<HuudMoment> moments;

  /// Games finished since it went Live, and chat lines in the last half hour.
  final int gamesPlayed, recentMessages;

  /// A championship on in it — the card says that instead of the game.
  final HuudCupLine? championship;

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
        findingPlayers: j['findingPlayers'] == true,
        id: j['id'].toString(),
        name: j['name'] as String? ?? 'Huud',
        privacy: HuudPrivacyInfo.parse(j['privacy'] as String?),
        host: j['host'] == null
            ? null
            : HuudMember.fromJson((j['host'] as Map).cast<String, dynamic>()),
        memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
        members: [
          for (final m in (j['members'] as List? ?? const []))
            HuudMember.fromJson((m as Map).cast<String, dynamic>()),
        ],
        gameType: j['gameType'] as String?,
        gameStatus: j['gameStatus'] as String?,
        youAreIn: j['youAreIn'] == true,
        watching: (j['watching'] as num?)?.toInt() ?? 0,
        championship: HuudCupLine.fromJson(j['championship']),
        background: j['background'] as String?,
        moments: [
          for (final m in (j['moments'] as List? ?? const []))
            HuudMoment.fromJson((m as Map).cast<String, dynamic>()),
        ],
        gamesPlayed: (j['gamesPlayed'] as num?)?.toInt() ?? 0,
        recentMessages: (j['recentMessages'] as num?)?.toInt() ?? 0,
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
    this.championship,
    this.quiet = false,
  });

  /// Live, but nobody in it has had the app open for a while (amber).
  final bool quiet;

  /// A championship on in it — the card says that instead of the game.
  final HuudCupLine? championship;

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
        host: j['host'] == null
            ? null
            : HuudMember.fromJson((j['host'] as Map).cast<String, dynamic>()),
        memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
        liveCount: (j['liveCount'] as num?)?.toInt() ?? 0,
        members: [
          for (final m in (j['members'] as List? ?? const []))
            HuudMember.fromJson((m as Map).cast<String, dynamic>()),
        ],
        gameType: j['gameType'] as String?,
        gameStatus: j['gameStatus'] as String?,
        background: j['background'] as String?,
        muted: j['muted'] == true,
        championship: HuudCupLine.fromJson(j['championship']),
        quiet: j['quiet'] == true,
      );
}

/// "Live now · 8 in Huud · Playing Whot" — or "Offline · 12 members", or
/// "Quiet · nobody on right now" for a Live Huud no one is using.
/// A championship on in the Huud is said instead of the game.
String huudStatusLine(
    {required bool live,
    required int liveCount,
    required int memberCount,
    String? game,
    String? gameStatus,
    HuudCupLine? championship,
    bool quiet = false}) {
  if (!live) return memberCount == 1 ? 'Offline · 1 member' : 'Offline · $memberCount members';
  if (quiet) return 'Quiet · nobody on right now';
  final doing = championship != null
      ? championship.text
      : game == null
          ? null
          : switch (gameStatus) {
              'playing' => 'Playing $game',
              'waiting' => '$game starting soon',
              _ => null,
            };
  return ['Live now', '$liveCount in Huud', if (doing != null) doing]
      .join(' · ');
}

/// "Today", "Yesterday", "3 days ago", "12 Mar" — friendly, not a timestamp.
String huudWhen(DateTime when, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final day = _dateOnly(when);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${when.day} ${months[when.month - 1]}';
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// When a chat message was sent: "just now", "5 min ago" while it's fresh,
/// then the clock time — "3:42 pm", "Yesterday 3:42 pm", "12 Mar 3:42 pm".
String huudChatTime(DateTime at, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final gap = current.difference(at);
  if (gap.inMinutes < 1) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final clock =
      '$hour:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'am' : 'pm'}';
  final days = _dateOnly(current).difference(_dateOnly(at)).inDays;
  if (days <= 0) return clock;
  if (days == 1) return 'Yesterday $clock';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${at.day} ${months[at.month - 1]} $clock';
}

/// Someone at the game's table and whether they're ready.
class HuudSeat {
  const HuudSeat(
      {required this.userId,
      required this.name,
      this.avatarUrl,
      this.bot = false,
      this.ready = false});
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
