import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:permission_handler/permission_handler.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/hangout_state.dart';
import '../features/calls/call_screen.dart';
import 'neon.dart';
import '../core/game_socket.dart';
import '../theme/neon_theme.dart';

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
  livekit.Room? get _room => HangoutState.instance.room;
  bool _joining = false;
  bool get _muted => HangoutState.instance.muted;
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
    HangoutState.instance.addListener(_voiceChanged);
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
    HangoutState.instance.removeListener(_voiceChanged);
    super.dispose();
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
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
        if (id == widget.selfId)
          _message('Your live-talk request was declined');
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
        if (id == widget.selfId)
          _message('A player unmuted your live-talk access');
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
          _applyPlayerMute();
          _message('A player removed your live-talk speaking permission');
        }
    }
  }

  Set<String> _ids(Object? raw) =>
      (raw as List? ?? const []).map((value) => value.toString()).toSet();

  String _name(String id) =>
      widget.nicknames[id] ?? (id.length > 6 ? id.substring(0, 6) : id);

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
      _message(
          'Allow microphone access in iPhone Settings to request live talk');
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
    if (_joining || (widget.spectating && (!_approved || _serverMuted))) return;
    if (HangoutState.instance.active) {
      // A Huud's voice has no call screen — the button is just the mic.
      if (HangoutState.instance.onOpen != null) {
        await HangoutState.instance.toggleMute?.call();
      } else {
        HangoutState.instance.show();
      }
      return;
    }
    setState(() => _joining = true);
    final api = AppScope.of(context).api;
    try {
      final path = '/calls/games/${widget.roomId}/token';
      final response = await api.post(path) as Map<String, dynamic>;
      if (!mounted) return;
      final opened = await CallScreen.open(
          context,
          CallScreen(
            roomName: response['roomName'] as String,
            token: response['token'] as String,
            livekitUrl: response['livekitUrl'] as String,
            title: 'Huud hangout',
            onConnected: widget.spectating
                ? () async {
                    await api.post('/calls/games/${widget.roomId}/activate');
                  }
                : null,
            refreshToken: () async =>
                ((await api.post('/calls/rooms/${response['roomName']}/token')
                    as Map<String, dynamic>)['token'] as String),
          ));
      if (opened) HangoutState.instance.minimize();
    } on ApiException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('Could not connect voice. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _toggleMicrophone() async {
    if (_serverMuted) {
      _message('A player has muted your live-talk microphone');
      return;
    }
    if (_room == null) {
      await _connect();
      return;
    }
    await HangoutState.instance.toggleMute?.call();
  }

  Future<void> _applyPlayerMute() async {
    await _room?.localParticipant?.setMicrophoneEnabled(false);
    HangoutState.instance.muted = true;
    HangoutState.instance.changed();
  }

  Future<void> _leave() async {
    await HangoutState.instance.leave?.call();
  }

  void _sendControl(String type, String userId) {
    widget.socket.send(type, {'userId': userId});
    Navigator.of(context).pop();
  }

  Future<void> _openPanel() async {
    final n = context.neon;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // The app theme leaves sheets transparent for screens that paint their
      // own panel; this one has none, so it brings its own solid surface —
      // otherwise the game shows straight through it.
      backgroundColor: n.panel,
      isScrollControlled: true,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: ListView(shrinkWrap: true, children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.graphic_eq_rounded),
              title: Text('Live talk'),
            ),
            if (_room != null) ...[
              for (final participant in HangoutState.instance.participants)
                ListTile(
                  leading: Avatar(
                      participant.name.isEmpty
                          ? _name(participant.identity)
                          : participant.name,
                      size: 36,
                      imageUrl:
                          HangoutState.instance.avatars[participant.identity]),
                  title: Text(participant.name.isEmpty
                      ? _name(participant.identity)
                      : participant.name),
                  trailing: Icon(
                      participant.isSpeaking
                          ? Icons.graphic_eq
                          : participant.isMuted
                              ? Icons.mic_off
                              : Icons.mic,
                      color: participant.isSpeaking ? n.jade : n.mute),
                ),
              ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Open hangout'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    HangoutState.instance.show();
                  }),
            ],
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
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800))),
                for (final id in _requests)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_add_alt_1_rounded),
                    title: Text(_name(id)),
                    trailing: Wrap(spacing: 4, children: [
                      IconButton(
                        tooltip: 'Decline',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () =>
                            _sendControl('SPECTATOR_VOICE_DECLINE', id),
                      ),
                      IconButton.filled(
                        tooltip: 'Approve',
                        icon: const Icon(Icons.check_rounded),
                        onPressed: () =>
                            _sendControl('SPECTATOR_VOICE_APPROVE', id),
                      ),
                    ]),
                  ),
              ],
              if (_speakers.isNotEmpty) ...[
                const Divider(),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('LIVE SPECTATORS',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800))),
                for (final id in _speakers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_mutedSpeakers.contains(id)
                        ? Icons.mic_off_rounded
                        : Icons.record_voice_over_rounded),
                    title: Text(_name(id)),
                    trailing: Wrap(spacing: 4, children: [
                      IconButton(
                        tooltip:
                            _mutedSpeakers.contains(id) ? 'Unmute' : 'Mute',
                        icon: Icon(_mutedSpeakers.contains(id)
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded),
                        onPressed: () =>
                            _sendControl('SPECTATOR_VOICE_MUTE_TOGGLE', id),
                      ),
                      IconButton(
                        tooltip: 'Remove from live talk',
                        icon: const Icon(Icons.person_remove_alt_1_rounded),
                        onPressed: () =>
                            _sendControl('SPECTATOR_VOICE_REMOVE', id),
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
        title: Text(
            _requesting ? 'Waiting for a player' : 'Request to join live talk'),
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
        leading: Icon(
            _serverMuted || _muted ? Icons.mic_off_rounded : Icons.mic_rounded),
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
      tooltip: HangoutState.instance.speaking.isNotEmpty
          ? '${HangoutState.instance.speaking.join(', ')} talking'
          : widget.spectating
              ? 'Live talk'
              : 'Game voice and live speakers',
      onPressed: _joining ? null : _openPanel,
      icon: Stack(clipBehavior: Clip.none, children: [
        Icon(HangoutState.instance.speaking.isNotEmpty
            ? Icons.graphic_eq_rounded
            : _serverMuted || (_room != null && _muted)
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
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 1.5),
              ),
            ),
          ),
      ]),
    );
  }
}
