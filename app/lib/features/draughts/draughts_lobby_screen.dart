import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/game_socket.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/cyber_agent_sheet.dart';
import '../../widgets/invite_players_sheet.dart';
import '../../widgets/neon.dart';
import '../../widgets/watching_eye.dart';
import '../../widgets/stake_picker_sheet.dart';
import 'draughts_game_screen.dart';

/// The room before a Draughts game starts. Same shape as
/// `WordBluffLobbyScreen`/`LobbyScreen`, but Draughts is exactly 1v1 rather
/// than "at least N" — `DraughtsModule.initialState` rejects anything but
/// exactly 2 players (`NEEDS_TWO_PLAYERS`), so Start stays disabled until
/// precisely two are in the room. A third join isn't blocked at the room
/// level (the generic 16-player room cap doesn't know about per-game
/// limits) — the host would just see that error if they tried to start with
/// one too many; a known, documented gap rather than a silent one.
class DraughtsLobbyScreen extends StatefulWidget {
  const DraughtsLobbyScreen({super.key});

  @override
  State<DraughtsLobbyScreen> createState() => _DraughtsLobbyScreenState();
}

class _DraughtsLobbyScreenState extends State<DraughtsLobbyScreen> {
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
    if (!_handedOff) {
      _socket?.close();
      // Never started from here — if we staked coins into it, refund them
      // rather than leaving them stuck in an abandoned lobby. Best-effort:
      // fires and forgets, since there's no UI left to show a failure to.
      final room = _room;
      if (room != null && room.stakeCoins > 0 && room.hostId == _selfId(_app)) {
        _app.api.delete('/rooms/${room.id}').catchError((_) {});
      }
    }
    super.dispose();
  }

  Future<void> _open() async {
    final app = AppScope.of(context);
    _app = app;
    if (app.identity == Identity.anonymous) {
      setState(() {
        _example = true;
        _room = _exampleRoom(app);
      });
      return;
    }
    int stake = 0;
    try {
      final wallet = await app.fetchWallet();
      if (!mounted) return;
      final picked = await showStakePicker(context, currentBalance: wallet.balance);
      if (!mounted) return;
      if (picked == null) {
        Navigator.of(context).pop(); // dismissed the picker — back out of the lobby entirely
        return;
      }
      stake = picked;
    } catch (_) {
      // Couldn't load a balance to stake against — fall through and just
      // host an unstaked room rather than blocking on it.
    }
    try {
      // House rules are settled before the first move rather than argued
      // about mid-game. Dismissing the sheet keeps the standard rules.
      final mandatoryCapture = await showDraughtsRulesSheet(context) ?? true;
      if (!mounted) return;
      final res = await app.api.post('/rooms', {
        'gameType': 'draughts',
        if (stake > 0) 'stake': stake,
        if (!mandatoryCapture) 'gameConfig': {'mandatoryCapture': false},
      }) as Map<String, dynamic>;
      if (!mounted) return;
      final room = RoomView.fromJson(res);
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
      switch (env['type']) {
        case 'SNAPSHOT':
          final p = (env['payload'] as Map).cast<String, dynamic>();
          if (p['lobby'] == true) _applyLobbySnapshot(p);
        case 'EVENT':
          final ep = (env['payload'] as Map).cast<String, dynamic>();
          if (ep['type'] == 'SPECTATOR_COUNT') {
            final data = ((ep['data'] as Map?) ?? const {}).cast<String, dynamic>();
            if (mounted) setState(() => _spectatorCount = data['count'] as int? ?? _spectatorCount);
          }
          // Anything else that happened in the room: re-ask for the roster.
          socket.send('HELLO', {'lastSeq': 0});
        case 'PHASE':
          _handOffToGame(app, roomId);
        case 'ERROR':
          final msg = (env['payload'] as Map)['message']?.toString();
          if (msg != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    });
    socket.send('HELLO', {'lastSeq': 0});
  }

  /// How many people are watching the room right now, straight off the
  /// lobby snapshot (and kept current by SPECTATOR_COUNT events).
  int _spectatorCount = 0;

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
        members: members,
        stakeCoins: _room?.stakeCoins ?? 0, // not carried on the WS snapshot — keep whatever the REST create/join response gave us
      );
      _spectatorCount = p['spectatorCount'] as int? ?? _spectatorCount;
      final me = _room!.members.where((m) => m.userId == _selfId(_app));
      if (me.isNotEmpty) _ready = me.first.ready;
    });
  }

  void _handOffToGame(AppState app, String roomId) {
    if (_handedOff || !mounted) return;
    _handedOff = true;
    _sub?.cancel();
    final room = _room!;
    final nicknames = {for (final m in room.members) m.userId: m.nickname ?? m.userId};
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => DraughtsGameScreen(socket: _socket!, selfId: _selfId(app), nicknames: nicknames),
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
    // Agents are saved per game, so this offers the ones already made and
    // only asks for a name when there are none — see showCyberAgentPicker.
    final choice = await showCyberAgentPicker(context, gameType: 'draughts');
    if (choice == null || !mounted) return;
    setState(() => _addingBot = true);
    try {
      final app = AppScope.of(context);
      if (choice.isExisting) {
        await app.api.post('/rooms/${room.id}/bots/existing/${choice.agentId}');
      } else {
        await app.api.post('/rooms/${room.id}/bots', {'name': choice.name, 'difficulty': choice.difficulty});
      }
      // the bot connects itself over WS right after this and shows up via
      // the lobby's own SNAPSHOT/EVENT stream — nothing else to do here.
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not add the Cyber Agent')));
    } finally {
      if (mounted) setState(() => _addingBot = false);
    }
  }

  RoomView _exampleRoom(AppState app) {
    final me = app.user?.displayName ?? 'You';
    return RoomView(
      id: 'example',
      code: 'DAME12',
      hostId: 'me',
      status: 'lobby',
      members: [
        RoomMember(userId: 'me', nickname: me, ready: _ready, connected: true),
        const RoomMember(userId: 'p2', nickname: 'Ronan', ready: true, connected: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final room = _room;
    final exact = room?.members.length == 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draft'),
        actions: [
          if (room != null)
            IconButton(
              tooltip: 'Copy code',
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: room.code));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied ${room.code}')));
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const MarqueeBar('10x10 · 20 pieces  •  flying kings  •  mandatory maximum capture'),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: TextStyle(color: n.danger))),
            if (room == null && _error == null) const Expanded(child: Center(child: CircularProgressIndicator())),
            if (room != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: NeonCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ROOM CODE', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, letterSpacing: 2)),
                    const SizedBox(height: 4),
                    Text(room.code,
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            fontSize: 40, letterSpacing: 6, shadows: [Shadow(color: n.gold.withValues(alpha: 0.4), blurRadius: 30)])),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      // Lights up only when somebody is actually watching.
                      WatchingEye(count: _spectatorCount),
                      _chip(n, '1v1'),
                      _chip(n, 'international rules'),
                      if (room.stakeCoins > 0) _chip(n, '🪙 ${room.stakeCoins} stake · ${room.stakeCoins * 2} pot'),
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
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, mainAxisSpacing: 18, crossAxisSpacing: 8, childAspectRatio: 0.76,
                  ),
                  itemCount: room.members.length,
                  itemBuilder: (context, i) => _memberTile(room.members[i], room.hostId),
                ),
              ),
              _bottomBar(room, exact),
            ],
          ],
        ),
      ),
    );
  }

  Widget _memberTile(RoomMember m, String hostId) {
    final n = context.neon;
    final isHost = m.userId == hostId || (m.userId == 'me' && _example);
    final away = !m.connected;
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
                    ? [BoxShadow(color: n.jade.withValues(alpha: 0.38), blurRadius: 16, spreadRadius: -2)]
                    : null,
              ),
              child: Opacity(opacity: away ? 0.4 : 1, child: Avatar(m.nickname ?? '?', size: 60)),
            ),
            if (isHost)
              Positioned(
                top: -3,
                left: -3,
                child: _badge(n, n.brand, const Icon(Icons.workspace_premium_rounded, size: 12, color: Colors.white)),
              ),
            if (m.isBot)
              Positioned(
                bottom: -2,
                right: -2,
                child: _badge(n, n.jade, const Icon(Icons.smart_toy_rounded, size: 13, color: Colors.black)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(m.nickname ?? m.userId,
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: away ? n.mute : n.ink, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(m.isBot ? 'CYBER AGENT' : (away ? 'AWAY' : (m.ready ? 'READY' : 'WAITING')),
            style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.8,
                color: away ? n.mute : (m.ready ? n.jade : n.mute))),
      ],
    );
  }

  Widget _badge(NeonColors n, Color bg, Widget icon) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: Border.all(color: n.panel, width: 2)),
        child: icon,
      );

  Widget _bottomBar(RoomView room, bool exact) {
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
          child: Text(
            exact ? '$readyCount of ${room.members.length} ready' : 'Waiting for exactly one opponent',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, fontWeight: FontWeight.w700),
          ),
        ),
        if (isHost && !exact && !_example) ...[
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: n.plate,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: n.line, width: 1.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.smart_toy_rounded, size: 14, color: _addingBot ? n.mute : n.gold),
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
        Row(children: [
          Expanded(
            child: NeonButton(
              _ready ? 'Ready ✓' : 'Ready up',
              style: NeonStyle.ghost,
              onPressed: () {
                final next = !_ready;
                setState(() => _ready = next);
                if (_example) {
                  setState(() => _room = _exampleRoom(app));
                } else {
                  _socket?.send('READY_SET', {'ready': next});
                }
              },
            ),
          ),
          if (isHost) ...[
            const SizedBox(width: 8),
            Expanded(
              child: NeonButton(
                'Start',
                onPressed: !exact
                    ? null
                    : () {
                        if (_example) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Guest games aren\'t connected to the live server yet — sign in with a phone to host a real game.')),
                          );
                        } else {
                          _socket?.send('GAME_START');
                        }
                      },
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _chip(NeonColors n, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(color: n.plate, borderRadius: BorderRadius.circular(NeonRadius.pill), border: Border.all(color: kCabinetInk, width: 1.6)),
        child: Text(t.toUpperCase(), style: TextStyle(color: n.mid, fontWeight: FontWeight.w800, fontSize: 8, letterSpacing: 0.6)),
      );
}


/// The house rules a Draughts host picks before the room exists. Returns the
/// chosen mandatory-capture setting, or null if the host backed out (which
/// the caller treats as "play it the standard way").
Future<bool?> showDraughtsRulesSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.neon.panel.withValues(alpha: 0.96),
    builder: (_) => const _DraughtsRulesSheet(),
  );
}

class _DraughtsRulesSheet extends StatefulWidget {
  const _DraughtsRulesSheet();

  @override
  State<_DraughtsRulesSheet> createState() => _DraughtsRulesSheetState();
}

class _DraughtsRulesSheetState extends State<_DraughtsRulesSheet> {
  // On is how international draughts is actually played, so that's the
  // default; off is the friendlier casual game.
  bool _mandatoryCapture = true;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HOUSE RULES', style: t.labelLarge?.copyWith(color: n.gold)),
          const SizedBox(height: 4),
          Text('Set before the game starts — everyone at the table plays by these.',
              style: t.bodySmall?.copyWith(color: n.mid)),
          const SizedBox(height: 16),
          NeonCard(
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Captures are compulsory', style: t.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      _mandatoryCapture
                          ? 'If you can take, you must — and you must take the most pieces available.'
                          : 'Taking is optional. A jump you start still has to be played out.',
                      style: t.labelSmall?.copyWith(color: n.mute, height: 1.3),
                    ),
                  ]),
                ),
                Switch(
                  value: _mandatoryCapture,
                  onChanged: (v) => setState(() => _mandatoryCapture = v),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 18),
          NeonButton('Start the room', onPressed: () => Navigator.of(context).pop(_mandatoryCapture)),
        ],
      ),
    );
  }
}
