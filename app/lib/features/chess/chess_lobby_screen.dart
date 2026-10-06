import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/game_socket.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/copyable_huud_code.dart';
import '../../widgets/invite_players_sheet.dart';
import '../../widgets/neon.dart';
import '../../widgets/stake_picker_sheet.dart';
import '../../widgets/watching_eye.dart';
import 'chess_game_screen.dart';

/// A chess time control: minutes on each clock plus seconds added per move.
class ChessTimeControl {
  const ChessTimeControl(this.name, this.minutes, this.increment);
  final String name;
  final int minutes;
  final int increment;

  String get label => '$minutes+$increment';
  Map<String, dynamic> toConfig() =>
      {'initialSeconds': minutes * 60, 'incrementSeconds': increment};
}

const chessTimeControls = [
  ChessTimeControl('Bullet', 1, 0),
  ChessTimeControl('Blitz', 3, 2),
  ChessTimeControl('Blitz', 5, 0),
  ChessTimeControl('Rapid', 10, 0),
  ChessTimeControl('Rapid', 15, 10),
  ChessTimeControl('Classical', 30, 0),
];

/// The room before a chess game starts — exactly two players, like Draft.
/// The host picks a time control before the room exists; there's no Cyber
/// Agent for chess yet, so an opponent is always a person you invite or who
/// joins with the code.
class ChessLobbyScreen extends StatefulWidget {
  const ChessLobbyScreen({super.key});

  @override
  State<ChessLobbyScreen> createState() => _ChessLobbyScreenState();
}

class _ChessLobbyScreenState extends State<ChessLobbyScreen> {
  RoomView? _room;
  String? _error;
  bool _ready = false;
  ChessTimeControl _control = chessTimeControls[3];
  int _spectatorCount = 0;

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
    if (!_handedOff) {
      _socket?.close();
      final room = _room;
      if (room != null && room.hostId == _app.user?.id) {
        _app.api.delete('/rooms/${room.id}').catchError((_) {});
      }
    }
    super.dispose();
  }

  Future<void> _open() async {
    final app = AppScope.of(context);
    _app = app;
    final control = await showChessTimeControlSheet(context);
    if (!mounted) return;
    if (control == null) {
      Navigator.of(context).pop();
      return;
    }
    _control = control;
    int stake = 0;
    try {
      final wallet = await app.fetchWallet();
      if (!mounted) return;
      final picked =
          await showStakePicker(context, currentBalance: wallet.balance);
      if (!mounted) return;
      if (picked == null) {
        Navigator.of(context).pop();
        return;
      }
      stake = picked;
    } catch (_) {
      // No balance to stake against — host an unstaked room.
    }
    try {
      final res = await app.api.post('/rooms', {
        'gameType': 'chess',
        if (stake > 0) 'stake': stake,
        'gameConfig': control.toConfig(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      final room = RoomView.fromJson(res);
      await app.rememberActiveRoom(room.id);
      setState(() => _room = room);
      _connect(app, room.id);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open a huud. Try again.');
      }
    }
  }

  void _connect(AppState app, String roomId) {
    final socket = GameSocket.connect(app.api, roomId);
    _socket = socket;
    _sub = socket.envelopes.listen((env) {
      switch (env['type']) {
        case 'SNAPSHOT':
          final p = (env['payload'] as Map).cast<String, dynamic>();
          if (p['lobby'] == true) _applyLobbySnapshot(p);
        case 'EVENT':
          final ep = (env['payload'] as Map).cast<String, dynamic>();
          if (ep['type'] == 'SPECTATOR_COUNT') {
            final data =
                ((ep['data'] as Map?) ?? const {}).cast<String, dynamic>();
            if (mounted) {
              setState(() =>
                  _spectatorCount = data['count'] as int? ?? _spectatorCount);
            }
          }
          socket.send('HELLO', {'lastSeq': 0});
        case 'PHASE':
          _handOffToGame(app);
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
      _room = RoomView(
        id: p['roomId'] as String,
        code: p['code'] as String,
        hostId: p['hostId'] as String,
        status: p['status'] as String? ?? 'lobby',
        gameType: 'chess',
        members: members,
        stakeCoins: _room?.stakeCoins ?? 0,
      );
      _spectatorCount = p['spectatorCount'] as int? ?? _spectatorCount;
      final me = members.where((m) => m.userId == _app.user?.id);
      if (me.isNotEmpty) _ready = me.first.ready;
    });
  }

  void _handOffToGame(AppState app) {
    if (_handedOff || !mounted) return;
    _handedOff = true;
    _sub?.cancel();
    final room = _room!;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ChessGameScreen(
        socket: _socket!,
        selfId: app.user?.id ?? '',
        roomCode: room.code,
        nicknames: {
          for (final m in room.members) m.userId: m.nickname ?? m.userId
        },
        avatars: {
          for (final m in room.members)
            if (m.avatarUrl?.isNotEmpty == true) m.userId: m.avatarUrl!,
        },
      ),
    ));
  }

  Future<void> _invitePlayers(RoomView room) async {
    final sent = await showInvitePlayersSheet(context, roomId: room.id);
    if (sent == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(sent == 0
          ? 'No invites sent'
          : 'Invited $sent ${sent == 1 ? 'friend' : 'friends'} — they\'ll see it in their chat'),
    ));
  }

  void _start(RoomView room) {
    final count = room.members.length;
    if (count != 2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(count < 2
              ? 'Chess needs one opponent. Invite a friend or share the code.'
              : 'Chess is one on one. Remove the extra players before starting.')));
      return;
    }
    if (_socket == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Still connecting to the huud. Try again.')));
      return;
    }
    _socket!.send('GAME_START');
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final room = _room;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Chess')),
      body: SafeArea(
        child: Column(children: [
          MarqueeBar(
              '${_control.name} ${_control.label}  •  standard rules  •  colours drawn at random'),
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
                          style: t.labelSmall
                              ?.copyWith(color: n.mute, letterSpacing: 2)),
                      const SizedBox(height: 4),
                      CopyableHuudCode(
                        code: room.code,
                        child: Text(room.code,
                            style: t.displayLarge?.copyWith(
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
                        WatchingEye(count: _spectatorCount),
                        _chip(n, '1v1'),
                        _chip(n, '${_control.name} ${_control.label}'),
                        if (room.stakeCoins > 0)
                          _chip(n,
                              '🪙 ${room.stakeCoins} stake · ${room.stakeCoins * 2} pot'),
                      ]),
                    ]),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  for (final m in room.members)
                    ListTile(
                      leading: OnlineAvatar(m.nickname ?? '?',
                          size: 40, online: m.connected),
                      title: Text(m.nickname ?? m.userId),
                      subtitle: Text(m.userId == room.hostId
                          ? 'Host'
                          : (m.ready ? 'Ready' : 'Waiting')),
                      trailing: Icon(
                          m.ready
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked,
                          color: m.ready ? n.jade : n.mute),
                    ),
                ],
              ),
            ),
            _bottomBar(room),
          ],
        ]),
      ),
    );
  }

  Widget _bottomBar(RoomView room) {
    final n = context.neon;
    final isHost = room.hostId == _app.user?.id;
    final exact = room.members.length == 2;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
          color: n.panel, border: Border(top: BorderSide(color: n.line))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (isHost && !exact) ...[
          NeonButton('Invite a player',
              style: NeonStyle.ghost, onPressed: () => _invitePlayers(room)),
          const SizedBox(height: 10),
        ],
        Row(children: [
          Expanded(
            child: NeonButton(
              _ready ? 'Ready ✓' : 'Ready up',
              style: NeonStyle.gold,
              onPressed: () {
                final next = !_ready;
                setState(() => _ready = next);
                _socket?.send('READY_SET', {'ready': next});
              },
            ),
          ),
          if (isHost) ...[
            const SizedBox(width: 8),
            Expanded(child: NeonButton('Start', onPressed: () => _start(room))),
          ],
        ]),
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

/// The host's time control, picked before the room exists. Null if they
/// backed out.
Future<ChessTimeControl?> showChessTimeControlSheet(BuildContext context) {
  final n = context.neon;
  final t = Theme.of(context).textTheme;
  return showModalBottomSheet<ChessTimeControl>(
    context: context,
    backgroundColor: n.panel.withValues(alpha: 0.96),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TIME CONTROL', style: t.labelLarge?.copyWith(color: n.gold)),
            const SizedBox(height: 4),
            Text('Minutes on each clock + seconds added after every move.',
                style: t.bodySmall?.copyWith(color: n.mid)),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.35,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final c in chessTimeControls)
                  NeonCard(
                    key: ValueKey('chess-time-${c.label}'),
                    padding: const EdgeInsets.all(6),
                    onTap: () => Navigator.of(context).pop(c),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(c.label,
                            style: t.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        Text(c.name.toUpperCase(),
                            style: t.labelSmall
                                ?.copyWith(color: n.mute, letterSpacing: 1)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
