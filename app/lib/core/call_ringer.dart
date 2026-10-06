import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// The sound and buzz of a call that hasn't been answered yet.
///
/// [ring] is what the person being called hears: a looping ringtone and the
/// phone vibrating every couple of seconds, like any phone call. [ringback]
/// is the quieter tone the caller hears while they wait. Only one plays at
/// a time; [stop] silences whichever it is.
class CallRinger {
  CallRinger._();

  static AudioPlayer? _player;
  static Timer? _buzz;

  static Future<void> ring() async {
    await stop();
    _vibrate();
    _buzz =
        Timer.periodic(const Duration(milliseconds: 1600), (_) => _vibrate());
    await _loop('assets/sfx/ringtone.wav', volume: 1.0);
  }

  static Future<void> ringback() async {
    await stop();
    await _loop('assets/sfx/ringback.wav', volume: 0.35);
  }

  static Future<void> stop() async {
    _buzz?.cancel();
    _buzz = null;
    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.stop();
        await player.dispose();
      } catch (_) {
        // already gone
      }
    }
  }

  static void _vibrate() {
    // A full system buzz on iOS; Android's strongest haptic. Best-effort:
    // a device with vibration off just stays still.
    HapticFeedback.vibrate();
  }

  static Future<void> _loop(String asset, {required double volume}) async {
    try {
      final player = AudioPlayer();
      _player = player;
      await player.setAsset(asset);
      await player.setLoopMode(LoopMode.all);
      await player.setVolume(volume);
      if (identical(_player, player)) unawaited(player.play());
    } catch (_) {
      // No audio (tests, a muted audio session) — the buzz still works.
    }
  }
}
