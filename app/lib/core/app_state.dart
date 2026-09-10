import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'device_id.dart';
import 'models.dart';

enum Identity { anonymous, guest, account }

/// Session + identity, held once and shared through [AppScope]. Persists the account
/// tokens; a guest identity is intentionally ephemeral (device id only, cleared after
/// one game unless a phone/email is verified — see the guest funnel).
class AppState extends ChangeNotifier {
  AppState(this.api);

  final ApiClient api;

  Identity identity = Identity.anonymous;
  UserView? user;
  ThemeMode themeMode = ThemeMode.system;

  static const _kAccess = 'ta_access';
  static const _kRefresh = 'ta_refresh';
  static const _kThemeMode = 'ta_theme';

  Future<void> bootstrap() async {
    api.deviceId = await DeviceId.get();
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_kThemeMode)) {
      case 'light':
        themeMode = ThemeMode.light;
      case 'dark':
        themeMode = ThemeMode.dark;
      default:
        themeMode = ThemeMode.system;
    }
    final access = prefs.getString(_kAccess);
    if (access != null && access.isNotEmpty) {
      api.bearer = access;
      try {
        final me = await api.get('/me') as Map<String, dynamic>;
        user = UserView.fromJson(me);
        identity = Identity.account;
      } catch (_) {
        await signOut();
      }
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.name);
  }

  Future<void> completeAccountSignIn(AuthTokens tokens) async {
    api.bearer = tokens.access;
    user = tokens.user;
    identity = Identity.account;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccess, tokens.access);
    await prefs.setString(_kRefresh, tokens.refresh);
    notifyListeners();
  }

  /// A guest gets no persisted token — just the device id and a nickname for one game.
  void startGuest(String nickname) {
    identity = Identity.guest;
    user = UserView(id: 'guest:${api.deviceId}', displayName: nickname);
    notifyListeners();
  }

  Future<void> signOut() async {
    api.bearer = null;
    user = null;
    identity = Identity.anonymous;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!.notifier!;
  }
}
