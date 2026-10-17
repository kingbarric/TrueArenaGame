import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/features/huudspace/huud_reconnect.dart';

void main() {
  testWidgets(
      'outages beyond two failures recover automatically and duplicate errors share one retry',
      (tester) async {
    var calls = 0, notices = 0;
    late HuudReconnect recovery;
    recovery = HuudReconnect(
        delays: const [Duration(milliseconds: 10)],
        onWaiting: () => notices++,
        reconnect: () async {
          calls++;
          if (calls < 5) throw StateError('offline');
          recovery.connected();
        });
    recovery.failed();
    recovery.failed();
    recovery.failed();
    expect(calls, 0);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 11));
    }
    expect(calls, 5);
    expect(notices, greaterThanOrEqualTo(5));
    await tester.pump(const Duration(minutes: 5));
    expect(calls, 5);
    recovery.dispose();
  });
  testWidgets(
      'a stalled renderer retries, pauses in background, and stops after disposal',
      (tester) async {
    var calls = 0;
    final hung = Completer<void>();
    final recovery = HuudReconnect(
        loadTimeout: const Duration(milliseconds: 20),
        attemptTimeout: const Duration(milliseconds: 20),
        delays: const [Duration(milliseconds: 10)],
        onWaiting: () {},
        reconnect: () {
          calls++;
          return hung.future;
        });
    recovery.waiting();
    await tester.pump(const Duration(milliseconds: 21));
    recovery.pause();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
    recovery.resume();
    await tester.pump();
    expect(calls, 1);
    recovery.retryNow();
    recovery.retryNow();
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 21));
    await tester.pump(const Duration(milliseconds: 11));
    expect(calls, 2);
    recovery.dispose();
    hung.complete();
    await tester.pump(const Duration(minutes: 5));
    expect(calls, 2);
  });
  testWidgets(
      'a failed startup reported inside an attempt does not get stuck waiting for a load event',
      (tester) async {
    var calls = 0;
    late HuudReconnect recovery;
    recovery = HuudReconnect(
        delays: const [Duration(milliseconds: 10)],
        onWaiting: () {},
        reconnect: () async {
          calls++;
          if (calls < 4) {
            recovery.failed();
          } else {
            recovery.connected();
          }
        });
    recovery.failed();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 11));
    }
    expect(calls, 4);
    recovery.dispose();
  });
}
