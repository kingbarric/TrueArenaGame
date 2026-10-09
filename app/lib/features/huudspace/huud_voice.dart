import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_client.dart';
import '../../core/hangout_state.dart';

/// A Huud's voice, without a call screen. Being in a Live Huud connects you
/// straight away with your mic off — you hear everyone; tapping the mic on
/// the Huud screen turns yours on (if the host has handed it to you).
///
/// It shares [HangoutState] with ordinary calls, so the little "who's
/// talking" bar still shows over the Huud's games; tapping that bar brings
/// you back to the Huud instead of opening a call screen.
class HuudVoice {
  HuudVoice._();
  static final instance = HuudVoice._();

  ApiClient? _api;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;
  Timer? _heartbeat;
  String? _connecting;
  bool _leaving = false;
  bool _canSpeak = false;

  /// Leave was asked for while still joining — finish by leaving.
  bool _cancel = false;

  HangoutState get _state => HangoutState.instance;

  /// Connected to this Huud's voice room.
  bool isIn(String roomName) => _state.roomName == roomName && _room != null;

  bool isConnecting(String roomName) => _connecting == roomName;

  /// The host has handed you the mic (or you're the host).
  bool get canSpeak => _canSpeak;

  /// Tests start from nothing.
  @visibleForTesting
  void reset() {
    _connecting = null;
    _cancel = false;
    _room = null;
    _canSpeak = false;
  }

  Future<void> join({
    required ApiClient api,
    required String roomName,
    required String title,
    required VoidCallback openHuud,
  }) async {
    if (_connecting != null) return;
    _cancel = false;
    await _join(api, roomName, title, openHuud);
  }

  Future<void> leave() async {
    if (_connecting != null) {
      _cancel = true;
      return;
    }
    await _leave();
  }

  Future<void> _join(ApiClient api, String roomName, String title, VoidCallback openHuud) async {
    if (_state.roomName == roomName && _room != null) {
      _state.onOpen = openHuud;
      return;
    }
    // Already on a call with a friend — don't cut it off; the Huud stays quiet.
    if (_state.active && _state.roomName != roomName) return;
    _api = api;
    _connecting = roomName;
    _state.changed();
    try {
      const wait = Duration(seconds: 12);
      final token = (await api.post('/calls/rooms/$roomName/token').timeout(wait) as Map).cast<String, dynamic>();
      await api.post('/calls/sessions/join', {'roomName': roomName}).timeout(wait).catchError((Object _) => null);
      api.post('/calls/sessions/mute', {'muted': true}).catchError((Object _) => null);
      _state
        ..open(const SizedBox.shrink(), roomName, title)
        ..expanded = false
        ..muted = true
        ..onOpen = openHuud
        ..toggleMute = (() => setMuted(!_state.muted))
        ..leave = leave
        ..play = null;
      await _connect(token['livekitUrl'] as String, token['token'] as String).timeout(const Duration(seconds: 20));
      if (_cancel) throw StateError('left while joining');
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        _api?.post('/calls/sessions/heartbeat').catchError((Object _) => null);
      });
    } catch (_) {
      await _teardown();
      if (_state.roomName == roomName) _state.clear();
      if (_cancel) api.post('/calls/sessions/leave', {'roomName': roomName}).catchError((Object _) => null);
    } finally {
      _connecting = null;
      _cancel = false;
      _state.changed();
    }
  }

  Future<void> _connect(String url, String token) async {
    final room = lk.Room();
    _room = room;
    _state.attach(room);
    final events = room.createListener();
    _events = events;
    events
      ..on<lk.ParticipantPermissionsUpdatedEvent>((e) {
        if (e.participant is! lk.LocalParticipant) return;
        _canSpeak = e.permissions.canPublish;
        // Mic taken back: you're muted again.
        if (!_canSpeak) _state.muted = true;
        _state.changed();
      })
      ..on<lk.RoomDisconnectedEvent>((e) {
        if (_leaving || e.reason == lk.DisconnectReason.clientInitiated) return;
        _rejoin();
      });
    await room.connect(url, token);
    _canSpeak = room.localParticipant?.permissions.canPublish ?? false;
  }

  /// The network dropped for longer than LiveKit's own retries: try again
  /// with a fresh token for a little while, quietly.
  Future<void> _rejoin() async {
    final roomName = _state.roomName;
    final api = _api;
    final open = _state.onOpen;
    if (roomName == null || api == null || open == null) return;
    await _teardown();
    _state.clear();
    for (var i = 0; i < 20 && !_leaving && !_state.active; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (_leaving || _state.active) return;
      await _join(api, roomName, '', open);
      if (_state.roomName == roomName) return;
    }
  }

  /// Mic on or off. Returns false when you can't talk (the host hasn't
  /// handed you the mic) or the phone's microphone is switched off.
  Future<bool> setMuted(bool muted) async {
    final room = _room;
    if (room == null) return false;
    if (!muted) {
      if (!_canSpeak) return false;
      if (!(await Permission.microphone.request()).isGranted) return false;
    }
    try {
      await room.localParticipant?.setMicrophoneEnabled(!muted);
    } catch (_) {
      return false;
    }
    _state.muted = muted;
    _state.changed();
    _api?.post('/calls/sessions/mute', {'muted': muted}).catchError((Object _) => null);
    return true;
  }

  Future<void> _leave() async {
    final roomName = _state.roomName;
    if (roomName == null || _state.onOpen == null) return;
    _leaving = true;
    try {
      await _api?.post('/calls/sessions/leave', {'roomName': roomName}).catchError((Object _) => null);
      await _teardown();
      _state.clear();
    } finally {
      _leaving = false;
    }
  }

  Future<void> _teardown() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _events?.dispose();
    _events = null;
    final room = _room;
    _room = null;
    _canSpeak = false;
    if (room != null) {
      if (_state.room == room) _state.attach(null);
      await room.disconnect();
      await room.dispose();
    }
  }
}
