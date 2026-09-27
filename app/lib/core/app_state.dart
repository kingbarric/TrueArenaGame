import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';

import 'api_client.dart';
import 'device_id.dart';
import 'e2e_crypto.dart';
import 'google_config.dart';
import 'inbox_client.dart';
import 'models.dart';
import '../widgets/coin_tier_badge.dart';

enum Identity { anonymous, guest, account }

enum VisualTheme { palmWine, nebula, supercar }

/// Session + identity, held once and shared through [AppScope]. A guest is a real,
/// server-known identity too (`POST /auth/guest`, keyed by device id) — it can host
/// and join real rooms and its tokens persist like an account's; the only difference
/// is it has no phone/email yet, so it's tied to this one device until it verifies
/// one (which upgrades the *same* id in place — see `startGuest`/`_completeSignIn`).
class AppState extends ChangeNotifier {
  AppState(this.api);

  final ApiClient api;
  GoogleSignIn? _googleClient;

  Identity identity = Identity.anonymous;
  UserView? user;
  ThemeMode themeMode = ThemeMode.system;
  VisualTheme visualTheme = VisualTheme.palmWine;

  // There's no backend profile field for this yet (UserView has no avatar
  // column) — kept as a per-device preference alongside theme, same pattern.
  String? avatarEmoji;
  String? avatarImagePath;

  /// Word Bluff's voice auto-detect (see `wordbluff_game_screen.dart`) — off
  /// by default (it needs a mic permission grant), and how close a heard
  /// guess must be to the secret word to auto-lock it in. 1.0 = exact only;
  /// lower values accept a looser match ("gerraffe" for "giraffe").
  bool voiceMatchEnabled = false;
  double voiceMatchThreshold = 0.8;

  /// Live while signed in — see `InboxClient`. `CallScreen` sends
  /// `CALL_JOINED`/`CALL_LEFT` on it directly; `AppState` itself only
  /// listens, for the one thing every screen needs to react to the same
  /// way: a `GAME_STARTING` notification pops [pendingGameInvite] so the
  /// app-level banner (see `app.dart`) can show a Join action regardless of
  /// which screen is on top.
  InboxClient? inbox;
  StreamSubscription? _inboxSub;
  Map<String, dynamic>? pendingGameInvite;

  // Broadcast (not single-value like pendingGameInvite) — a chat list screen
  // and an open conversation screen may both be alive and both want every
  // `NEW_MESSAGE` push, so this fans out rather than holding "the latest".
  final _chatController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get chatMessages => _chatController.stream;

  void dismissGameInvite() {
    pendingGameInvite = null;
    notifyListeners();
  }

  /// Makes sure this device has an X25519 keypair and the server knows its
  /// public half — the one prerequisite for encrypted DMs and DM calls (see
  /// `E2eCrypto`). Fire-and-forget and best-effort: if the upload fails,
  /// DMs simply stay unencrypted for pairs where a key is missing rather
  /// than the app refusing to work.
  void _ensurePublicKey() {
    () async {
      try {
        final publicKey = await E2eCrypto.ensureKeyPair();
        await api.post('/me/public-key', {'publicKey': publicKey});
      } catch (_) {
        // no key published — encrypted DMs stay off for this device until a later launch succeeds
      }
    }();
  }

  void _connectInbox() {
    _inboxSub?.cancel();
    inbox?.close();
    inbox = InboxClient.connect(api);
    _inboxSub = inbox!.envelopes.listen((env) {
      final payload = (env['payload'] as Map?)?.cast<String, dynamic>();
      if (payload?['type'] == 'GAME_STARTING') {
        pendingGameInvite = (payload!['data'] as Map).cast<String, dynamic>();
        notifyListeners();
      } else if (payload?['type'] == 'NEW_MESSAGE') {
        _chatController.add((payload!['data'] as Map).cast<String, dynamic>());
      }
    });
  }

  static const _kAccess = 'ta_access';
  static const _kRefresh = 'ta_refresh';
  static const _kThemeMode = 'ta_theme';
  static const _kVisualTheme = 'ta_visual_theme';
  static const _kAvatarEmoji = 'ta_avatar_emoji';
  static const _kAvatarImage = 'ta_avatar_image';
  static const _kVoiceMatchEnabled = 'ta_voice_match_enabled';
  static const _kVoiceMatchThreshold = 'ta_voice_match_threshold';

  Future<void> bootstrap() async {
    api.deviceId = await DeviceId.get();
    // Lets ApiClient recover a mid-session 401 on its own (the access token
    // is only good for 15 min) instead of every call site having to special-
    // case token expiry — see ApiClient._send and _tryRefresh below.
    api.refreshHandler = _tryRefresh;
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_kThemeMode)) {
      case 'light':
        themeMode = ThemeMode.light;
      case 'dark':
        themeMode = ThemeMode.dark;
      default:
        themeMode = ThemeMode.system;
    }
    final savedVisualTheme = prefs.getString(_kVisualTheme);
    visualTheme = VisualTheme.values.firstWhere(
      (choice) => choice.name == savedVisualTheme,
      orElse: () => VisualTheme.palmWine,
    );
    avatarEmoji = prefs.getString(_kAvatarEmoji);
    avatarImagePath = prefs.getString(_kAvatarImage);
    voiceMatchEnabled = prefs.getBool(_kVoiceMatchEnabled) ?? false;
    voiceMatchThreshold = prefs.getDouble(_kVoiceMatchThreshold) ?? 0.8;
    final access = prefs.getString(_kAccess);
    if (access != null && access.isNotEmpty) {
      api.bearer = access;
      try {
        await _loadMe();
      } catch (_) {
        // The access token is short-lived (15 min) and expires long before the
        // refresh token (30 days) — on a normal cold start it's very likely
        // already expired, so a plain 401 here does NOT mean the session is
        // over. Only sign out if the refresh itself fails (refresh token
        // expired/revoked, or the account is gone).
        if (!await _tryRefresh()) await signOut();
      }
    }
    notifyListeners();
  }

  /// Exchanges the stored refresh token for a fresh pair and updates the
  /// session in place. Used both at cold-start recovery (above) and by
  /// `ApiClient` itself mid-session on any 401 (see `bootstrap`'s
  /// `api.refreshHandler = _tryRefresh` and `ApiClient._send`).
  Future<bool> _tryRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_kRefresh);
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final res =
          await api.post('/auth/refresh', {'refreshToken': refreshToken})
              as Map<String, dynamic>;
      await _completeSignIn(AuthTokens.fromJson(res));
      return true;
    } catch (_) {
      return false; // refresh token is dead too — caller decides what happens next
    }
  }

  Future<void> _loadMe() async {
    final me = await api.get('/me') as Map<String, dynamic>;
    user = UserView.fromJson(me);
    identity = user!.isGuest ? Identity.guest : Identity.account;
    _connectInbox();
    _ensurePublicKey();
    // Server avatar wins over a stale local pref once we know it (e.g. a
    // fresh reinstall, or a change made from another device).
    final serverIcon = user!.avatarUrl;
    if (serverIcon != null && !serverIcon.startsWith('http')) {
      avatarEmoji = serverIcon;
      avatarImagePath = null;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.name);
  }

  Future<void> setVisualTheme(VisualTheme choice) async {
    visualTheme = choice;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kVisualTheme, choice.name);
  }

  Future<void> setVoiceMatchEnabled(bool enabled) async {
    voiceMatchEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVoiceMatchEnabled, enabled);
  }

  Future<void> setVoiceMatchThreshold(double threshold) async {
    voiceMatchThreshold = threshold;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kVoiceMatchThreshold, threshold);
  }

  /// Pick one of the preset icons — clears any uploaded photo. Synced to the
  /// account (if signed in) so it follows the user to another device; a
  /// guest or an offline moment just keeps the local pref.
  Future<void> setAvatarEmoji(String emoji) async {
    avatarEmoji = emoji;
    avatarImagePath = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAvatarEmoji, emoji);
    await prefs.remove(_kAvatarImage);
    if (identity == Identity.account) {
      try {
        final res = await api.patch('/me', {'avatarEmoji': emoji})
            as Map<String, dynamic>;
        user = UserView.fromJson(res);
        notifyListeners();
      } catch (_) {
        // best-effort — the local pref already took effect
      }
    }
  }

  /// Change the account's username. Throws [ApiException] (e.g. 409 if taken)
  /// so the caller can show that error — there's no local fallback for this
  /// one since a username only means anything server-side.
  Future<void> setUsername(String username) async {
    final res =
        await api.patch('/me', {'username': username}) as Map<String, dynamic>;
    user = UserView.fromJson(res);
    notifyListeners();
  }

  Future<StatsView> fetchStats() async {
    final res = await api.get('/me/stats') as Map<String, dynamic>;
    return StatsView.fromJson(res);
  }

  Future<CoinTierInfo> fetchTier() async {
    final res = await api.get('/me/wallet') as Map<String, dynamic>;
    return CoinTierInfo.fromWallet(res);
  }

  Future<WalletInfo> fetchWallet({int limit = 30}) async {
    final res =
        await api.get('/me/wallet?limit=$limit') as Map<String, dynamic>;
    return WalletInfo.fromJson(res);
  }

  /// Use an uploaded photo — clears any preset icon.
  Future<void> setAvatarImage(String path) async {
    avatarImagePath = path;
    avatarEmoji = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAvatarImage, path);
    await prefs.remove(_kAvatarEmoji);
  }

  Future<void> clearAvatar() async {
    avatarEmoji = null;
    avatarImagePath = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAvatarEmoji);
    await prefs.remove(_kAvatarImage);
  }

  Future<void> completeAccountSignIn(AuthTokens tokens) =>
      _completeSignIn(tokens);

  /// Shared by every sign-in path (OTP, Google, refresh, guest) — sets the
  /// bearer, persists both tokens, and derives [identity] from what the
  /// server actually says the account is (`tokens.user.isGuest`) rather than
  /// the caller assuming it, so e.g. an OTP verify that upgraded a guest in
  /// place correctly flips this device from guest to account.
  Future<void> _completeSignIn(AuthTokens tokens) async {
    api.bearer = tokens.access;
    user = tokens.user;
    identity = tokens.user.isGuest ? Identity.guest : Identity.account;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccess, tokens.access);
    await prefs.setString(_kRefresh, tokens.refresh);
    _connectInbox();
    _ensurePublicKey();
    notifyListeners();
  }

  /// Full round trip: native Google account picker → ID token → `/auth/google`
  /// → the same `completeAccountSignIn` every other login path uses. Returns
  /// null if the user cancels the picker (not an error); throws otherwise —
  /// including [StateError] if GOOGLE_WEB_CLIENT_ID was omitted at build time.
  Future<AuthTokens?> signInWithGoogle() async {
    if (!isGoogleSignInConfigured) {
      throw StateError(
          'Google sign-in is not configured yet — see docs/DEV_REFERENCE.md');
    }
    final client = _googleClient ??= GoogleSignIn(
      scopes: const ['email'],
      // clientId is iOS/macOS-only (Android is configured via the registered
      // SHA-1 instead, and ignores this) — harmless to always pass it.
      clientId: kGoogleIosClientId,
      serverClientId: kGoogleWebClientId,
    );
    final googleUser = await client.signIn();
    if (googleUser == null) return null; // user cancelled the picker
    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw StateError(
          'Google did not return an ID token — check serverClientId matches the backend');
    }
    final res = await api.post('/auth/google', {'idToken': idToken})
        as Map<String, dynamic>;
    final tokens = AuthTokens.fromJson(res);
    await completeAccountSignIn(tokens);
    return tokens;
  }

  /// A real, server-known guest identity (POST /auth/guest) keyed by device id —
  /// can host/join real rooms like any account, just with no phone/email yet.
  /// Relaunching the app on the same device reconnects to this same identity
  /// (and its rooms) rather than minting a new guest every time. See
  /// `docs/DEV_REFERENCE.md` for the upgrade-in-place path (verifying a phone
  /// or email later attaches it to this same user id via `/otp/verify`).
  Future<void> startGuest(String nickname) async {
    final res = await api.post('/auth/guest', {
      'deviceId': api.deviceId,
      'displayName': nickname,
    }) as Map<String, dynamic>;
    await _completeSignIn(AuthTokens.fromJson(res));
  }

  Future<void> signOut() async {
    try {
      await _googleClient?.signOut();
    } catch (_) {
      // The app session can still be cleared if the provider is unavailable.
    }
    api.bearer = null;
    user = null;
    identity = Identity.anonymous;
    pendingGameInvite = null;
    await _inboxSub?.cancel();
    await inbox?.close();
    inbox = null;
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
