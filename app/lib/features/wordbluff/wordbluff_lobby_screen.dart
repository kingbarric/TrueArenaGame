import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/game_socket.dart';
import '../../core/models.dart';
import '../../widgets/pending_huud.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/cyber_agent_sheet.dart';
import '../../widgets/copyable_huud_code.dart';
import '../../widgets/invite_players_sheet.dart';
import '../../widgets/neon.dart';
import 'wordbluff_game_screen.dart';
import '../../widgets/lobby_start_bar.dart';

/// The room before a Word Bluff game starts. Mirrors `LobbyScreen`'s shape
/// (see docs/DEV_REFERENCE.md §4) but posts `gameType: 'wordbluff'` and hands
/// off to `WordBluffGameScreen` instead — there are no presets to pick here,
/// just a minimum head-count (4, enforced server-side as `NOT_ENOUGH_PLAYERS`).
class WordBluffLobbyScreen extends StatefulWidget {
  const WordBluffLobbyScreen({super.key});

  @override
  State<WordBluffLobbyScreen> createState() => _WordBluffLobbyScreenState();
}

class _WordBluffLobbyScreenState extends State<WordBluffLobbyScreen> {
  RoomView? _room;
  bool _example = false;
  String? _error;
  bool _ready = false;
  bool _addingBot = false;

  GameSocket? _socket;
  StreamSubscription? _sub;
  bool _handedOff = false;
  late AppState _app;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (!_handedOff) _socket?.close();
    super.dispose();
  }

  Future<void> _open() async {
    final app = AppScope.of(context);
    _app = app;
    try {
      if (await resumePendingHuud(context, app, 'wordbluff')) return;
      if (!mounted) return;
    } catch (_) {
      if (mounted)
        setState(
            () => _error = 'Could not check your waiting Huud. Try again.');
      return;
    }
    if (app.identity == Identity.anonymous) {
      setState(() {
        _example = true;
        _room = _exampleRoom(app);
      });
      return;
    }
    try {
      final res = await app.api
              .post('/rooms', const <String, dynamic>{'gameType': 'wordbluff'})
          as Map<String, dynamic>;
      if (!mounted) return;
      final room = RoomView.fromJson(res);
      await app.rememberActiveRoom(room.id);
      setState(() => _room = room);
      _connect(app, room.id);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _example = true;
          _room = _exampleRoom(app);
        });
      }
    }
  }

  void _connect(AppState app, String roomId) {
    final socket = GameSocket.connect(app.api, roomId);
    _socket = socket;
    _sub = socket.envelopes.listen((env) {
      if (!mounted) return;
      if (handleCancelledHuud(context, env, _room!.id)) return;
      switch (env['type']) {
        case 'SNAPSHOT':
          final p = (env['payload'] as Map).cast<String, dynamic>();
          if (p['lobby'] == true) _applyLobbySnapshot(p);
        case 'EVENT':
          socket.send('HELLO', {'lastSeq': 0});
        case 'PHASE':
          _handOffToGame(app, roomId);
        case 'ERROR':
          final msg = (env['payload'] as Map)['message']?.toString();
          if (msg != null && mounted)
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(msg)));
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
      _room = RoomView(
        id: p['roomId'] as String,
        code: p['code'] as String,
        hostId: p['hostId'] as String,
        status: p['status'] as String? ?? 'lobby',
        gameType: 'wordbluff',
        members: members,
      );
      final me = _room!.members.where((m) => m.userId == _selfId(_app));
      if (me.isNotEmpty) _ready = me.first.ready;
    });
  }

  void _handOffToGame(AppState app, String roomId) {
    if (_handedOff || !mounted) return;
    _handedOff = true;
    _sub?.cancel();
    final room = _room!;
    final nicknames = {
      for (final m in room.members) m.userId: m.nickname ?? m.userId
    };
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => WordBluffGameScreen(
        socket: _socket!,
        selfId: _selfId(app),
        isHost: room.hostId == _selfId(app),
        nicknames: nicknames,
      ),
    ));
  }

  String _selfId(AppState app) => app.user?.id ?? '';

  Future<void> _invitePlayers(RoomView room) async {
    final sent = await showInvitePlayersSheet(context, roomId: room.id);
    if (sent == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(sent == 0
          ? 'No invites sent'
          : 'Invited $sent ${sent == 1 ? 'friend' : 'friends'} — they\'ll see it in their chat'),
    ));
  }

  Future<void> _addBot(RoomView room) async {
    final choice = await showCyberAgentPicker(context,
        defaultName: 'Cyber ${room.members.where((m) => m.isBot).length + 1}');
    if (choice == null || !mounted) return;
    setState(() => _addingBot = true);
    try {
      final app = AppScope.of(context);
      await app.api.post('/rooms/${room.id}/bots',
          {'name': choice.name, 'difficulty': choice.difficulty});
      // the bot connects itself over WS right after this and shows up via
      // the lobby's own SNAPSHOT/EVENT stream — nothing else to do here.
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not add the Cyber Agent')));
    } finally {
      if (mounted) setState(() => _addingBot = false);
    }
  }

  RoomView _exampleRoom(AppState app) {
    final me = app.user?.displayName ?? 'You';
    return RoomView(
      id: 'example',
      code: 'BLUFF3',
      hostId: 'me',
      status: 'lobby',
      members: [
        RoomMember(userId: 'me', nickname: me, ready: _ready, connected: true),
        const RoomMember(
            userId: 'p2', nickname: 'Ronan', ready: true, connected: true),
        const RoomMember(
            userId: 'p3', nickname: 'Priya', ready: true, connected: true),
        const RoomMember(
            userId: 'p4', nickname: 'Dex', ready: false, connected: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final room = _room;
    final enough = (room?.members.length ?? 0) >= 4;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Word Bluff'),
        actions: [
          if (room != null)
            IconButton(
              tooltip: 'Copy code',
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: room.code));
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copied ${room.code}')));
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const MarqueeBar(
                'teams of 2+  •  describe without saying the word  •  first to 30 wins'),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: TextStyle(color: n.danger))),
            if (room == null && _error == null)
              const Expanded(child: Center(child: CircularProgressIndicator())),
            if (room != null) ...[
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
                          code: room.code,
                          child: Text(room.code,
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
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          _chip(n, 'min 4 players'),
                          _chip(n, '2 teams'),
                          _chip(n, '20 categories'),
                        ]),
                      ]),
                ),
              ),
              if (_example)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('Example roster — sign in to host a real huud.',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: n.mute)),
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
                  itemCount: room.members.length,
                  itemBuilder: (context, i) =>
                      _memberTile(room.members[i], room.hostId),
                ),
              ),
              _bottomBar(room, enough),
            ],
          ],
        ),
      ),
    );
  }

  Widget _memberTile(RoomMember m, String hostId) {
    final n = context.neon;
    final isHost = m.userId == hostId || (m.userId == 'me' && _example);
    final away = !m.isBot && !m.connected;
    final ringColor = away ? kCabinetInk : n.jade;
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
                boxShadow: !away
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
            Positioned(
              bottom: -2,
              right: -2,
              child: m.isBot
                  ? _badge(
                      n,
                      n.jade,
                      const Icon(Icons.smart_toy_rounded,
                          size: 13, color: Colors.black))
                  : _badge(n, n.plate,
                      Icon(Icons.mic_off_rounded, size: 13, color: n.mute),
                      border: kCabinetInk),
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
        Text(
            m.isBot
                ? 'CYBER AGENT'
                : (away ? 'AWAY' : 'HERE'),
            style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: away ? n.mute : n.jade)),
      ],
    );
  }

  Widget _badge(NeonColors n, Color bg, Widget icon, {Color? border}) =>
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: border ?? n.panel, width: 2)),
        child: icon,
      );

  Widget _bottomBar(RoomView room, bool enough) {
    final n = context.neon;
    final app = AppScope.of(context);
    final isHost = _example || room.hostId == app.user?.id;
    final full = room.members.length >= 16;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
          color: n.panel, border: Border(top: BorderSide(color: n.line))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            enough
                ? '${room.members.length} players in'
                : 'Need at least 4 players (2 per team)',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: n.mute, fontWeight: FontWeight.w700),
          ),
        ),
        if (isHost && !full && !_example) ...[
          // Inviting a real friend is the headline action; an agent is the
          // fallback when nobody's around, so it sits underneath as a small
          // pill rather than competing as a full-width button.
          NeonButton('Add a player', onPressed: () => _invitePlayers(room)),
          const SizedBox(height: 8),
          Center(
            child: Bouncy(
              feel: BouncyFeel.snap,
              onTap: _addingBot ? null : () => _addBot(room),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: n.plate,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: n.line, width: 1.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.smart_toy_rounded,
                      size: 14, color: _addingBot ? n.mute : n.gold),
                  const SizedBox(width: 6),
                  Text(_addingBot ? 'Adding…' : 'or add a Cyber Agent',
                      style: TextStyle(
                          color: _addingBot ? n.mute : n.mid,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        LobbyStartBar(
          isHost: isHost,
          onStart: !enough
              ? null
              : () {
                  if (_example) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Add an account to host a game.')));
                  } else {
                    _socket?.send('GAME_START');
                  }
                },
        ),
      ]),
    );
  }

  Widget _chip(NeonColors n, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
            color: n.plate,
            borderRadius: BorderRadius.circular(NeonRadius.pill),
            border: Border.all(color: kCabinetInk, width: 1.6)),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                color: n.mid,
                fontWeight: FontWeight.w800,
                fontSize: 8,
                letterSpacing: 0.6)),
      );
}
