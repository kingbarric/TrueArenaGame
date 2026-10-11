import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the phone's screen on while something needs it — you're inside a
/// Huud, or connected to a game (playing or watching). Each holder takes a
/// turn on and gives it back; the screen may sleep again once nobody holds it.
class KeepAwake {
  KeepAwake._();

  static final _holders = <Object>{};

  static void hold(Object holder) {
    if (_holders.add(holder) && _holders.length == 1) _set(true);
  }

  static void release(Object holder) {
    if (_holders.remove(holder) && _holders.isEmpty) _set(false);
  }

  static void _set(bool on) {
    try {
      WakelockPlus.toggle(enable: on).catchError((Object _) {});
    } catch (_) {
      // No screen to keep on (tests, desktop) — nothing to do.
    }
  }
}
