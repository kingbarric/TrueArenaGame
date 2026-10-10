import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/push_notifications.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a notification that opened the app opens it once — not on every later launch', () async {
    final sent = DateTime(2026, 10, 9, 12);
    final now = sent.add(const Duration(minutes: 2));
    expect(await PushNotifications.isFreshLaunchMessage('m1', sent, now: now), isTrue);
    expect(await PushNotifications.isFreshLaunchMessage('m1', sent, now: now), isFalse);
    expect(await PushNotifications.isFreshLaunchMessage('m2', sent, now: now), isTrue);
  });

  test('an old notification never pulls you into a game', () async {
    final sent = DateTime(2026, 10, 7, 21);
    expect(await PushNotifications.isFreshLaunchMessage('old', sent, now: DateTime(2026, 10, 9, 12)), isFalse);
  });
}
