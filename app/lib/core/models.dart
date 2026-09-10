/// Wire models. `GameConfig` is kept as a raw map — the app renders and edits it
/// generically against the twist catalog rather than mirroring every field of
/// docs/GAME_CONFIG.md in Dart.

class UserView {
  const UserView({required this.id, required this.displayName, this.phone});

  final String id;
  final String displayName;
  final String? phone;

  factory UserView.fromJson(Map<String, dynamic> j) => UserView(
        id: j['id'] as String,
        displayName: j['displayName'] as String? ?? 'Player',
        phone: j['phone'] as String?,
      );
}

class AuthTokens {
  const AuthTokens({required this.access, required this.refresh, required this.user});

  final String access;
  final String refresh;
  final UserView user;

  factory AuthTokens.fromJson(Map<String, dynamic> j) => AuthTokens(
        access: j['accessToken'] as String,
        refresh: j['refreshToken'] as String,
        user: UserView.fromJson(j['user'] as Map<String, dynamic>),
      );
}

class ModePreset {
  const ModePreset({
    required this.id,
    required this.scope,
    required this.slug,
    required this.name,
    required this.tag,
    required this.description,
    required this.config,
  });

  final String id;
  final String scope; // builtin | group | user
  final String? slug;
  final String name;
  final String? tag; // e.g. "Default"
  final String? description;
  final Map<String, dynamic> config;

  bool get isCustomSlot => scope != 'builtin';

  Map<String, dynamic> get table => (config['table'] as Map).cast<String, dynamic>();
  int get minPlayers => table['minPlayers'] as int;
  int get maxPlayers => table['maxPlayers'] as int;
  int get traitors {
    final curve = (table['traitorCurve'] as List).cast<List>();
    return curve.isEmpty ? 0 : (curve.last[1] as num).toInt();
  }

  String get veilLabel {
    final v = config['endgameVeil'] as String? ?? 'off';
    return v == 'off' ? 'no veil' : 'veil ${v.replaceAll('final_', 'final ')}';
  }

  int get twistCount => (config['twists'] as Map?)?.length ?? 0;

  factory ModePreset.fromJson(Map<String, dynamic> j) => ModePreset(
        id: j['id'] as String,
        scope: j['scope'] as String? ?? 'builtin',
        slug: j['slug'] as String?,
        name: j['name'] as String? ?? 'Mode',
        tag: j['tag'] as String?,
        description: j['description'] as String?,
        config: (j['config'] as Map).cast<String, dynamic>(),
      );
}

class RoomMember {
  const RoomMember({required this.userId, this.nickname, required this.ready, required this.connected});
  final String userId;
  final String? nickname;
  final bool ready;
  final bool connected;

  factory RoomMember.fromJson(Map<String, dynamic> j) => RoomMember(
        userId: j['userId'] as String,
        nickname: j['nickname'] as String?,
        ready: j['ready'] as bool? ?? false,
        connected: (j['connectionStatus'] as String? ?? 'connected') == 'connected',
      );
}

class RoomView {
  const RoomView({
    required this.id,
    required this.code,
    required this.hostId,
    required this.status,
    required this.members,
    this.wsUrl,
  });

  final String id;
  final String code;
  final String hostId;
  final String status;
  final List<RoomMember> members;
  final String? wsUrl;

  factory RoomView.fromJson(Map<String, dynamic> j) => RoomView(
        id: j['id'] as String,
        code: j['code'] as String,
        hostId: j['hostId'] as String,
        status: j['status'] as String? ?? 'lobby',
        wsUrl: j['wsUrl'] as String?,
        members: ((j['members'] as List?) ?? const [])
            .map((e) => RoomMember.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class TwistMeta {
  const TwistMeta({required this.id, required this.name, required this.summary, required this.hooks});

  final String id;
  final String name;
  final String summary;
  final List<String> hooks;

  factory TwistMeta.fromJson(Map<String, dynamic> j) => TwistMeta(
        id: j['id'] as String,
        name: j['name'] as String,
        summary: j['summary'] as String,
        hooks: (j['hooks'] as List?)?.cast<String>() ?? const [],
      );
}
