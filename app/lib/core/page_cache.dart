import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Account and server scoped snapshots, never credentials or private match state.
class PageCache {
  PageCache(this.prefs, String origin, String userId)
      : key = 'ta_pages_v1_${Uri.encodeComponent(origin)}_$userId' {
    try {
      final raw = prefs.getString(key);
      if (raw != null) {
        _entries.addAll((jsonDecode(raw) as Map).cast<String, dynamic>());
      }
    } catch (_) {/* A damaged snapshot must not prevent launch. */}
  }
  final SharedPreferences prefs;
  final String key;
  final _entries = <String, dynamic>{};
  bool _cleared = false;
  static bool permits(String path) {
    final p = Uri.parse(path).path;
    return const [
          '/huuds/sessions',
          '/huuds/sessions/owned',
          '/huud/feed',
          '/friends',
          '/friends/requests',
          '/conversations',
          '/me/stats',
          '/me/competitive',
          '/competitive/games',
          '/championships/badges/mine'
        ].contains(p) ||
        RegExp(r'^/huuds/sessions/[^/]+(/chat)?$').hasMatch(p) ||
        RegExp(r'^/conversations/[^/]+(/messages)?$').hasMatch(p);
  }

  dynamic read(String path) {
    if (_cleared || !permits(path)) return null;
    try {
      final entry = _entries[path] as Map?;
      if (entry == null ||
          DateTime.now().millisecondsSinceEpoch - (entry['at'] as int) >
              const Duration(days: 7).inMilliseconds) {
        return null;
      }
      return jsonDecode(jsonEncode(entry['data']));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String path, dynamic data) async {
    if (_cleared || !permits(path)) return;
    final encoded = jsonEncode(data);
    if (utf8.encode(encoded).length > 256 * 1024) return;
    _entries.remove(path);
    _entries[path] = {
      'at': DateTime.now().millisecondsSinceEpoch,
      'data': jsonDecode(encoded)
    };
    while (_entries.length > 40 ||
        utf8.encode(jsonEncode(_entries)).length > 2 * 1024 * 1024) {
      _entries.remove(_entries.keys.first);
    }
    await prefs.setString(key, jsonEncode(_entries));
  }

  Future<void> remove(String path) async {
    _entries.remove(path);
    if (!_cleared) await prefs.setString(key, jsonEncode(_entries));
  }

  Future<void> clear() async {
    _cleared = true;
    _entries.clear();
    await prefs.remove(key);
  }
}
