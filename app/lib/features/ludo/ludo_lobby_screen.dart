import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/game_socket.dart';
import '../../core/models.dart';
import '../../widgets/pending_huud.dart';
import '../../widgets/cancel_huud_button.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/cyber_agent_sheet.dart';
import '../../widgets/copyable_huud_code.dart';
import '../../widgets/invite_players_sheet.dart';
import '../../widgets/neon.dart';
import 'ludo_game_screen.dart';

Future<int?> showLudoPieceCountDialog(BuildContext context,
    {int initialValue = 8}) {
  var chosen = initialValue;
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Two-player Ludo'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Choose pieces per player. Opponents use diagonal corners.'),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 4, label: Text('4 pieces')),
              ButtonSegment(value: 8, label: Text('8 pieces')),
            ],
            selected: {chosen},
            onSelectionChanged: (value) =>
                setDialogState(() => chosen = value.first),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, chosen),
              child: const Text('Start')),
        ],
      ),
    ),
  );
}

class LudoLobbyScreen extends StatefulWidget {
  const LudoLobbyScreen({super.key});

  @override
  State<LudoLobbyScreen> createState() => _LudoLobbyScreenState();
}

class _LudoLobbyScreenState extends State<LudoLobbyScreen> {
  RoomView? _room;
  GameSocket? _socket;
  StreamSubscription? _subscription;
  int _turnSeconds = 60;
  int _twoPlayerPieces = 8;
  bool _busy = false, _connected = false, _handedOff = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = AppScope.of(context);
      try {
        await resumePendingHuud(context, app, 'ludo');
      } catch (_) {
        if (mounted)
          setState(
              () => _error = 'Could not check your waiting Huud. Try again.');
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (!_handedOff) _socket?.close();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final app = AppScope.of(context);
      if (await resumePendingHuud(context, app, 'ludo')) return;
      if (!mounted) return;
      final raw = await app.api.post('/rooms', {
        'gameType': 'ludo',
        'gameConfig': {'turnSeconds': _turnSeconds},
      });
      if (!mounted) return;
      _room = RoomView.fromJson((raw as Map).cast<String, dynamic>());
      await app.rememberActiveRoom(_room!.id);
      if (mounted) {
        setState(() {});
        _connect();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open the huud. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _connect() {
    _subscription?.cancel();
    _socket?.close();
    final socket = GameSocket.connect(AppScope.of(context).api, _room!.id);
    _socket = socket;
    _subscription = socket.envelopes.listen((env) {
      if (!mounted) return;
      if (handleCancelledHuud(context, env, _room!.id)) return;
      if (!mounted || _handedOff) return;
      final payload = (env['payload'] as Map? ?? {}).cast<String, dynamic>();
      switch (env['type']) {
        case 'SNAPSHOT':
          if (payload['lobby'] == false) {
            _openGame();
            return;
          }
          setState(() {
            _connected = true;
            _room = RoomView(
              id: _room!.id,
              code: _room!.code,
              hostId: payload['hostId'] as String? ?? _room!.hostId,
              status: payload['status'] as String? ?? 'lobby',
              gameType: 'ludo',
              members: (payload['members'] as List? ?? [])
                  .map((m) =>
                      RoomMember.fromJson((m as Map).cast<String, dynamic>()))
                  .toList(),
            );
          });
        case 'PHASE':
          _openGame();
        case 'EVENT':
          socket.send('HELLO', {'lastSeq': 0});
        case 'ERROR':
          setState(() => _error = payload['message']?.toString());
        case 'CONNECTION':
          setState(() => _connected = payload['connected'] == true);
      }
    });
    socket.send('HELLO', {'lastSeq': 0});
  }

  void _openGame() {
    if (_handedOff || _room == null) return;
    _handedOff = true;
    _subscription?.cancel();
    final room = _room!;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LudoGameScreen(
        socket: _socket!,
        selfId: AppScope.of(context).user!.id,
        roomCode: room.code,
        nicknames: {
          for (final m in room.members) m.userId: m.nickname ?? m.userId
        },
        agents: {
          for (final m in room.members)
            if (m.isBot) m.userId
        },
      ),
    ));
  }

  Future<void> _addAgent() async {
    final room = _room;
    if (room == null) return;
    final choice = await showCyberAgentPicker(context,
        defaultName: 'Cyber ${room.members.where((m) => m.isBot).length + 1}');
    // Re-read _room rather than trusting the pre-await snapshot — the room
    // could have ended, or been replaced by a different one, while the
    // picker sheet was open.
    final current = _room;
    if (choice == null ||
        !mounted ||
        current == null ||
        current.id != room.id) {
      return;
    }
    setState(() => _busy = true);
    try {
      final api = AppScope.of(context).api;
      await api.post('/rooms/${current.id}/bots',
          {'name': choice.name, 'difficulty': choice.difficulty});
      _socket?.send('HELLO', {'lastSeq': 0});
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startGame(int count) async {
    if (count != 2) {
      _socket?.send('GAME_START');
      return;
    }
    final selection =
        await showLudoPieceCountDialog(context, initialValue: _twoPlayerPieces);
    if (selection == null || !mounted) return;
    _twoPlayerPieces = selection;
    _socket?.send('GAME_START', {'twoPlayerPieces': selection});
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    return Scaffold(
      appBar: AppBar(actions: [
        if (_room != null) CancelHuudButton(room: _room!)
      ], title: Text(room == null ? 'Ludo · Open a huud' : 'Ludo · Your huud')),
      body: SafeArea(child: room == null ? _setup() : _lobby(room)),
    );
  }

  Widget _setup() => Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Ludo', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('2–4 players · two dice · move one or two pieces'),
          const SizedBox(height: 20),
          DropdownButtonFormField<int>(
            initialValue: _turnSeconds,
            decoration: const InputDecoration(labelText: 'Turn time'),
            items: const [30, 60, 90, 120]
                .map((s) =>
                    DropdownMenuItem(value: s, child: Text('$s seconds')))
                .toList(),
            onChanged: (value) => setState(() => _turnSeconds = value ?? 60),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child:
                  Text(_error!, style: TextStyle(color: context.neon.danger)),
            ),
          const Spacer(),
          NeonButton(_busy ? 'Opening huud…' : 'Open a huud',
              onPressed: _busy ? null : _create),
        ]),
      );

  Widget _lobby(RoomView room) {
    final self = AppScope.of(context).user?.id;
    final me = room.members.where((m) => m.userId == self).firstOrNull;
    final count = room.members.length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (_error != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_error!, style: TextStyle(color: context.neon.danger))),
      NeonCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('INVITE CODE'),
        Row(children: [
          Expanded(
              child: CopyableHuudCode(
            code: room.code,
            child: Text(room.code,
                style: Theme.of(context).textTheme.headlineLarge),
          )),
          IconButton(
              tooltip: 'Copy huud code',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: room.code))),
        ]),
        Text('$count of 4 seats'),
      ])),
      const SizedBox(height: 12),
      for (final m in room.members)
        ListTile(
          dense: true,
          leading: CircleAvatar(
              child: Text(m.isBot
                  ? 'AI'
                  : (m.nickname?.isNotEmpty == true ? m.nickname![0] : '?'))),
          title: Text(m.nickname ?? m.userId),
          subtitle: Text(m.userId == room.hostId
              ? 'Host'
              : m.isBot
                  ? 'Cyber Agent'
                  : 'Player'),
          trailing: Text(m.ready ? 'Ready' : 'Waiting'),
        ),
      const SizedBox(height: 14),
      if (!_connected) NeonButton('Reconnect', onPressed: _connect),
      if (_connected) ...[
        if (count < 4) ...[
          NeonButton('Invite friends',
              style: NeonStyle.ghost,
              onPressed: () =>
                  showInvitePlayersSheet(context, roomId: room.id)),
          const SizedBox(height: 8),
          NeonButton(_busy ? 'Adding Cyber Agent…' : 'Add Cyber Agent',
              style: NeonStyle.ghost, onPressed: _busy ? null : _addAgent),
          const SizedBox(height: 8),
        ],
        NeonButton(me?.ready == true ? 'Ready' : 'Ready up',
            style: NeonStyle.ghost,
            onPressed: () =>
                _socket!.send('READY_SET', {'ready': !(me?.ready ?? false)})),
        if (room.hostId == self) ...[
          const SizedBox(height: 8),
          NeonButton('Start game',
              onPressed: count >= 2 ? () => _startGame(count) : null),
        ],
        if (count < 2)
          const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Invite one more player or add a Cyber Agent.')),
      ],
    ]);
  }
}
