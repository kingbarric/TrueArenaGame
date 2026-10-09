import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'social_huud_models.dart';

/// Session screen and game drawer share this controller. Navigation never leaves membership.
class SocialHuudController extends ChangeNotifier {
  SocialHuudController(this.api, this.userId, this.huud) {
    final saved = api.cached(path);
    if (saved is Map) huud = SocialHuud.fromJson(saved.cast<String, dynamic>());
    final chat = api.cached('$path/chat');
    if (chat is List) {
      messages = chat.map((m) => (m as Map).cast<String, dynamic>()).toList();
    }
  }
  bool liveConfirmed = false;
  final ApiClient api;
  final String userId;
  SocialHuud huud;
  List<Map<String, dynamic>> messages = [];
  bool busy = false, unavailable = false;
  String? error;
  Timer? _poll;
  bool _refreshing = false, _disposed = false;
  int _generation = 0;
  String get path => '/huuds/sessions/${huud.id}';
  bool get isHost => huud.ownerId == userId;
  void start() {
    refresh();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed || unavailable || busy) return;
    _refreshing = true;
    liveConfirmed = false;
    final generation = _generation;
    try {
      final view = await api.get(path) as Map;
      final chat = await api.get('$path/chat') as List;
      if (_disposed || generation != _generation) return;
      huud = SocialHuud.fromJson(view.cast<String, dynamic>());
      messages = chat.map((m) => (m as Map).cast<String, dynamic>()).toList();
      liveConfirmed = !api.usedSavedResponse(path) &&
          !api.usedSavedResponse('$path/chat') &&
          !api.offline.value;
      error = api.offline.value ? 'Offline · Showing your saved Huud' : null;
      if (liveConfirmed) {
        await api.post('$path/heartbeat');
        if (_disposed || generation != _generation) return;
      }
    } on ApiException catch (e) {
      if (_disposed || generation != _generation) return;
      liveConfirmed = false;
      error = e.message;
      if (e.status == 403 || e.status == 404) unavailable = true;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      liveConfirmed = false;
      error = 'Connection lost. Reconnecting to your Huud…';
    } finally {
      _refreshing = false;
      if (generation != _generation && !busy && !_disposed) {
        unawaited(refresh());
      }
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> action(String suffix,
      [Map<String, dynamic>? body, bool remove = false]) async {
    if (busy || _disposed) return;
    busy = true;
    _generation++;
    notifyListeners();
    try {
      if (remove) {
        await api.delete('$path$suffix');
      } else {
        await api.post('$path$suffix', {
          ...?body,
          if (suffix == '/game' ||
              suffix == '/game-request' ||
              suffix == '/start' ||
              suffix == '/rematch' ||
              suffix.startsWith('/game-players/') ||
              suffix.startsWith('/roster/'))
            'activityVersion': huud.activityVersion,
        });
      }
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
      await refresh();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    api.delete('$path/viewing').catchError((_) => null);
    super.dispose();
  }
}

class SocialHuudScope extends InheritedWidget {
  const SocialHuudScope(
      {super.key, required this.controller, required super.child});
  final SocialHuudController controller;
  static SocialHuudController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SocialHuudScope>()?.controller;
  @override
  bool updateShouldNotify(SocialHuudScope oldWidget) =>
      controller != oldWidget.controller;
}
