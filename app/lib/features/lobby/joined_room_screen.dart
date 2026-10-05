import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/game_socket.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../../widgets/copyable_huud_code.dart';
import '../draughts/draughts_game_screen.dart';
import '../game/game_screen.dart';
import '../goosi/goosi_game_screen.dart';
import '../whot/whot_game_screen.dart';
import '../ludo/ludo_game_screen.dart';
import '../wordbluff/wordbluff_game_screen.dart';

/// The lobby for a room this device *joined* rather than created — same live
/// roster/ready/socket wiring as `LobbyScreen`/`WordBluffLobbyScreen`, but
/// generic across both game types (it doesn't know which one until the
/// `POST /rooms/join` response says so) and never posts `GAME_START` itself
/// since a joiner is essentially never the host.
class JoinedRoomScreen extends StatefulWidget {
  const JoinedRoomScreen({super.key, required this.room});
  final RoomView room;

  @override
  State<JoinedRoomScreen> createState() => _JoinedRoomScreenState();
}

class _JoinedRoomScreenState extends State<JoinedRoomScreen> {
  late RoomView _room;
  GameSocket? _socket;
  StreamSubscription? _sub;
  bool _handedOff = false;
  String _gameMode = 'relay';
  bool _ready = false;
  late AppState _app;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = AppScope.of(context);
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (!_handedOff) _socket?.close();
    super.dispose();
  }

  void _connect() {
    _app = AppScope.of(context);
    final socket = GameSocket.connect(_app.api, _room.id);
    _socket = socket;
    _sub = socket.envelopes.listen((env) {
      switch (env['type']) {
        case 'CONNECTION':
          // A resume already knows from GET /rooms/{id} that the match is in
          // progress. Hand the live socket to the game immediately, before its
          // HELLO response arrives, so the game screen receives the first
          // snapshot itself instead of briefly rendering an empty board.
          final payload = (env['payload'] as Map?)?.cast<String, dynamic>();
          if (payload?['connected'] == true && _room.status == 'in_game') {
            _handOffToGame();
          }
        case 'SNAPSHOT':
          final p = (env['payload'] as Map).cast<String, dynamic>();
          if (p['lobby'] == true) _applyLobbySnapshot(p);
          if (p['lobby'] == false) {
            _handOffToGame();
          }
        case 'EVENT':
          socket.send('HELLO', {'lastSeq': 0});
        case 'PHASE':
          _handOffToGame();
        case 'ERROR':
          final msg = (env['payload'] as Map)['message']?.toString();
          if (msg != null && mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(msg)));
          }
      }
    });
    socket.send('HELLO', {'lastSeq': 0});
  }

  void _applyLobbySnapshot(Map<String, dynamic> p) {
    final members = ((p['members'] as List?) ?? const [])
        .map((e) => RoomMember.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    if (!mounted) return;
    setState(() {
      _gameMode = p['mode'] as String? ?? _gameMode;
      _room = RoomView(
        id: p['roomId'] as String,
        code: p['code'] as String,
        hostId: p['hostId'] as String,
        status: p['status'] as String? ?? 'lobby',
        gameType: _room.gameType,
        members: members,
      );
      final me = _room.members.where((m) => m.userId == _selfId());
      if (me.isNotEmpty) _ready = me.first.ready;
    });
  }

  void _handOffToGame() {
    if (_handedOff || !mounted) return;
    _handedOff = true;
    _sub?.cancel();
    final nicknames = {
      for (final m in _room.members) m.userId: m.nickname ?? m.userId
    };
    final selfId = _selfId();
    final isHost = _room.hostId == selfId;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => switch (_room.gameType) {
        'wordbluff' => WordBluffGameScreen(
            socket: _socket!,
            selfId: selfId,
            isHost: isHost,
            nicknames: nicknames),
        'draughts' => DraughtsGameScreen(
            socket: _socket!, selfId: selfId, nicknames: nicknames),
        'whot' => WhotGameScreen(
              socket: _socket!,
              selfId: selfId,
              roomId: _room.id,
              roomCode: _room.code,
              nicknames: nicknames,
              avatars: {
                for (final m in _room.members)
                  if (m.avatarUrl?.isNotEmpty == true)
                    m.userId: m.avatarUrl!
                  else if (m.isBot)
                    m.userId: '🤖'
              }),
        'ludo' => LudoGameScreen(
              socket: _socket!,
              selfId: selfId,
              roomCode: _room.code,
              nicknames: nicknames,
              agents: {
                for (final m in _room.members)
                  if (m.isBot) m.userId
              }),
        'goosi' => GoosiGameScreen(
              socket: _socket!,
              selfId: selfId,
              roomCode: _room.code,
              nicknames: nicknames,
              avatars: {
                for (final m in _room.members)
                  if (m.avatarUrl?.isNotEmpty == true) m.userId: m.avatarUrl!,
              },
              agents: {
                for (final m in _room.members)
                  if (m.isBot) m.userId,
              }),
        _ => GameScreen(
            socket: _socket!,
            selfId: selfId,
            isHost: isHost,
            nicknames: nicknames),
      },
    ));
  }

  String _selfId() => _app.user?.id ?? '';

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_room.gameType) {
          'wordbluff' => 'Word Bluff',
          'draughts' => 'Draft',
          'goosi' => 'Macala',
          'whot' => 'Whot',
          _ => 'Traitors',
        }),
        actions: [
          IconButton(
            tooltip: 'Copy code',
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _room.code));
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied ${_room.code}')));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            MarqueeBar(_room.gameType == 'goosi'
                ? _gameMode == 'oware'
                    ? 'OWARE ABAPA  •  CAPTURE 2 OR 3  •  WAITING ON HOST'
                    : 'RELAY FOUR  •  COLLECT FOUR  •  WAITING ON HOST'
                : 'YOU\'RE IN  •  READY UP  •  WAITING ON THE HOST TO START'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: NeonCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('HUUD CODE',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: n.mute, letterSpacing: 2)),
                      const SizedBox(height: 4),
                      CopyableHuudCode(
                        code: _room.code,
                        child: Text(_room.code,
                            style: Theme.of(context)
                                .textTheme
                                .displayLarge
                                ?.copyWith(
                                    fontSize: 40,
                                    letterSpacing: 6,
                                    shadows: [
                                  Shadow(
                                      color: n.gold.withValues(alpha: 0.4),
                                      blurRadius: 30)
                                ])),
                      ),
                    ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text("WHO'S IN THE HUUD?",
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: n.gold)),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.76,
                ),
                itemCount: _room.members.length,
                itemBuilder: (context, i) =>
                    _memberTile(_room.members[i], _room.hostId),
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(RoomMember m, String hostId) {
    final n = context.neon;
    final isHost = m.userId == hostId;
    final away = !m.isBot && !m.connected;
    final ringColor = away ? kCabinetInk : (m.ready ? n.jade : n.mute);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ringColor, width: away ? 1.6 : 2.6),
                boxShadow: !away && m.ready
                    ? [
                        BoxShadow(
                            color: n.jade.withValues(alpha: 0.38),
                            blurRadius: 16,
                            spreadRadius: -2)
                      ]
                    : null,
              ),
              child: Opacity(
                  opacity: away ? 0.4 : 1,
                  child: OnlineAvatar(m.nickname ?? '?',
                      size: 60,
                      imageUrl: m.avatarUrl,
                      online: m.isBot || m.connected)),
            ),
            if (isHost)
              Positioned(
                top: -3,
                left: -3,
                child: _badge(
                    n,
                    n.brand,
                    const Icon(Icons.workspace_premium_rounded,
                        size: 12, color: Colors.white)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(m.nickname ?? m.userId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: away ? n.mute : n.ink, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(away ? 'AWAY' : (m.ready ? 'READY' : 'WAITING'),
            style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: away ? n.mute : (m.ready ? n.jade : n.mute))),
      ],
    );
  }

  Widget _badge(NeonColors n, Color bg, Widget icon) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: n.panel, width: 2)),
        child: icon,
      );

  Widget _bottomBar() {
    final n = context.neon;
    final isHost = _room.hostId == _selfId();
    final readyCount = _room.members.where((m) => m.ready).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
          color: n.panel, border: Border(top: BorderSide(color: n.line))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('$readyCount of ${_room.members.length} ready',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: n.mute, fontWeight: FontWeight.w700)),
        ),
        Row(children: [
          Expanded(
            child: NeonButton(
              _ready ? 'Ready ✓' : 'Ready up',
              style: NeonStyle.ghost,
              onPressed: () {
                final next = !_ready;
                setState(() => _ready = next);
                _socket?.send('READY_SET', {'ready': next});
              },
            ),
          ),
          // A joiner only sees Start if host migration (the original host
          // disconnecting) has actually made them the host — same rule the
          // backend enforces on GAME_START either way.
          if (isHost) ...[
            const SizedBox(width: 8),
            Expanded(
                child: NeonButton('Start',
                    onPressed: () => _socket?.send('GAME_START'))),
          ],
        ]),
      ]),
    );
  }
}
