import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../core/api_client.dart';

enum PreviewVoiceStatus {
  off,
  connecting,
  listening,
  reconnecting,
  unavailable
}

typedef PreviewAudioFactory = PreviewAudio Function(VoidCallback disconnected);

/// Media boundary for a receive-only preview. No microphone/camera is created.
abstract class PreviewAudio {
  Future<void> connect(String url, String token);
  Future<void> play();
  Future<void> close();
}

class LiveKitPreviewAudio implements PreviewAudio {
  LiveKitPreviewAudio(VoidCallback disconnected) {
    _events = _room.createListener()
      ..on<lk.RoomDisconnectedEvent>((_) {
        if (!_closed) disconnected();
      })
      ..on<lk.TrackPublishedEvent>((e) {
        if (_playing && !_closed && e.publication.kind == lk.TrackType.AUDIO) {
          unawaited(e.publication.subscribe().catchError((_) {}));
        }
      });
  }
  final _room = lk.Room();
  late final lk.EventsListener<lk.RoomEvent> _events;
  bool _closed = false, _playing = false;

  @override
  Future<void> connect(String url, String token) async {
    // A late connection from a previous swipe cannot start playing audio.
    await _room.connect(url, token,
        connectOptions: const lk.ConnectOptions(autoSubscribe: false));
    if (_closed) await _room.disconnect();
  }

  @override
  Future<void> play() async {
    if (_closed) return;
    _playing = true;
    for (final person in _room.remoteParticipants.values) {
      for (final publication in person.audioTrackPublications) {
        if (_closed) return;
        await publication.subscribe();
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _playing = false;
    try {
      await _room.disconnect();
    } finally {
      await _events.dispose();
      await _room.dispose();
    }
  }
}

class _Attempt {
  _Attempt(this.huud, this.epoch);
  final String huud;
  final int epoch;
  String? previewId;
  PreviewAudio? audio;
  bool stopSent = false;
}

/// Exactly one visible Huud owns preview sound. Swipes invalidate pending work.
class HuudPreviewVoice extends ChangeNotifier {
  HuudPreviewVoice(this.api, {PreviewAudioFactory? createAudio})
      : _createAudio = createAudio ?? LiveKitPreviewAudio.new;
  final ApiClient api;
  final PreviewAudioFactory _createAudio;
  String? _target;
  _Attempt? _attempt;
  Timer? _retry;
  int _epoch = 0, _failures = 0;
  bool _disposed = false;
  PreviewVoiceStatus _status = PreviewVoiceStatus.off;
  PreviewVoiceStatus get status => _status;
  String? get target => _target;

  void _show(PreviewVoiceStatus value) {
    if (_disposed) return;
    _status = value;
    notifyListeners();
  }

  Future<void> watch(String? id) async {
    if (_disposed || id == _target) return;
    _target = id;
    final epoch = ++_epoch;
    _retry?.cancel();
    _retry = null;
    _failures = 0;
    final old = _attempt;
    _attempt = null;
    _show(id == null ? PreviewVoiceStatus.off : PreviewVoiceStatus.connecting);
    await _close(old);
    if (_disposed || epoch != _epoch || id == null) return;
    await _connect(epoch);
  }

  bool _current(_Attempt attempt) =>
      !_disposed && attempt.epoch == _epoch && identical(_attempt, attempt);

  Future<void> _connect(int epoch) async {
    final id = _target;
    if (_disposed || id == null || epoch != _epoch) return;
    final attempt = _Attempt(id, epoch);
    _attempt = attempt;
    try {
      final raw = await api.post('/huud-spaces/$id/listen') as Map;
      attempt.previewId = raw['previewId'] as String;
      if (!_current(attempt)) {
        await _close(attempt);
        return;
      }
      final audio = _createAudio(() => _failed(attempt));
      attempt.audio = audio;
      await audio
          .connect(raw['livekitUrl'] as String, raw['token'] as String)
          .timeout(const Duration(seconds: 20));
      if (!_current(attempt)) {
        await _close(attempt);
        return;
      }
      await audio.play();
      if (!_current(attempt)) {
        await _close(attempt);
        return;
      }
      _failures = 0;
      _show(PreviewVoiceStatus.listening);
    } catch (error) {
      if (_current(attempt)) _failed(attempt, error);
      await _close(attempt);
    }
  }

  void _failed(_Attempt attempt, [Object? error]) {
    if (!_current(attempt)) return;
    _attempt = null;
    final epoch = ++_epoch;
    unawaited(_close(attempt));
    if (error is ApiException && (error.status == 403 || error.status == 404)) {
      _show(PreviewVoiceStatus.unavailable);
      return;
    }
    _show(PreviewVoiceStatus.reconnecting);
    const seconds = [2, 4, 8, 15, 30];
    final delay = seconds[_failures.clamp(0, seconds.length - 1)];
    _failures++;
    _retry = Timer(Duration(seconds: delay), () {
      _retry = null;
      unawaited(_connect(epoch));
    });
  }

  Future<void> _close(_Attempt? attempt) async {
    if (attempt == null) return;
    final preview = attempt.previewId;
    if (preview != null && !attempt.stopSent) {
      attempt.stopSent = true;
      // Session-specific: an old stop cannot remove a new visit to this Huud.
      unawaited(api
          .delete('/huud-spaces/${attempt.huud}/listen/$preview')
          .catchError((_) => null));
    }
    try {
      await attempt.audio?.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      // The session is already invalidated locally; server cleanup is separate.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    _retry?.cancel();
    unawaited(_close(_attempt));
    _attempt = null;
    super.dispose();
  }
}
