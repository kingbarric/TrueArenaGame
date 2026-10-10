import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_client.dart';
import '../../core/hangout_state.dart';
import '../../widgets/mic_button.dart';

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

  /// You've asked the host for the mic and are waiting.
  bool asked = false;

  /// Where the mic is right now, for any mic button (the Huud's, a game's).
  MicState get micState {
    if (_room == null) return asked ? MicState.asked : MicState.locked;
    if (!_canSpeak) return asked ? MicState.asked : MicState.locked;
    return _state.muted ? MicState.muted : MicState.live;
  }

  /// The Huud this voice belongs to (its room is `huud-<id>`).
  String? get huudId {
    final room = _state.roomName;
    return room != null && room.startsWith('huud-') && _state.onOpen != null ? room.substring(5) : null;
  }

  /// Ask the host for the mic — from the Huud or from a game's top bar.
  Future<bool> askForMic(ApiClient api) async {
    final id = huudId;
    if (id == null) return false;
    try {
      await api.post('/huud-spaces/$id/mic');
      asked = true;
      _state.changed();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The one tap every mic button makes: ask, wait, or switch the mic.
  Future<MicResult?> tap(ApiClient api) async {
    switch (micState) {
      case MicState.locked:
        await askForMic(api);
        return null;
      case MicState.asked:
        return null;
      case MicState.muted:
        return setMuted(false);
      case MicState.live:
        return setMuted(true);
    }
  }

  /// Tests start from nothing.
  @visibleForTesting
  void reset() {
    asked = false;
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
        final was = _canSpeak;
        _canSpeak = e.permissions.canPublish;
        // Mic taken back: you're muted again.
        if (!_canSpeak) _state.muted = true;
        // You asked and the host said yes: your mic comes on.
        if (_canSpeak && !was && asked) {
          asked = false;
          setMuted(false);
        }
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

  /// Mic on or off, and why not when it can't be.
  Future<MicResult> setMuted(bool muted) async {
    final room = _room;
    if (room == null) return MicResult.notConnected;
    if (!muted) {
      if (!_canSpeak) return MicResult.noMic;
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        debugPrint('HuudVoice: microphone permission is $status');
        return MicResult.noPermission;
      }
    }
    // iOS can refuse the first try ("session activation failed") while it
    // moves audio over — e.g. AirPods switching from listening to talking.
    // A moment later it works, so try a few times before giving up.
    for (var attempt = 1;; attempt++) {
      try {
        await room.localParticipant?.setMicrophoneEnabled(!muted);
        break;
      } catch (e) {
        debugPrint('HuudVoice: setMicrophoneEnabled(${!muted}) try $attempt failed: $e');
        if (attempt == 4) {
          if (!muted) await room.localParticipant?.setMicrophoneEnabled(false).catchError((Object _) => null);
          return MicResult.failed;
        }
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      }
    }
    _state.muted = muted;
    _state.changed();
    _api?.post('/calls/sessions/mute', {'muted': muted}).catchError((Object _) => null);
    return MicResult.ok;
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
    asked = false;
    if (room != null) {
      if (_state.room == room) _state.attach(null);
      await room.disconnect();
      await room.dispose();
    }
  }
}

enum MicResult { ok, notConnected, noMic, noPermission, failed }
