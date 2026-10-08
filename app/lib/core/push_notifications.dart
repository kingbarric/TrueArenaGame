import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../app.dart';
import '../features/calls/incoming_call_screen.dart';
import '../features/chat/conversation_screen.dart';
import '../features/lobby/joined_room_screen.dart';
import '../features/huud/social_huud_entry.dart';
import '../features/huud/social_huud_screen.dart';
import '../features/shell/main_shell.dart';
import 'app_state.dart';
import 'models.dart';

/// OS push notifications (new messages, game invites, turn reminders,
/// admin broadcasts) via Firebase Cloud Messaging — FCM bridges to APNs for
/// iOS, so this is the one integration point for both platforms. See
/// `ChatService.pushNewMessage`, `GameOrchestrator.pushTurnReminders`, and
/// the admin broadcast composer on the backend for where these originate.
class PushNotifications {
  PushNotifications._(this._app);

  final AppState _app;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static const _channelId = 'playhuud_default';

  /// False until Firebase has actually initialized — true as soon as this
  /// app has `google-services.json`/`GoogleService-Info.plist` configured.
  /// Every other method is a no-op while this is false, so a device without
  /// Firebase set up yet just runs with push silently off, not crashed.
  bool _available = false;

  static Future<PushNotifications> init(AppState app) async {
    final pn = PushNotifications._(app);
    try {
      await Firebase.initializeApp();
      await pn._initLocalNotifications();

      FirebaseMessaging.onMessage.listen(pn._showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(pn._openNow);
      FirebaseMessaging.instance.onTokenRefresh.listen(pn._sendTokenToBackend);

      // Cold start via a notification tap: the widget tree isn't necessarily
      // ready yet, so this stashes the target on AppState instead of
      // navigating directly — see _ResumeGate in app.dart, which consumes
      // pendingConversationId/pendingRoomId once the app is actually up.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) pn._stashPending(initial.data);
      pn._available = true;
    } catch (_) {
      // No Firebase config on this build yet (no google-services.json /
      // GoogleService-Info.plist) — push stays off instead of blocking launch.
    }
    return pn;
  }

  Future<void> _initLocalNotifications() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      'PlayHuud',
      description: 'Messages, game invites, turn reminders, and announcements',
      importance: Importance.high,
    );
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(channel);
    // Calls get their own loud channel — the server sends call pushes on
    // "incoming_calls" so they ring and buzz even when other alerts are quiet.
    await android?.createNotificationChannel(AndroidNotificationChannel(
      'incoming_calls',
      'Incoming calls',
      description: 'Rings and vibrates when a friend calls you',
      importance: Importance.max,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 900, 600, 900, 600, 900]),
    ));
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      // Tapping a *local* notification only ever happens while the app is
      // already running (that's the whole reason _showForeground exists) —
      // so this opens directly, same as a warm FCM tap, never stashes.
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        open((jsonDecode(payload) as Map).cast<String, dynamic>());
      },
    );
  }

  /// Called right after a successful sign-in or session resume (the same two
  /// call sites `AppState._ensurePublicKey` fires from) — not during
  /// onboarding, matching this app's existing "ask at the point of use"
  /// convention for permissions (contacts, mic).
  Future<void> requestPermissionAndRegister() async {
    if (!_available) return;
    try {
      final settings = await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _sendTokenToBackend(token);
    } catch (_) {
      // best-effort — a later app resume tries again via onTokenRefresh/init
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      await _app.api.post('/devices/token', {
        'platform': Platform.isIOS ? 'ios' : 'android',
        'token': token,
      });
    } catch (_) {
      // next successful launch retries — see requestPermissionAndRegister
    }
  }

  /// Called on sign-out so a shared/resold device stops getting the
  /// previous user's pushes. Always invalidates the token locally via
  /// `deleteToken()`, even if the server-side unregister call fails (network
  /// drop, offline sign-out) — otherwise a failed DELETE would leave the old
  /// account's token live server-side, and message previews / game invites
  /// could keep reaching this device after someone else signs in on it.
  /// `deleteToken()` makes the token itself unusable going forward, and the
  /// next send attempt prunes the stale row server-side either way.
  Future<void> unregisterCurrentToken() async {
    if (!_available) return;
    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _app.api.delete('/devices/token', {'token': token});
      }
    } catch (_) {
      // server call failed — still fall through to the local deleteToken() below
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // best-effort — a device that can't even reach Firebase to delete its
      // own token locally is thoroughly offline and isn't receiving pushes anyway
    }
  }

  /// FCM doesn't auto-display a system banner for a foregrounded app on
  /// Android (iOS can via setForegroundNotificationPresentationOptions, but
  /// one code path for both is simpler) — this matters most for broadcasts,
  /// which are sent regardless of whether the recipient is online.
  void _showForeground(RemoteMessage message) {
    // Calls and nudges have their own in-app treatment — a ringing screen,
    // a buzz — rather than a banner.
    final type = message.data['type'];
    if (type == 'INCOMING_CALL') {
      IncomingCalls.present(message.data.cast<String, dynamic>());
      return;
    }
    if (type == 'NUDGE') {
      IncomingCalls.nudged(message.data['fromName'] as String? ?? 'A friend');
      return;
    }
    final notification = message.notification;
    if (notification == null) return;
    _local.show(
      id: message.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(_channelId, 'PlayHuud',
            importance: Importance.high, priority: Priority.high),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// The app was backgrounded, not killed — the navigator is already live,
  /// so this jumps straight there instead of stashing anything.
  void _openNow(RemoteMessage message) => open(message.data);

  void _stashPending(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'NEW_MESSAGE' || type == 'GAME_INVITE') {
      _app.pendingConversationId = data['conversationId'] as String?;
    } else if (type == 'YOUR_TURN') {
      _app.pendingRoomId = data['roomId'] as String?;
    } else if (type == 'INCOMING_CALL') {
      _app.pendingIncomingCall = data;
    } else if (type == 'HUUD_CHALLENGE' || type == 'HUUD_CHALLENGE_ANSWERED') {
      // Read by MainShell when it first mounts.
      MainShell.requestedTab.value = MainShell.huudTab;
    }
    // BROADCAST: no deep link — the app just opens normally.
  }

  /// Routes a push/local-notification payload to its destination screen —
  /// shared by the tap handlers above and the Notifications page, which
  /// re-sends the same `data` a tapped history row originally carried.
  static Future<void> open(Map<String, dynamic> data) async {
    final type = data['type'];
    if (type == 'NEW_MESSAGE' || type == 'GAME_INVITE') {
      final conversationId = data['conversationId'] as String?;
      if (conversationId != null) await openConversation(conversationId);
    } else if (type == 'YOUR_TURN') {
      final roomId = data['roomId'] as String?;
      if (roomId != null) await openRoom(roomId);
    } else if (type == 'INCOMING_CALL') {
      IncomingCalls.present(data);
    } else if (type == 'HUUD_CHALLENGE' || type == 'HUUD_CHALLENGE_ANSWERED') {
      // The challenge card (Accept / Not now) lives at the top of Your Huud.
      MainShell.requestedTab.value = MainShell.huudTab;
    }
  }

  /// Shared by the push tap handlers and _ResumeGate's cold-start
  /// consumption — fetches just enough to render the destination, same
  /// endpoints the rest of the app already uses to get there.
  static Future<void> openConversation(String conversationId) async {
    final nav = TrueArenaApp.navigatorKey.currentState;
    final ctx = TrueArenaApp.navigatorKey.currentContext;
    if (nav == null || ctx == null) return;
    try {
      final app = AppScope.of(ctx);
      final raw = await app.api.get('/conversations/$conversationId') as Map<String, dynamic>;
      final other = raw['other'] as Map<String, dynamic>?;
      final title = (raw['type'] == 'dm'
              ? (other?['displayName'] as String?) ?? (other?['username'] as String?)
              : raw['groupName'] as String?) ??
          'Chat';
      nav.push(MaterialPageRoute(
          builder: (_) => ConversationScreen(conversationId: conversationId, title: title)));
    } catch (_) {
      // conversation may have been deleted, or the request failed — nothing to recover into
    }
  }

  static Future<void> openRoom(String roomId) async {
    final nav = TrueArenaApp.navigatorKey.currentState;
    final ctx = TrueArenaApp.navigatorKey.currentContext;
    if (nav == null || ctx == null) return;
    try {
      final app = AppScope.of(ctx);
      final raw = await app.api.get('/rooms/$roomId') as Map<String, dynamic>;
      final room = RoomView.fromJson(raw);
      final social = await socialHuudForRoom(app.api, room.id);
      await app.rememberActiveRoom(room.id);
      nav.push(MaterialPageRoute(builder: (_) => social == null
          ? JoinedRoomScreen(room: room) : SocialHuudScreen(initial: social)));
    } catch (_) {
      // room may have ended, or the request failed — nothing to recover into
    }
  }
}
