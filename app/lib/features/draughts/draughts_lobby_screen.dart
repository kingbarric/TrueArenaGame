import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/game_socket.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/cyber_agent_sheet.dart';
import '../../widgets/copyable_huud_code.dart';
import '../../widgets/invite_players_sheet.dart';
import '../../widgets/neon.dart';
import '../../widgets/watching_eye.dart';
import '../../widgets/stake_picker_sheet.dart';
import 'draughts_game_screen.dart';

/// The room before a Draughts game starts. Same shape as
/// `WordBluffLobbyScreen`/`LobbyScreen`, but Draughts is exactly 1v1 rather
/// than "at least N" — `DraughtsModule.initialState` rejects anything but
/// exactly 2 players (`NEEDS_TWO_PLAYERS`). The Start action explains that
/// requirement when the host taps it with an incomplete or oversized roster.
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
      // An unstarted room must be removed even when it is unstaked. Otherwise
      // its Cyber Agent remains attached to an active room and cannot be reused.
      final room = _room;
      if (room != null && room.hostId == _selfId(_app)) {
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
      final picked =
          await showStakePicker(context, currentBalance: wallet.balance);
      if (!mounted) return;
      if (picked == null) {
        Navigator.of(context)
            .pop(); // dismissed the picker — back out of the lobby entirely
        return;
      }
      stake = picked;
    } catch (_) {
      // Couldn't load a balance to stake against — fall through and just
      // host an unstaked room rather than blocking on it.
    }
    try {
      // Ranked/casual and house rules are settled before the first move.
      // Dismissing the sheet means a casual game with optional captures.
      final setup = await showDraughtsRulesSheet(context,
              canRank: app.identity == Identity.account) ??
          const DraughtsMatchSetup();
      if (!mounted) return;
      final res = await app.api.post('/rooms', {
        'gameType': 'draughts',
        if (stake > 0) 'stake': stake,
        if (setup.ranked) 'ranked': true,
        'gameConfig': {'mandatoryCapture': setup.mandatoryCapture},
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
            final data =
                ((ep['data'] as Map?) ?? const {}).cast<String, dynamic>();
            if (mounted)
              setState(() =>
                  _spectatorCount = data['count'] as int? ?? _spectatorCount);
          }
          // Anything else that happened in the room: re-ask for the roster.
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
        stakeCoins: _room?.stakeCoins ??
            0, // not carried on the WS snapshot — keep whatever the REST create/join response gave us
        ranked: _room?.ranked ?? false, // likewise REST-only
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
    final nicknames = {
      for (final m in room.members) m.userId: m.nickname ?? m.userId
    };
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => DraughtsGameScreen(
          socket: _socket!, selfId: _selfId(app), nicknames: nicknames),
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

  void _start(RoomView room) {
    final count = room.members.length;
    if (count != 2) {
      final message = count < 2
          ? 'Draughts needs one opponent. Add a player or a Cyber Agent before starting.'
          : 'Draughts is one on one. Remove the extra players before starting.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (_example) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an account to host a game.')),
      );
      return;
    }
    if (_socket == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Still connecting to the huud. Try again.')),
      );
      return;
    }
    _socket!.send('GAME_START');
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
        const RoomMember(
            userId: 'p2', nickname: 'Ronan', ready: true, connected: true),
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
        title: const Text('Draughts'),
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
                '10x10 · 20 pieces  •  flying kings  •  choose your capture rule'),
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
                        Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // Lights up only when somebody is actually watching.
                              WatchingEye(count: _spectatorCount),
                              _chip(n, '1v1'),
                              _chip(n, 'international rules'),
                              if (room.stakeCoins > 0)
                                _chip(n,
                                    '🪙 ${room.stakeCoins} stake · ${room.stakeCoins * 2} pot'),
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
                      size: 60, online: m.isBot || m.connected)),
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
            if (m.isBot)
              Positioned(
                bottom: -2,
                right: -2,
                child: _badge(
                    n,
                    n.jade,
                    const Icon(Icons.smart_toy_rounded,
                        size: 13, color: Colors.black)),
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
                : (away ? 'AWAY' : (m.ready ? 'READY' : 'WAITING')),
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

  Widget _bottomBar(RoomView room, bool exact) {
    final n = context.neon;
    final app = AppScope.of(context);
    final isHost = _example || room.hostId == app.user?.id;
    final readyCount = room.members.where((m) => m.ready).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
          color: n.panel, border: Border(top: BorderSide(color: n.line))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            exact
                ? '$readyCount of ${room.members.length} ready'
                : 'Waiting for exactly one opponent',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: n.mute, fontWeight: FontWeight.w700),
          ),
        ),
        if (isHost && !exact && !_example) ...[
          // Inviting a real friend is the headline action; an agent is the
          // fallback when nobody's around, so it sits underneath as a small
          // pill rather than competing as a full-width button.
          NeonButton('Add a player',
              style: NeonStyle.ghost, onPressed: () => _invitePlayers(room)),
          const SizedBox(height: 8),
          Center(
            child: Bouncy(
              feel: BouncyFeel.snap,
              onTap: _addingBot ? null : () => _addBot(room),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: n.jade.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: n.jade.withValues(alpha: 0.75), width: 1.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.smart_toy_rounded,
                      size: 14, color: _addingBot ? n.mute : n.jade),
                  const SizedBox(width: 6),
                  Text(_addingBot ? 'Adding…' : 'or add a Cyber Agent',
                      style: TextStyle(
                          color: _addingBot ? n.mute : n.jade,
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
              style: NeonStyle.gold,
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
                onPressed: () => _start(room),
              ),
            ),
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

/// The house rules a Draughts host picks before the room exists. Returns the
/// chosen mandatory-capture setting, or null if the host backed out (which
/// the caller treats as optional captures).
/// What the host chose before opening the room.
class DraughtsMatchSetup {
  const DraughtsMatchSetup(
      {this.ranked = false, this.mandatoryCapture = false});

  final bool ranked;
  final bool mandatoryCapture;
}

/// `canRank` is false for guests — a rated game needs a verified account on
/// both sides, so the option isn't offered rather than silently ignored.
Future<DraughtsMatchSetup?> showDraughtsRulesSheet(BuildContext context,
    {bool canRank = false}) {
  return showModalBottomSheet<DraughtsMatchSetup>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.neon.panel.withValues(alpha: 0.96),
    builder: (_) => _DraughtsRulesSheet(canRank: canRank),
  );
}

class _DraughtsRulesSheet extends StatefulWidget {
  const _DraughtsRulesSheet({required this.canRank});

  final bool canRank;

  @override
  State<_DraughtsRulesSheet> createState() => _DraughtsRulesSheetState();
}

class _DraughtsRulesSheetState extends State<_DraughtsRulesSheet> {
  bool _ranked = false;
  bool _mandatoryCapture = false;

  /// Every rated game is played under the same, official rules — a rating
  /// earned with optional captures wouldn't mean the same thing.
  bool get _capturesCompulsory => _ranked || _mandatoryCapture;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = Theme.of(context).textTheme;
    // Scrolls so the Start button stays reachable on short phones now that
    // the sheet carries the ranked choice as well as the house rules.
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.canRank) ...[
              Text('MATCH TYPE', style: t.labelLarge?.copyWith(color: n.gold)),
              const SizedBox(height: 10),
              NeonCard(
                accent: _ranked ? n.gold : null,
                child: Row(children: [
                  Icon(Icons.military_tech_rounded,
                      color: _ranked ? n.gold : n.mute, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ranked',
                              style: t.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(
                            _ranked
                                ? 'Counts toward your Draughts rating and rankings. Official rules.'
                                : 'Casual — just for fun, no rating change.',
                            style: t.labelSmall
                                ?.copyWith(color: n.mute, height: 1.3),
                          ),
                        ]),
                  ),
                  Switch(
                    value: _ranked,
                    onChanged: (v) => setState(() => _ranked = v),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
            ],
            Text('HOUSE RULES', style: t.labelLarge?.copyWith(color: n.gold)),
            const SizedBox(height: 4),
            Text(
                _ranked
                    ? 'Ranked games always use official rules.'
                    : 'Set before the game starts — everyone at the table plays by these.',
                style: t.bodySmall?.copyWith(color: n.mid)),
            const SizedBox(height: 16),
            NeonCard(
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Captures are compulsory', style: t.bodyMedium),
                          const SizedBox(height: 2),
                          Text(
                            _capturesCompulsory
                                ? 'If you can take, you must — and you must take the most pieces available.'
                                : 'Taking is optional. A jump you start still has to be played out.',
                            style: t.labelSmall
                                ?.copyWith(color: n.mute, height: 1.3),
                          ),
                        ]),
                  ),
                  Switch(
                    value: _capturesCompulsory,
                    onChanged: _ranked
                        ? null
                        : (v) => setState(() => _mandatoryCapture = v),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 18),
            NeonButton(_ranked ? 'Start ranked huud' : 'Start the huud',
                onPressed: () => Navigator.of(context).pop(DraughtsMatchSetup(
                    ranked: _ranked, mandatoryCapture: _capturesCompulsory))),
          ],
        ),
      ),
    );
  }
}
