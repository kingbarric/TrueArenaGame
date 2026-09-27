import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';

import '../../core/app_state.dart';
import '../../core/e2e_crypto.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';

/// A voice call — 1:1 or group, same screen either way, since a LiveKit
/// room is multi-party by default (see `CallService`, ta-api: a DM call and
/// a group call are the same mechanism, just a different room name and
/// membership check to get the token). Connects with the token the caller
/// already fetched from `POST /calls/dm/{id}/token` or
/// `/calls/groups/{id}/token`.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.roomName,
    required this.token,
    required this.livekitUrl,
    required this.title,
    this.peerPublicKey,
  });

  final String roomName;
  final String token;
  final String livekitUrl;
  final String title;

  /// The other participant's X25519 public key, for a 1:1 call — when
  /// present, the same shared secret that encrypts this pair's DMs is used
  /// as LiveKit's frame-encryption key, so the media is end-to-end
  /// encrypted and the SFU relays frames it can't decode (see `E2eCrypto`).
  /// Null for a group call: every member would need the same key
  /// distributed to them, which is a real key-distribution problem this
  /// pass deliberately doesn't solve — group calls stay transport-encrypted
  /// (DTLS-SRTP) only, exactly as before.
  final String? peerPublicKey;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  /// Built in [_connect] rather than at field init, because the E2EE key
  /// has to be derived first — it's a construction-time room option.
  lk.Room? _room;
  StreamSubscription? _eventsSub;
  Timer? _ticker;

  bool _connecting = true;
  bool _muted = false;
  bool _e2ee = false;
  String? _error;
  int _seconds = 0;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _app = AppScope.of(context);
    _connect();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _eventsSub?.cancel();
    final room = _room;
    if (room != null) {
      room.removeListener(_onRoomChanged);
      room.disconnect();
      room.dispose();
    }
    _app?.inbox?.send('CALL_LEFT');
    super.dispose();
  }

  // Captured once, before any `await`, so it's safe to use after one without
  // touching `context` post-frame — `initState` is the only place this reads it.
  AppState? _app;

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Microphone access is off — turn it on in Settings to make calls.';
        });
      }
      return;
    }
    try {
      // A 1:1 call encrypts its media frames with the same X25519 shared
      // secret that encrypts this pair's DMs — the key is derived on-device
      // and never sent anywhere, so LiveKit's SFU forwards frames it can't
      // decode. A group call has no such key (see `peerPublicKey`) and
      // connects exactly as it did before.
      lk.E2EEOptions? e2ee;
      final secret = await E2eCrypto.sharedSecretWith(widget.peerPublicKey);
      if (secret != null) {
        e2ee = await lk.E2EEOptions.sharedKey(await E2eCrypto.sharedSecretHex(secret));
      }
      final room = lk.Room(roomOptions: lk.RoomOptions(e2eeOptions: e2ee));
      _room = room;
      room.addListener(_onRoomChanged);

      await room.connect(widget.livekitUrl, widget.token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      _app?.inbox?.send('CALL_JOINED', {'roomName': widget.roomName});
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _e2ee = e2ee != null;
        _muted = !(room.localParticipant?.isMicrophoneEnabled() ?? true);
      });
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Could not connect — check your mic permission and connection.';
        });
      }
    }
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    await _room?.localParticipant?.setMicrophoneEnabled(!next);
    if (mounted) setState(() => _muted = next);
  }

  Future<void> _leave() async {
    await _room?.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  String get _duration {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final participants = <lk.Participant>[
      if (_room?.localParticipant != null) _room!.localParticipant!,
      ...?_room?.remoteParticipants.values,
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: const Color(0xff130C0D),
        body: SafeArea(
          child: Column(children: [
            const SizedBox(height: 24),
            Text(widget.title, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 26)),
            const SizedBox(height: 6),
            Text(
              _connecting ? 'Connecting…' : (_error ?? _duration),
              style: TextStyle(color: _error != null ? n.danger : n.mute, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            if (_e2ee && _error == null) ...[
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.lock_rounded, size: 12, color: n.jade),
                const SizedBox(width: 4),
                Text('End-to-end encrypted',
                    style: TextStyle(color: n.jade, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ],
            Expanded(
              child: _connecting
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      padding: const EdgeInsets.all(24),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, mainAxisSpacing: 18, crossAxisSpacing: 18, childAspectRatio: 0.85,
                      ),
                      itemCount: participants.length,
                      itemBuilder: (context, i) => _participantTile(n, participants[i]),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _roundButton(
                  icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  active: !_muted,
                  onTap: _connecting ? null : _toggleMute,
                ),
                const SizedBox(width: 24),
                _roundButton(icon: Icons.call_end_rounded, active: false, danger: true, onTap: _leave),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _participantTile(NeonColors n, lk.Participant p) {
    final speaking = p.isSpeaking;
    final muted = p.isMuted;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: const Color(0xff241517),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: speaking ? n.jade : const Color(0xff3A2429), width: speaking ? 2.4 : 1),
        boxShadow: speaking ? [BoxShadow(color: n.jade.withValues(alpha: 0.4), blurRadius: 18, spreadRadius: -2)] : null,
      ),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Avatar(p.name.isNotEmpty ? p.name : p.identity, size: 64),
        const SizedBox(height: 10),
        Text(p.name.isNotEmpty ? p.name : p.identity, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 4),
        Icon(muted ? Icons.mic_off_rounded : Icons.mic_rounded, size: 14, color: muted ? n.mute : n.jade),
      ]),
    );
  }

  Widget _roundButton({required IconData icon, required bool active, VoidCallback? onTap, bool danger = false}) {
    final n = context.neon;
    final bg = danger ? n.danger : (active ? n.jade : const Color(0xff2C1A1D));
    return InkWell(
      borderRadius: BorderRadius.circular(32),
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
        child: Icon(icon, color: danger || active ? Colors.white : n.mute, size: 26),
      ),
    );
  }
}
