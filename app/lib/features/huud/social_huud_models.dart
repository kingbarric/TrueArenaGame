class HuudParticipant {
  const HuudParticipant(
      {required this.userId,
      required this.username,
      this.avatarUrl,
      this.status = 'participant'});
  final String userId;
  final String username;
  final String? avatarUrl;
  final String status;
  factory HuudParticipant.fromJson(Map<String, dynamic> j) => HuudParticipant(
      userId: j['userId'].toString(),
      username: j['username'] as String? ?? 'Player',
      avatarUrl: j['avatarUrl'] as String?,
      status: j['status'] as String? ?? 'participant');
}

class SocialHuud {
  const SocialHuud(
      {required this.id,
      required this.code,
      required this.ownerId,
      required this.name,
      required this.description,
      required this.privacy,
      required this.activity,
      required this.status,
      required this.activityVersion,
      required this.participantCount,
      required this.viewerCount,
      required this.playerCount,
      required this.participant,
      required this.joinRequestStatus,
      required this.gameRequestStatus,
      required this.participants,
      required this.joinRequests,
      required this.gameRequests,
      required this.selectedPlayers,
      this.gameType,
      this.currentRoomId,
      this.minPlayers = 0,
      this.maxPlayers = 0,
      this.allowedCounts = const []});
  final String id, code, ownerId, name, description, privacy, activity, status;
  final String? gameType, currentRoomId;
  final int activityVersion,
      participantCount,
      viewerCount,
      playerCount,
      minPlayers,
      maxPlayers;
  final bool participant;
  final String joinRequestStatus, gameRequestStatus;
  final List<HuudParticipant> participants, joinRequests, gameRequests;
  final List<String> selectedPlayers;
  final List<int> allowedCounts;
  bool get waiting => activity == 'waiting';
  bool get playing => activity == 'playing';
  bool get results => activity == 'results';
  bool get validRoster =>
      selectedPlayers.length >= minPlayers &&
      selectedPlayers.length <= maxPlayers &&
      (allowedCounts.isEmpty || allowedCounts.contains(selectedPlayers.length));
  String get gameName => socialGameName(gameType);
  factory SocialHuud.fromJson(Map<String, dynamic> j) {
    List<HuudParticipant> people(String key) => (j[key] as List? ?? [])
        .map(
            (p) => HuudParticipant.fromJson((p as Map).cast<String, dynamic>()))
        .toList();
    final capacity = (j['capacity'] as Map?)?.cast<String, dynamic>();
    return SocialHuud(
        id: j['id'].toString(),
        code: j['code'].toString(),
        ownerId: j['ownerId'].toString(),
        name: j['name'] as String,
        description: j['description'] as String? ?? '',
        privacy: j['privacy'] as String,
        activity: j['activity'] as String,
        status: j['status'] as String,
        gameType: j['gameType'] as String?,
        currentRoomId: j['currentRoomId'] as String?,
        activityVersion: (j['activityVersion'] as num).toInt(),
        participantCount: (j['participantCount'] as num).toInt(),
        viewerCount: (j['viewerCount'] as num).toInt(),
        playerCount: (j['playerCount'] as num).toInt(),
        participant: j['participant'] == true,
        joinRequestStatus: j['joinRequestStatus'] as String? ?? 'none',
        gameRequestStatus: j['gameRequestStatus'] as String? ?? 'none',
        participants: people('participants'),
        joinRequests: people('joinRequests'),
        gameRequests: people('gameRequests'),
        selectedPlayers: (j['selectedPlayers'] as List? ?? [])
            .map((p) => p.toString())
            .toList(),
        minPlayers: (capacity?['min'] as num?)?.toInt() ?? 0,
        maxPlayers: (capacity?['max'] as num?)?.toInt() ?? 0,
        allowedCounts: (capacity?['allowed'] as List? ?? [])
            .map((n) => (n as num).toInt())
            .toList());
  }
}

String socialGameName(String? type) =>
    const {
      'draughts': 'Draughts',
      'whot': 'Whot',
      'chess': 'Chess',
      'ludo': 'Ludo',
      'goosi': 'Macala',
      'wordbluff': 'Word Bluff',
      'truearena': 'Traitors',
      'slayhuud': 'SlayHuud',
    }[type] ??
    'Just hanging out';
