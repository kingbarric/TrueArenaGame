import 'dart:async';

/// Keeps retrying at a bounded rate until the renderer confirms it is ready.
/// Pausing/disposal stops timers; a stalled load is treated as a disconnect.
class HuudReconnect {
  HuudReconnect(
      {required this.reconnect,
      required this.onWaiting,
      this.loadTimeout = const Duration(seconds: 75),
      this.attemptTimeout = const Duration(seconds: 30),
      this.delays = const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 15),
        Duration(seconds: 30)
      ]});
  final Future<void> Function() reconnect;
  final void Function() onWaiting;
  final Duration loadTimeout, attemptTimeout;
  final List<Duration> delays;
  Timer? _retry, _watchdog;
  bool _disposed = false,
      _active = true,
      _running = false,
      _healthy = false,
      _failedDuringRun = false;
  int _attempt = 0, _confirmed = 0;

  void waiting() {
    if (_disposed || !_active || _healthy) return;
    _watchdog?.cancel();
    _watchdog = Timer(loadTimeout, failed);
  }

  void failed() {
    if (_disposed) return;
    _healthy = false;
    if (_running) _failedDuringRun = true;
    _watchdog?.cancel();
    onWaiting();
    if (!_active || _running || _retry != null) return;
    final delay = delays[_attempt.clamp(0, delays.length - 1)];
    _attempt++;
    _retry = Timer(delay, () {
      _retry = null;
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    if (_disposed || !_active || _running) return;
    _running = true;
    _failedDuringRun = false;
    final confirmed = _confirmed;
    var failedAttempt = false;
    try {
      await reconnect().timeout(attemptTimeout);
    } catch (_) {
      failedAttempt = true;
    } finally {
      _running = false;
    }
    if (_disposed || _confirmed != confirmed) return;
    if (failedAttempt || _failedDuringRun) {
      failed();
    } else {
      waiting();
    }
  }

  void connected() {
    if (_disposed) return;
    _confirmed++;
    _healthy = true;
    _attempt = 0;
    _retry?.cancel();
    _retry = null;
    _watchdog?.cancel();
  }

  void retryNow() {
    if (_disposed) return;
    _healthy = false;
    _retry?.cancel();
    _retry = null;
    _watchdog?.cancel();
    unawaited(_run());
  }

  void pause() {
    _active = false;
    _retry?.cancel();
    _retry = null;
    _watchdog?.cancel();
  }

  void resume() {
    if (_disposed) return;
    _active = true;
    if (!_healthy) retryNow();
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _watchdog?.cancel();
  }
}
