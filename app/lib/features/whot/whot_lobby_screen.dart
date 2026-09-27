import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_state.dart';
import '../../core/api_client.dart';
import '../../core/game_socket.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/invite_players_sheet.dart';
import '../../widgets/cyber_agent_sheet.dart';
import '../../widgets/neon.dart';
import 'whot_game_screen.dart';

class WhotLobbyScreen extends StatefulWidget {
  const WhotLobbyScreen({super.key});
  @override
  State<WhotLobbyScreen> createState() => _WhotLobbyScreenState();
}

class _WhotLobbyScreenState extends State<WhotLobbyScreen> {
  RoomView? _room;
  GameSocket? _socket;
  StreamSubscription? _sub;
  bool _busy = false,
      _handedOff = false,
      _connected = false,
      _addingBot = false;
  String? _error;
  int _hand = 5, _seconds = 60;
  final _rules = <String, bool>{
    'includeWhot': true,
    'pickTwo': true,
    'pickTwoStacking': true,
    'generalMarket': true,
    'holdOn': true,
    'suspension': true
  };
  static const _labels = {
    'includeWhot': '20 · Whot wild cards',
    'pickTwo': '2 · Pick two',
    'pickTwoStacking': 'Stack twos',
    'generalMarket': '14 · Market',
    'holdOn': '1 · Hold on',
    'suspension': '8 · Skip'
  };

  @override
  void dispose() {
    _sub?.cancel();
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
      final raw = await app.api.post('/rooms', {
        'gameType': 'whot',
        'gameConfig': {
          'startingHand': _hand,
          'turnSeconds': _seconds,
          ..._rules
        }
      });
      if (!mounted) return;
      setState(() =>
          _room = RoomView.fromJson((raw as Map).cast<String, dynamic>()));
      _connect();
    } on ApiException catch (e) {
      _showCreateError(e.message);
    } catch (_) {
      _showCreateError(
          'Could not connect. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showCreateError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _connect() {
    _sub?.cancel();
    _socket?.close();
    final app = AppScope.of(context);
    final socket = GameSocket.connect(app.api, _room!.id);
    _socket = socket;
    _sub = socket.envelopes.listen((env) {
      if (!mounted || _handedOff) return;
      final p = (env['payload'] as Map? ?? {}).cast<String, dynamic>();
      if (env['type'] == 'SNAPSHOT') {
        if (p['lobby'] == false) {
          _openGame();
          return;
        }
        setState(() {
          _connected = true;
          _error = null;
          _room = RoomView(
              id: _room!.id,
              code: _room!.code,
              hostId: p['hostId'] as String? ?? _room!.hostId,
              status: p['status'] as String? ?? 'lobby',
              gameType: 'whot',
              members: (p['members'] as List? ?? [])
                  .map((m) =>
                      RoomMember.fromJson((m as Map).cast<String, dynamic>()))
                  .toList());
        });
      } else if (env['type'] == 'PHASE') {
        _openGame();
      } else if (env['type'] == 'EVENT') {
        socket.send('HELLO', {'lastSeq': 0});
      } else if (env['type'] == 'ERROR') {
        setState(() => _error =
            p['message']?.toString() ?? 'Could not complete that action');
      }
    }, onDone: () {
      if (mounted && !_handedOff) {
        setState(() {
          _connected = false;
          _error = 'Connection lost. Reconnect to the room.';
        });
      }
    });
    socket.send('HELLO', {'lastSeq': 0});
  }

  void _openGame() {
    if (_handedOff) return;
    _handedOff = true;
    _sub?.cancel();
    final room = _room!;
    final selfId = AppScope.of(context).user!.id;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => WhotGameScreen(
              socket: _socket!,
              roomId: room.id,
              roomCode: room.code,
              selfId: selfId,
              nicknames: {
                for (final m in room.members) m.userId: m.nickname ?? m.userId
              },
              avatars: {
                for (final m in room.members)
                  if (m.avatarUrl?.isNotEmpty == true)
                    m.userId: m.avatarUrl!
                  else if (m.isBot)
                    m.userId: '🤖'
              },
            )));
  }

  Future<void> _addBot() async {
    final choice = await showCyberAgentPicker(context, gameType: 'whot');
    if (choice == null || !mounted || _room == null) return;
    setState(() => _addingBot = true);
    try {
      final app = AppScope.of(context);
      if (choice.isExisting) {
        await app.api
            .post('/rooms/${_room!.id}/bots/existing/${choice.agentId}');
      } else {
        await app.api.post('/rooms/${_room!.id}/bots', {
          'name': choice.name,
          'difficulty': choice.difficulty,
        });
      }
      _socket?.send('HELLO', {'lastSeq': 0});
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not add the Cyber Agent')));
      }
    } finally {
      if (mounted) setState(() => _addingBot = false);
    }
  }

  Widget _compactSelector({
    required String label,
    required int value,
    required List<int> values,
    required String Function(int) display,
    required ValueChanged<int>? onChanged,
  }) =>
      Container(
        height: 48,
        padding: const EdgeInsets.fromLTRB(9, 3, 5, 2),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: .2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: .65), fontSize: 9)),
          Expanded(
              child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                      value: value,
                      isExpanded: true,
                      isDense: true,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      items: [
                        for (final option in values)
                          DropdownMenuItem(
                              value: option, child: Text(display(option)))
                      ],
                      onChanged: onChanged == null
                          ? null
                          : (next) {
                              if (next != null) onChanged(next);
                            }))),
        ]),
      );

  Widget _ruleToggle(String rule, double width) {
    final selected = _rules[rule]!;
    return SizedBox(
      width: width,
      height: 30,
      child: Material(
        color: selected
            ? context.neon.brand.withValues(alpha: .22)
            : Colors.white.withValues(alpha: .035),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: BorderSide(
                color: selected
                    ? context.neon.brand
                    : Colors.white.withValues(alpha: .1))),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: _busy ? null : () => setState(() => _rules[rule] = !selected),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Row(children: [
              Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                  size: 13,
                  color: selected
                      ? context.neon.brand
                      : Colors.white.withValues(alpha: .45)),
              const SizedBox(width: 5),
              Expanded(
                  child: Text(_labels[rule]!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9.5))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _initialSettings(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Create a Whot table',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          const Text('2–20 players · Choose the rules and create your room.',
              style: TextStyle(fontSize: 12)),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(_error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: context.neon.danger, fontSize: 11))),
          const SizedBox(height: 9),
          Row(children: [
            Expanded(
                child: _compactSelector(
                    label: 'CARDS EACH',
                    value: _hand,
                    values: [for (var i = 3; i <= 12; i++) i],
                    display: (value) => '$value cards',
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _hand = value))),
            const SizedBox(width: 8),
            Expanded(
                child: _compactSelector(
                    label: 'TURN TIME',
                    value: _seconds,
                    values: const [60, 90],
                    display: (value) => '$value sec',
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _seconds = value))),
          ]),
          const SizedBox(height: 8),
          Material(
            color: Colors.white.withValues(alpha: .05),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.white.withValues(alpha: .12))),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 3, 10, 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity:
                            const VisualDensity(horizontal: -3, vertical: -3),
                        title: const Text('Include Whot cards',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: const Text(
                            'Wild 20 cards can call a new shape',
                            style: TextStyle(fontSize: 10)),
                        value: _rules['includeWhot']!,
                        onChanged: _busy
                            ? null
                            : (value) =>
                                setState(() => _rules['includeWhot'] = value)),
                    const Divider(height: 8),
                    const Text('SPECIAL CARD RULES',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1)),
                    const SizedBox(height: 5),
                    LayoutBuilder(builder: (context, constraints) {
                      final width = (constraints.maxWidth - 6) / 2;
                      return Wrap(spacing: 6, runSpacing: 5, children: [
                        for (final rule
                            in _rules.keys.where((key) => key != 'includeWhot'))
                          _ruleToggle(rule, width),
                      ]);
                    }),
                  ]),
            ),
          ),
          const Spacer(),
          NeonButton(_busy ? 'Creating room…' : 'Create room',
              onPressed: _busy ? null : _create),
        ]),
      );

  Widget _roomLobby(BuildContext context, RoomView room) {
    final self = AppScope.of(context).user?.id;
    final me = room.members.where((m) => m.userId == self).firstOrNull;
    final count = room.members.length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (_error != null) ...[
        Text(_error!, style: TextStyle(color: context.neon.danger)),
        const SizedBox(height: 10),
      ],
      NeonCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('INVITE CODE'),
        Row(children: [
          Expanded(
              child: Text(room.code,
                  style: Theme.of(context).textTheme.headlineLarge)),
          IconButton(
              tooltip: 'Copy room code',
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: room.code));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Room code copied')));
                }
              })
        ]),
        Text(
            '$count of 20 seats · ${room.members.where((m) => m.ready).length} ready'),
      ])),
      const SizedBox(height: 12),
      for (final member in room.members)
        ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Avatar(member.nickname ?? '?',
                size: 36,
                emoji: member.avatarUrl?.startsWith('http') == true
                    ? null
                    : (member.avatarUrl?.isNotEmpty == true
                        ? member.avatarUrl
                        : member.isBot
                            ? '🤖'
                            : null),
                imageUrl: member.avatarUrl?.startsWith('http') == true
                    ? member.avatarUrl
                    : null),
            title: Text(member.nickname ?? member.userId),
            subtitle: Text(member.userId == room.hostId ? 'Host' : 'Player'),
            trailing: Text(!member.connected
                ? 'Away'
                : member.ready
                    ? 'Ready ✓'
                    : 'Waiting')),
      const SizedBox(height: 12),
      if (!_connected) NeonButton('Reconnect', onPressed: _connect),
      if (_connected) ...[
        if (count < 20)
          NeonButton('Invite friends',
              style: NeonStyle.ghost,
              onPressed: () =>
                  showInvitePlayersSheet(context, roomId: room.id)),
        if (count < 20) ...[
          const SizedBox(height: 8),
          NeonButton(_addingBot ? 'Adding Cyber Agent…' : 'Add Cyber Agent',
              style: NeonStyle.ghost, onPressed: _addingBot ? null : _addBot),
        ],
        const SizedBox(height: 8),
        NeonButton(me?.ready == true ? 'Ready ✓' : 'Ready up',
            style: NeonStyle.ghost,
            onPressed: () =>
                _socket!.send('READY_SET', {'ready': !(me?.ready ?? false)})),
        const SizedBox(height: 8),
        if (room.hostId == self)
          NeonButton('Start game',
              onPressed: count >= 2 && count <= 20
                  ? () => _socket!.send('GAME_START')
                  : null),
        if (count < 2)
          const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Invite at least one more player to start.')),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    return Scaffold(
      appBar: AppBar(
          title:
              Text(room == null ? 'Whot · Create room' : 'Whot · Your room')),
      body: SafeArea(
          child: room == null
              ? _initialSettings(context)
              : _roomLobby(context, room)),
    );
  }
}
