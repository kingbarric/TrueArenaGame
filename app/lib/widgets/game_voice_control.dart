import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:permission_handler/permission_handler.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';

/// The same join/mute/leave control on every game table.
class GameVoiceControl extends StatefulWidget {
  const GameVoiceControl({super.key, required this.roomId});
  final String roomId;

  @override
  State<GameVoiceControl> createState() => _GameVoiceControlState();
}

class _GameVoiceControlState extends State<GameVoiceControl> {
  livekit.Room? _room;
  bool _joining = false;
  bool _muted = false;

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

  @override
  void dispose() {
    final room = _room;
    if (room != null) {
      room.disconnect();
      room.dispose();
    }
    super.dispose();
  }

  Future<void> _toggle() async {
    final room = _room;
    if (room != null) {
      try {
        await room.localParticipant?.setMicrophoneEnabled(_muted);
        if (mounted) setState(() => _muted = !_muted);
      } catch (_) {
        _message('Could not change microphone state');
      }
      return;
    }

    setState(() => _joining = true);
    final api = AppScope.of(context).api;
    livekit.Room? joining;
    try {
      if (!(await Permission.microphone.request()).isGranted) {
        _message(
            'Allow microphone access in iPhone Settings to use game voice');
        return;
      }
      final response = await api.post('/calls/games/${widget.roomId}/token')
          as Map<String, dynamic>;
      joining = livekit.Room();
      await joining.connect(
          response['livekitUrl'] as String, response['token'] as String);
      if (!mounted) return;

      // Connecting and publishing the microphone are separate operations.
      // Keep a successful voice connection alive if iOS needs the user to tap
      // once more before it can publish audio; previously that publish error
      // fell into the outer catch and immediately disconnected the room.
      final connectedRoom = joining;
      _room = connectedRoom;
      joining = null;
      final microphoneOn = await _enableMicrophone(connectedRoom);
      if (!mounted) {
        await connectedRoom.disconnect();
        connectedRoom.dispose();
        return;
      }
      setState(() {
        _muted = !microphoneOn;
      });
      if (!microphoneOn) {
        _message('Voice connected. Tap the microphone again to turn it on.');
      }
    } on ApiException catch (error) {
      _message('Game voice: ${error.message}');
    } catch (error, stack) {
      debugPrint('Game voice connection failed: $error\n$stack');
      _message(
          'Could not connect game voice. Check your connection and try again.');
    } finally {
      if (joining != null) {
        await joining.disconnect();
        joining.dispose();
      }
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _leave() async {
    final room = _room;
    if (room == null) return;
    setState(() => _room = null);
    await room.disconnect();
    room.dispose();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: _joining
            ? 'Connecting to game voice'
            : _room == null
                ? 'Join game voice'
                : _muted
                    ? 'Unmute microphone'
                    : 'Mute microphone',
        icon: Icon(_room == null
            ? Icons.mic_none_rounded
            : _muted
                ? Icons.mic_off_rounded
                : Icons.mic_rounded),
        onPressed: _joining ? null : _toggle,
      ),
      if (_room != null)
        IconButton(
          tooltip: 'Leave game voice',
          icon: const Icon(Icons.call_end_rounded),
          onPressed: _leave,
        ),
    ]);
  }
}
