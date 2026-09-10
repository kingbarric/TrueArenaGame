import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A stable per-install identifier for temporary (guest) players. One game is played
/// under this id; everything clears afterwards unless the guest verifies a phone
/// (preferred) or email. See docs/GAME_CONFIG.md / the guest funnel.
class DeviceId {
  static const _key = 'ta_device_id';

  static Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null || id.isEmpty) {
      id = _uuidV4();
      await prefs.setString(_key, id);
    }
    return id;
  }

  static String _uuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant 10
    String hex(int start, int end) =>
        b.sublist(start, end).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
