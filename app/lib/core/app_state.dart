import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  /// Kept while a new invitee completes sign-in after opening a championship link.
  String? pendingChampionshipCode;
  AppState(this.api);

  final ApiClient api;

  /// Set by `main.dart` once `PushNotifications.init` resolves, so `AppState`
  /// can trigger the permission prompt/token registration (and its reverse on
  /// sign-out) without importing push_notifications.dart itself.
  VoidCallback? onSignedIn;
  // Awaited before the bearer token is cleared below, since unregistering
  // this device's push token needs to make one last authenticated call.
  Future<void> Function()? onSignedOut;

  /// Set from a cold-start notification tap (see `PushNotifications`) when
  /// the widget tree isn't ready yet — consumed once by `_ResumeGate` in
  /// app.dart, same "stash it, consume it once the app is actually up"
  /// shape as [pendingChampionshipCode].
  String? pendingConversationId;
  String? pendingRoomId;

  /// A call push tapped while the app was closed — rung once the app is up.
  Map<String, dynamic>? pendingIncomingCall;
  GoogleSignIn? _googleClient;

  Identity identity = Identity.anonymous;
  UserView? user;
  String? activeRoomId;
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
  /// `CALL_JOINED`/`CALL_LEFT` on it directly. `AppState` routes game-start
  /// notices to [pendingGameInvite] and incoming DMs to [chatMessages].
  InboxClient? inbox;
  final ValueNotifier<Set<String>> onlineFriends = ValueNotifier(<String>{});
  Timer? _presenceTimer;
  StreamSubscription? _inboxSub;
  Timer? _inboxRetry;
  int _inboxGeneration = 0;
  int _inboxRetrySeconds = 1;
  Map<String, dynamic>? pendingGameInvite;

  // Broadcast (not single-value like pendingGameInvite) — a chat list screen
  // and an open conversation screen may both be alive and both want every
  // `NEW_MESSAGE` push, so this fans out rather than holding "the latest".
  final _chatController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get chatMessages => _chatController.stream;

  /// Ringing and nudges from the inbox: `CALL_INCOMING`, `CALL_CANCELLED`,
  /// `CALL_DECLINED` and `NUDGE`, each as `{type, data}`.
  final _callController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get callEvents => _callController.stream;

  /// The Huud feed's live notices: `HUUD_CHALLENGE` (someone challenged
  /// you) and `HUUD_CHALLENGE_ANSWERED`, each as `{type, data}`.
  final _huudController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get huudEvents => _huudController.stream;

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
    final generation = ++_inboxGeneration;
    _inboxRetry?.cancel();
    _inboxRetry = null;
    _inboxSub?.cancel();
    inbox?.close();
    final client = InboxClient.connect(api);
    inbox = client;
    _inboxSub = client.envelopes.listen((env) {
      final payload = (env['payload'] as Map?)?.cast<String, dynamic>();
      if (payload?['type'] == 'GAME_STARTING') {
        pendingGameInvite = (payload!['data'] as Map).cast<String, dynamic>();
        notifyListeners();
      } else if (payload?['type'] == 'NEW_MESSAGE') {
        _chatController.add((payload!['data'] as Map).cast<String, dynamic>());
      } else if (const {'CALL_INCOMING', 'CALL_CANCELLED', 'CALL_DECLINED', 'NUDGE'}
          .contains(payload?['type'])) {
        _callController.add(payload!);
      } else if (const {'HUUD_CHALLENGE', 'HUUD_CHALLENGE_ANSWERED'}
          .contains(payload?['type'])) {
        _huudController.add(payload!);
      }
    }, onDone: () => _scheduleInboxReconnect(generation));
    client.ready.then((_) {
      if (generation == _inboxGeneration) {
        _inboxRetrySeconds = 1;
        // Reconcile messages sent while this device was offline.
        _chatController.add({'type': 'sync'});
      }
    }).catchError((Object _) {
      _scheduleInboxReconnect(generation);
    });
    _presenceTimer?.cancel();
    _refreshPresence();
    _presenceTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _refreshPresence());
  }

  Future<void> _refreshPresence() async {
    if (api.bearer == null) return;
    try {
      final result = await api.get('/friends/online') as List;
      if (api.bearer != null) {
        onlineFriends.value = result.map((id) => id.toString()).toSet();
      }
    } catch (_) {
      onlineFriends.value = <String>{};
    }
  }

  void _scheduleInboxReconnect(int generation) {
    if (generation != _inboxGeneration ||
        api.bearer == null ||
        _inboxRetry != null) {
      return;
    }
    final delay = _inboxRetrySeconds;
    _inboxRetrySeconds = (_inboxRetrySeconds * 2).clamp(1, 30);
    _inboxRetry = Timer(Duration(seconds: delay), () async {
      _inboxRetry = null;
      if (generation != _inboxGeneration || api.bearer == null) return;
      try {
        // Also renew an expired access token before opening the socket.
        await api.get('/me');
      } catch (_) {
        _scheduleInboxReconnect(generation);
        return;
      }
      // A token refresh already calls _connectInbox with the new token.
      if (generation == _inboxGeneration) _connectInbox();
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
  static const _kActiveRoom = 'ta_active_room';
  static const _kActiveRoomUser = 'ta_active_room_user';
  static const _kActiveRoomSavedAt = 'ta_active_room_saved_at';
  static const _kCachedUser = 'ta_cached_user';
  static const _roomResumeWindow = Duration(days: 7);
  static const _secure = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> _readSessionSecret(
      String key, SharedPreferences prefs) async {
    try {
      final secureValue = await _secure.read(key: key);
      if (secureValue != null && secureValue.isNotEmpty) return secureValue;
      final legacyValue = prefs.getString(key);
      if (legacyValue != null && legacyValue.isNotEmpty) {
        await _secure.write(key: key, value: legacyValue);
        await prefs.remove(key);
      }
      return legacyValue;
    } catch (_) {
      // Widget tests and unsupported platforms may not provide the secure
      // storage plugin. Retain the legacy store as a functional fallback.
      return prefs.getString(key);
    }
  }

  Future<void> _writeSessionSecret(
      String key, String value, SharedPreferences prefs) async {
    try {
      await _secure.write(key: key, value: value);
      await prefs.remove(key);
    } catch (_) {
      await prefs.setString(key, value);
    }
  }

  Future<void> _deleteSessionSecret(String key, SharedPreferences prefs) async {
    try {
      await _secure.delete(key: key);
    } catch (_) {
      // Still clear the fallback below.
    }
    await prefs.remove(key);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPresence();
      if (api.bearer != null) _chatController.add({'type': 'sync'});
      inbox?.send('APP_FOREGROUND');
    }
    if (state == AppLifecycleState.paused) {
      // The inbox socket itself usually survives backgrounding for a while —
      // this is just the "don't count me as actively looking" signal, so
      // PushNotificationService.sendToUserIfOffline still sends an OS push
      // instead of assuming the live in-app frame was enough.
      inbox?.send('APP_BACKGROUND');
      if (activeRoomId != null) {
        SharedPreferences.getInstance().then((prefs) => prefs.setInt(
            _kActiveRoomSavedAt, DateTime.now().millisecondsSinceEpoch));
      }
    }
  }

  Future<void> rememberActiveRoom(String roomId) async {
    final userId = user?.id;
    if (userId == null) return;
    activeRoomId = roomId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveRoom, roomId);
    await prefs.setString(_kActiveRoomUser, userId);
    await prefs.setInt(
        _kActiveRoomSavedAt, DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
  }

  Future<void> clearActiveRoom([String? roomId]) async {
    if (roomId != null && activeRoomId != roomId) return;
    activeRoomId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kActiveRoom);
    await prefs.remove(_kActiveRoomUser);
    await prefs.remove(_kActiveRoomSavedAt);
    notifyListeners();
  }

  Future<void> bootstrap() async {
    WidgetsBinding.instance.addObserver(this);
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
    final access = await _readSessionSecret(_kAccess, prefs);
    if (access != null && access.isNotEmpty) {
      api.bearer = access;
      try {
        await _loadMe();
      } on ApiException catch (error) {
        if (error.status == 401) {
          // ApiClient already tried the stored refresh token. A final 401
          // means the account session is no longer valid.
          await signOut();
        } else {
          _restoreCachedUser(prefs);
        }
      } catch (_) {
        // A temporary network outage must not erase a month-long session or
        // the room the player intends to resume.
        _restoreCachedUser(prefs);
      }
    }
    final savedRoom = prefs.getString(_kActiveRoom);
    final savedAt = prefs.getInt(_kActiveRoomSavedAt);
    if (savedRoom != null &&
        user?.id == prefs.getString(_kActiveRoomUser) &&
        savedAt != null &&
        DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(savedAt)) <=
            _roomResumeWindow) {
      activeRoomId = savedRoom;
    } else if (savedRoom != null) {
      await clearActiveRoom();
    }
    notifyListeners();
  }

  /// Exchanges the stored refresh token for a fresh pair and updates the
  /// session in place. Used both at cold-start recovery (above) and by
  /// `ApiClient` itself mid-session on any 401 (see `bootstrap`'s
  /// `api.refreshHandler = _tryRefresh` and `ApiClient._send`).
  Future<bool> _tryRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = await _readSessionSecret(_kRefresh, prefs);
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
    await _cacheUser(user!);
    _connectInbox();
    _ensurePublicKey();
    onSignedIn?.call();
    // Server avatar wins over a stale local pref once we know it (e.g. a
    // fresh reinstall, or a change made from another device).
    final serverIcon = user!.avatarUrl;
    if (serverIcon != null &&
        !serverIcon.startsWith('http') &&
        !serverIcon.startsWith('data:image/')) {
      avatarEmoji = serverIcon;
      avatarImagePath = null;
    } else if (serverIcon?.startsWith('data:image/') == true) {
      avatarEmoji = null;
      avatarImagePath = null;
    }
  }

  Future<void> _cacheUser(UserView value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kCachedUser,
        jsonEncode({
          'id': value.id,
          'displayName': value.displayName,
          'username': value.username,
          'phone': value.phone,
          'email': value.email,
          'avatarUrl': value.avatarUrl,
          'isGuest': value.isGuest,
        }));
  }

  void _restoreCachedUser(SharedPreferences prefs) {
    final raw = prefs.getString(_kCachedUser);
    if (raw == null) return;
    try {
      user = UserView.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      identity = user!.isGuest ? Identity.guest : Identity.account;
    } catch (_) {
      // Ignore a damaged cache; the server remains the source of truth.
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
    // ImagePicker returns a temporary path on iOS. Keep a private copy so the
    // chosen photo is still there after the OS clears its cache.
    final directory = await getApplicationSupportDirectory();
    final extension = path.split('.').last.toLowerCase();
    final safeExtension =
        {'jpg', 'jpeg', 'png', 'heic', 'webp'}.contains(extension)
            ? extension
            : 'jpg';
    final saved = await File(path).copy(
        '${directory.path}/profile_${DateTime.now().microsecondsSinceEpoch}.$safeExtension');
    avatarImagePath = saved.path;
    avatarEmoji = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAvatarImage, saved.path);
    await prefs.remove(_kAvatarEmoji);
    if (identity == Identity.account) {
      final bytes = await saved.readAsBytes();
      if (bytes.length > 110000) {
        throw StateError(
            'That photo is too large to sync. Please choose a smaller one.');
      }
      final mime = bytes.length > 7 && bytes[0] == 0x89 && bytes[1] == 0x50
          ? 'png'
          : bytes.length > 11 && bytes[0] == 0x52 && bytes[8] == 0x57
              ? 'webp'
              : 'jpeg';
      final data = 'data:image/$mime;base64,${base64Encode(bytes)}';
      final response = await api.patch('/me', {'avatarImageData': data})
          as Map<String, dynamic>;
      user = UserView.fromJson(response);
      notifyListeners();
    }
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
    await _writeSessionSecret(_kAccess, tokens.access, prefs);
    await _writeSessionSecret(_kRefresh, tokens.refresh, prefs);
    await _cacheUser(tokens.user);
    _connectInbox();
    _ensurePublicKey();
    onSignedIn?.call();
    notifyListeners();
  }

  /// Full round trip: native Google account picker → ID token → `/auth/google`
  /// → the same `completeAccountSignIn` every other login path uses. Returns
  /// null if the user cancels the picker (not an error); throws otherwise —
  /// including [StateError] if the Web client ID is invalid.
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

  /// Native iOS Apple sheet, with a one-use nonce issued and consumed by our
  /// backend. The backend verifies Apple's signature before creating a session.
  Future<AuthTokens> signInWithApple() async {
    final challenge =
        await api.post('/auth/apple/challenge', {}) as Map<String, dynamic>;
    final nonce = challenge['nonce'] as String;
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );
    final idToken = credential.identityToken;
    if (idToken == null) {
      throw StateError('Apple did not return an identity token');
    }
    final response = await api.post('/auth/apple', {
      'idToken': idToken,
      'nonce': nonce,
    }) as Map<String, dynamic>;
    final tokens = AuthTokens.fromJson(response);
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
    if (onSignedOut != null) await onSignedOut!(); // before api.bearer is cleared below
    try {
      await _googleClient?.signOut();
    } catch (_) {
      // The app session can still be cleared if the provider is unavailable.
    }
    api.bearer = null;
    ++_inboxGeneration;
    _inboxRetry?.cancel();
    _inboxRetry = null;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    onlineFriends.value = <String>{};
    user = null;
    identity = Identity.anonymous;
    await clearActiveRoom();
    pendingGameInvite = null;
    await _inboxSub?.cancel();
    await inbox?.close();
    inbox = null;
    final prefs = await SharedPreferences.getInstance();
    await _deleteSessionSecret(_kAccess, prefs);
    await _deleteSessionSecret(_kRefresh, prefs);
    await prefs.remove(_kCachedUser);
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    onlineFriends.dispose();
    super.dispose();
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
