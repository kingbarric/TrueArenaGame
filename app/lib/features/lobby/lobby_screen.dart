import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';

/// The room before the game starts. For a signed-in host this creates a real
/// ad-hoc room via POST /api/v1/rooms and shows the returned code + roster; the
/// live roster + ready-check + start come with the WebSocket layer (Phase 4).
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.preset});
  final ModePreset preset;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  RoomView? _room;
  bool _example = false;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final app = AppScope.of(context);
    if (app.identity != Identity.account) {
      setState(() {
        _example = true;
        _room = _exampleRoom(app);
      });
      return;
    }
    try {
      final res = await app.api.post('/rooms', const <String, dynamic>{}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _room = RoomView.fromJson(res));
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

  RoomView _exampleRoom(AppState app) {
    final me = app.user?.displayName ?? 'You';
    return RoomView(
      id: 'example',
      code: 'NIGHT7',
      hostId: 'me',
      status: 'lobby',
      members: [
        RoomMember(userId: 'me', nickname: me, ready: _ready, connected: true),
        const RoomMember(userId: 'p2', nickname: 'Ronan', ready: true, connected: true),
        const RoomMember(userId: 'p3', nickname: 'Priya', ready: true, connected: true),
        const RoomMember(userId: 'p4', nickname: 'Dex', ready: false, connected: true),
        const RoomMember(userId: 'p5', nickname: 'Ana', ready: true, connected: true),
        const RoomMember(userId: 'p6', nickname: 'Otis', ready: false, connected: false),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final p = widget.preset;
    final room = _room;

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          if (room != null)
            IconButton(
              tooltip: 'Copy code',
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: room.code));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied ${room.code}')),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const MarqueeBar('waiting on the table  •  host sets the rules  •  tap to ready up'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: TextStyle(color: n.danger)),
              ),
            if (room == null && _error == null)
              const Expanded(child: Center(child: CircularProgressIndicator())),
            if (room != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: NeonCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ROOM CODE',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, letterSpacing: 2)),
                    const SizedBox(height: 4),
                    Text(room.code,
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            fontSize: 40, letterSpacing: 6, shadows: [Shadow(color: n.cyan.withValues(alpha: 0.4), blurRadius: 30)])),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      _chip('${p.minPlayers}–${p.maxPlayers} players'),
                      _chip('${p.traitors} traitors'),
                      _chip(p.veilLabel),
                      if (p.twistCount > 0) _chip('${p.twistCount} twist${p.twistCount == 1 ? '' : 's'}'),
                    ]),
                  ]),
                ),
              ),
              if (_example)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('Example roster — sign in to host a real room.',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    for (final m in room.members) _memberRow(m, room.hostId),
                  ],
                ),
              ),
              _bottomBar(room),
            ],
          ],
        ),
      ),
    );
  }

  Widget _memberRow(RoomMember m, String hostId) {
    final n = context.neon;
    final isHost = m.userId == hostId || (m.userId == 'me' && _example);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NeonCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Avatar(m.nickname ?? '?', size: 32, color: m.connected ? null : n.plate),
          const SizedBox(width: 10),
          Expanded(
            child: Text(m.nickname ?? m.userId,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: m.connected ? n.ink : n.mute, fontWeight: FontWeight.w700)),
          ),
          if (isHost) _tag('HOST', n.magenta),
          const SizedBox(width: 6),
          _tag(m.connected ? (m.ready ? 'READY' : 'WAIT') : 'AWAY', m.ready ? n.acid : n.mute),
        ]),
      ),
    );
  }

  Widget _bottomBar(RoomView room) {
    final n = context.neon;
    final app = AppScope.of(context);
    final isHost = _example || room.hostId == app.user?.id;
    final readyCount = room.members.where((m) => m.ready).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(color: n.panel, border: Border(top: BorderSide(color: n.line))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('$readyCount of ${room.members.length} ready',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, fontWeight: FontWeight.w700)),
        ),
        Row(children: [
          Expanded(
            child: NeonButton(
              _ready ? 'Ready ✓' : 'Ready up',
              style: NeonStyle.ghost,
              onPressed: () => setState(() {
                _ready = !_ready;
                if (_example) _room = _exampleRoom(app);
              }),
            ),
          ),
          if (isHost) ...[
            const SizedBox(width: 8),
            Expanded(
              child: NeonButton('Start', onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Start → role reveal comes with the WebSocket layer (Phase 4).')),
                );
              }),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _chip(String t) {
    final n = context.neon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: n.plate,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: n.line),
      ),
      child: Text(t.toUpperCase(),
          style: TextStyle(color: n.mid, fontWeight: FontWeight.w800, fontSize: 8, letterSpacing: 0.6)),
    );
  }

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 8, letterSpacing: 0.8)),
      );
}
