import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:permission_handler/permission_handler.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/game_socket.dart';

/// One game-voice entry point for players and spectators in every game.
class GameVoiceControl extends StatefulWidget {
  const GameVoiceControl({
    super.key,
    required this.roomId,
    required this.socket,
    required this.selfId,
    this.nicknames = const {},
    this.spectating = false,
  });

  final String roomId;
  final GameSocket socket;
  final String selfId;
  final Map<String, String> nicknames;
  final bool spectating;

  @override
  State<GameVoiceControl> createState() => _GameVoiceControlState();
}

class _GameVoiceControlState extends State<GameVoiceControl> {
  StreamSubscription? _socketSub;
  livekit.Room? _room;
  bool _joining = false;
  bool _muted = false;
  bool _requesting = false;
  bool _approved = false;
  bool _serverMuted = false;
  final Set<String> _requests = {};
  final Set<String> _speakers = {};
  final Set<String> _mutedSpeakers = {};

  @override
  void initState() {
    super.initState();
    _socketSub = widget.socket.envelopes.listen(_onEnvelope);
  }

  @override
  void didUpdateWidget(covariant GameVoiceControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.socket != widget.socket) {
      _socketSub?.cancel();
      _socketSub = widget.socket.envelopes.listen(_onEnvelope);
    }
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    final room = _room;
    if (room != null) {
      room.disconnect();
      room.dispose();
    }
    super.dispose();
  }

  void _onEnvelope(Map<String, dynamic> envelope) {
    final payload = (envelope['payload'] as Map?)?.cast<String, dynamic>();
    if (payload == null) return;
    if (envelope['type'] == 'SNAPSHOT') {
      final requests = _ids(payload['spectatorVoiceRequests']);
      final speakers = _ids(payload['spectatorVoiceSpeakers']);
      final muted = _ids(payload['mutedSpectatorVoiceSpeakers']);
      if (!mounted) return;
      setState(() {
        _requests
          ..clear()
          ..addAll(requests);
        _speakers
          ..clear()
          ..addAll(speakers);
        _mutedSpeakers
          ..clear()
          ..addAll(muted);
        _requesting = requests.contains(widget.selfId);
        _approved = speakers.contains(widget.selfId);
        _serverMuted = muted.contains(widget.selfId);
      });
      return;
    }
    if (envelope['type'] == 'ERROR') {
      // A rejected SPECTATOR_VOICE_REQUEST (e.g. the game already ended, or
      // we're already approved) never reaches _speakers/_requests, so
      // without this the optimistic "waiting for a player" state set in
      // _requestToTalk would otherwise stick until the next full snapshot.
      const voiceRequestErrors = {
        'PLAYERS_ALREADY_ALLOWED',
        'NO_ACTIVE_GAME',
        'ALREADY_APPROVED',
      };
      if (_requesting && voiceRequestErrors.contains(payload['code'])) {
        setState(() => _requesting = false);
      }
      return;
    }
    if (envelope['type'] != 'EVENT') return;
    final type = payload['type']?.toString();
    final data = (payload['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final id = data['userId']?.toString();
    if (id == null || !mounted) return;
    switch (type) {
      case 'SPECTATOR_VOICE_REQUESTED':
        setState(() => _requests.add(id));
      case 'SPECTATOR_VOICE_APPROVED':
        setState(() {
          _requests.remove(id);
          _speakers.add(id);
          _mutedSpeakers.remove(id);
          if (id == widget.selfId) {
            _requesting = false;
            _approved = true;
            _serverMuted = false;
          }
        });
        if (id == widget.selfId) {
          _message('A player approved you for live talk');
          _connect();
        }
      case 'SPECTATOR_VOICE_DECLINED':
        setState(() {
          _requests.remove(id);
          if (id == widget.selfId) _requesting = false;
        });
        if (id == widget.selfId) _message('Your live-talk request was declined');
      case 'SPECTATOR_VOICE_MUTED':
        setState(() {
          _mutedSpeakers.add(id);
          if (id == widget.selfId) _serverMuted = true;
        });
        if (id == widget.selfId) _applyPlayerMute();
      case 'SPECTATOR_VOICE_UNMUTED':
        setState(() {
          _mutedSpeakers.remove(id);
          if (id == widget.selfId) _serverMuted = false;
        });
        if (id == widget.selfId) _message('A player unmuted your live-talk access');
      case 'SPECTATOR_VOICE_REMOVED':
        setState(() {
          _requests.remove(id);
          _speakers.remove(id);
          _mutedSpeakers.remove(id);
          if (id == widget.selfId) {
            _requesting = false;
            _approved = false;
            _serverMuted = false;
          }
        });
        if (id == widget.selfId) {
          _leave();
          _message('A player removed you from live talk');
        }
    }
  }

  Set<String> _ids(Object? raw) =>
      (raw as List? ?? const []).map((value) => value.toString()).toSet();

  String _name(String id) => widget.nicknames[id] ??
      (id.length > 6 ? id.substring(0, 6) : id);

  Future<bool> _enableMicrophone(livekit.Room room) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await room.localParticipant?.setMicrophoneEnabled(true);
        return room.localParticipant?.isMicrophoneEnabled() ?? false;
      } catch (error, stack) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        debugPrint('Game voice microphone failed: $error\n$stack');
      }
    }
    return false;
  }

  Future<void> _requestToTalk() async {
    if (_requesting) {
      _message('Your live-talk request is waiting for a player');
      return;
    }
    if (!widget.socket.isConnected) {
      _message('Reconnecting to the game. Try again in a moment.');
      return;
    }
    if (!(await Permission.microphone.request()).isGranted) {
      _message('Allow microphone access in iPhone Settings to request live talk');
      return;
    }
    if (!mounted) return;
    if (!widget.socket.isConnected) {
      _message('Reconnecting to the game. Try again in a moment.');
      return;
    }
    setState(() => _requesting = true);
    widget.socket.send('SPECTATOR_VOICE_REQUEST');
    _message('Live-talk request sent to the players');
  }

  Future<void> _connect() async {
    if (_room != null || _joining || (widget.spectating && (!_approved || _serverMuted))) {
      return;
    }
    setState(() => _joining = true);
    final api = AppScope.of(context).api;
    livekit.Room? joining;
    try {
      if (!(await Permission.microphone.request()).isGranted) {
        _message('Allow microphone access in iPhone Settings to use game voice');
        return;
      }
      final response = await api.post('/calls/games/${widget.roomId}/token')
          as Map<String, dynamic>;
      joining = livekit.Room();
      await joining.connect(
          response['livekitUrl'] as String, response['token'] as String);
      if (!mounted) return;
      if (widget.spectating) {
        await api.post('/calls/games/${widget.roomId}/activate');
        if (!mounted) return;
      }
      final connectedRoom = joining;
      _room = connectedRoom;
      joining = null;
      final microphoneOn = await _enableMicrophone(connectedRoom);
      if (!mounted) {
        await connectedRoom.disconnect();
        connectedRoom.dispose();
        return;
      }
      setState(() => _muted = !microphoneOn);
      if (!microphoneOn) {
        _message('Voice connected. Tap the microphone again to turn it on.');
      }
    } on ApiException catch (error) {
      _message('Game voice: ${error.message}');
    } catch (error, stack) {
      debugPrint('Game voice connection failed: $error\n$stack');
      _message('Could not connect game voice. Check your connection and try again.');
    } finally {
      if (joining != null) {
        await joining.disconnect();
        joining.dispose();
      }
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _toggleMicrophone() async {
    if (_serverMuted) {
      _message('A player has muted your live-talk microphone');
      return;
    }
    final room = _room;
    if (room == null) return _connect();
    try {
      await room.localParticipant?.setMicrophoneEnabled(_muted);
      if (mounted) setState(() => _muted = !_muted);
    } catch (_) {
      _message('Could not change microphone state');
    }
  }

  Future<void> _applyPlayerMute() async {
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(false);
    } finally {
      if (mounted) setState(() => _muted = true);
    }
  }

  Future<void> _leave() async {
    final room = _room;
    if (room == null) return;
    if (mounted) setState(() => _room = null);
    await room.disconnect();
    room.dispose();
  }

  void _sendControl(String type, String userId) {
    widget.socket.send(type, {'userId': userId});
    Navigator.of(context).pop();
  }

  Future<void> _openPanel() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: ListView(shrinkWrap: true, children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.graphic_eq_rounded),
              title: Text('Live talk'),
            ),
            if (widget.spectating)
              _spectatorActions(sheetContext)
            else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_room == null
                    ? Icons.mic_none_rounded
                    : _muted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded),
                title: Text(_room == null
                    ? 'Join game voice'
                    : _muted
                        ? 'Unmute microphone'
                        : 'Mute microphone'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _toggleMicrophone();
                },
              ),
              if (_room != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.call_end_rounded),
                  title: const Text('Leave game voice'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _leave();
                  },
                ),
              if (_requests.isNotEmpty) ...[
                const Divider(),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('REQUESTS',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
                for (final id in _requests)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_add_alt_1_rounded),
                    title: Text(_name(id)),
                    trailing: Wrap(spacing: 4, children: [
                      IconButton(
                        tooltip: 'Decline',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => _sendControl('SPECTATOR_VOICE_DECLINE', id),
                      ),
                      IconButton.filled(
                        tooltip: 'Approve',
                        icon: const Icon(Icons.check_rounded),
                        onPressed: () => _sendControl('SPECTATOR_VOICE_APPROVE', id),
                      ),
                    ]),
                  ),
              ],
              if (_speakers.isNotEmpty) ...[
                const Divider(),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('LIVE SPECTATORS',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
                for (final id in _speakers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_mutedSpeakers.contains(id)
                        ? Icons.mic_off_rounded
                        : Icons.record_voice_over_rounded),
                    title: Text(_name(id)),
                    trailing: Wrap(spacing: 4, children: [
                      IconButton(
                        tooltip: _mutedSpeakers.contains(id) ? 'Unmute' : 'Mute',
                        icon: Icon(_mutedSpeakers.contains(id)
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded),
                        onPressed: () =>
                            _sendControl('SPECTATOR_VOICE_MUTE_TOGGLE', id),
                      ),
                      IconButton(
                        tooltip: 'Remove from live talk',
                        icon: const Icon(Icons.person_remove_alt_1_rounded),
                        onPressed: () => _sendControl('SPECTATOR_VOICE_REMOVE', id),
                      ),
                    ]),
                  ),
              ],
            ],
          ]),
        ),
      ),
    );
  }

  Widget _spectatorActions(BuildContext sheetContext) {
    if (!_approved) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(_requesting
            ? Icons.hourglass_top_rounded
            : Icons.record_voice_over_rounded),
        title: Text(_requesting ? 'Waiting for a player' : 'Request to join live talk'),
        onTap: _requesting
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                _requestToTalk();
              },
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(_serverMuted || _muted
            ? Icons.mic_off_rounded
            : Icons.mic_rounded),
        title: Text(_serverMuted
            ? 'Muted by a player'
            : _room == null
                ? 'Join live talk'
                : _muted
                    ? 'Unmute microphone'
                    : 'Mute microphone'),
        onTap: _serverMuted
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                _toggleMicrophone();
              },
      ),
      if (_room != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.call_end_rounded),
          title: const Text('Leave live talk'),
          onTap: () {
            Navigator.of(sheetContext).pop();
            _leave();
          },
        ),
    ]);
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRequests = !widget.spectating && _requests.isNotEmpty;
    final active = _room != null || _approved || _requesting;
    return IconButton(
      tooltip: widget.spectating ? 'Live talk' : 'Game voice and live speakers',
      onPressed: _joining ? null : _openPanel,
      icon: Stack(clipBehavior: Clip.none, children: [
        Icon(_serverMuted || (_room != null && _muted)
            ? Icons.mic_off_rounded
            : active
                ? Icons.mic_rounded
                : Icons.mic_none_rounded),
        if (hasRequests)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                shape: BoxShape.circle,
                border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
              ),
            ),
          ),
      ]),
    );
  }
}
