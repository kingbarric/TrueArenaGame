import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/app_state.dart';
import 'core/models.dart';
import 'core/push_notifications.dart';
import 'features/calls/incoming_call_screen.dart';
import 'features/shell/main_shell.dart';
import 'features/lobby/joined_room_screen.dart';
import 'features/onboarding/welcome_screen.dart';
import 'features/draughts/championships_screen.dart';
import 'theme/neon_theme.dart';
import 'widgets/neon.dart';

class TrueArenaApp extends StatelessWidget {
  const TrueArenaApp({super.key, required this.state});

  final AppState state;

  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'PlayHuud',
            debugShowCheckedModeBanner: false,
            theme: switch (state.visualTheme) {
              VisualTheme.palmWine => NeonTheme.light,
              VisualTheme.nebula => NeonTheme.nebulaLight,
              VisualTheme.supercar => NeonTheme.supercarLight,
            },
            darkTheme: switch (state.visualTheme) {
              VisualTheme.palmWine => NeonTheme.dark,
              VisualTheme.nebula => NeonTheme.nebulaDark,
              VisualTheme.supercar => NeonTheme.supercarDark,
            },
            themeMode: state.themeMode,
            home: state.identity != Identity.anonymous
                ? _ResumeGate(state: state)
                : const WelcomeScreen(),
            onGenerateRoute: (settings) {
              final match = RegExp(r'^/championships/([A-HJ-NP-Z2-9]{8})$', caseSensitive: false)
                  .firstMatch(settings.name ?? '');
              if (match == null) return null;
              final code = match.group(1)!.toUpperCase();
              state.pendingChampionshipCode = code;
              return MaterialPageRoute(builder: (_) => state.identity == Identity.anonymous
                  ? const WelcomeScreen() : ChampionshipsScreen(inviteCode: code));
            },
            builder: (context, child) {
              final content = DismissKeyboardOnOutsideTap(
                  child: _GameInviteOverlay(
                      state: state, child: child ?? const SizedBox.shrink()));
              if (state.visualTheme == VisualTheme.palmWine) return content;
              final design = context.neonDesign.kind;
              return DecoratedBox(
                decoration: BoxDecoration(
                    gradient: NeonTheme.backdrop(
                        design, Theme.of(context).brightness)),
                child: content,
              );
            },
          );
        },
      ),
    );
  }
}

/// App-wide: tapping anywhere that isn't a control, or starting to drag a
/// list, puts the keyboard away. Flutter only does this by default on
/// desktop/web, so on phones the keyboard stayed up after tapping out of a
/// search or text box.
///
/// Taps on buttons and fields still go to them (they win the gesture arena),
/// so a chat's send button keeps the keyboard up for the next message and
/// tapping from one field to another never flickers it closed.
class DismissKeyboardOnOutsideTap extends StatelessWidget {
  const DismissKeyboardOnOutsideTap({super.key, required this.child});

  final Widget child;

  static void _dismiss() => FocusManager.instance.primaryFocus?.unfocus();

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (n) {
        // Only a finger drag — not the scroll that brings a focused field
        // into view when the keyboard opens.
        if (n.dragDetails != null) _dismiss();
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismiss,
        child: child,
      ),
    );
  }
}

/// A "someone on your call just started a game" banner — see `InboxClient`/
/// `AppState.pendingGameInvite`. Lives above the whole routed app (via
/// `MaterialApp.builder`) rather than on any one screen, since a call can be
/// running while the viewer is anywhere in the app. Slides and fades in/out
/// rather than popping, per house style.
class _GameInviteOverlay extends StatefulWidget {
  const _GameInviteOverlay({required this.state, required this.child});
  final AppState state;
  final Widget child;

  @override
  State<_GameInviteOverlay> createState() => _GameInviteOverlayState();
}

class _GameInviteOverlayState extends State<_GameInviteOverlay> {
  bool _joining = false;

  static const _gameNames = {
    'truearena': 'Traitors',
    'wordbluff': 'Word Bluff',
    'draughts': 'Draughts',
    'chess': 'Chess',
    'goosi': 'Macala',
    'whot': 'Whot',
    'ludo': 'Ludo',
  };

  Future<void> _join(Map<String, dynamic> invite) async {
    setState(() => _joining = true);
    try {
      final res = await widget.state.api.post(
          '/rooms/join', {'code': invite['roomCode']}) as Map<String, dynamic>;
      widget.state.dismissGameInvite();
      final room = RoomView.fromJson(res);
      await widget.state.rememberActiveRoom(room.id);
      TrueArenaApp.navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => JoinedRoomScreen(room: room)));
    } on ApiException catch (e) {
      final ctx = TrueArenaApp.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.state.pendingGameInvite;
    final n = context.neon;
    final gameName =
        _gameNames[invite?['gameType']] ?? invite?['gameType'] ?? 'a game';
    return Stack(children: [
      widget.child,
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          child: AnimatedSlide(
            offset: invite == null ? const Offset(0, -1.4) : Offset.zero,
            duration: NeonMotion.overlay,
            curve: invite == null ? NeonMotion.exit : NeonMotion.enter,
            child: AnimatedOpacity(
              opacity: invite == null ? 0 : 1,
              // Fades over the same window it slides across, so it drifts in
              // as one movement instead of snapping solid then sliding.
              duration: NeonMotion.overlay,
              curve: invite == null ? NeonMotion.exit : NeonMotion.enter,
              child: invite == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                      // Frosted rather than a solid slab: the screen behind
                      // stays faintly visible, so this reads as a notification
                      // floating over the app rather than a bar bolted on.
                      child: NeonGlass(
                        borderRadius: BorderRadius.circular(18),
                        opacity: 0.86,
                        blur: 22,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Icon(Icons.sports_esports_rounded,
                                color: n.jade, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                        '${invite['hostName'] ?? 'Someone'} started $gameName',
                                        style: TextStyle(
                                            color: n.ink,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13)),
                                    Text('Tap to join',
                                        style: TextStyle(
                                            color: n.mute, fontSize: 11)),
                                  ]),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _joining
                                  ? null
                                  : widget.state.dismissGameInvite,
                              child: Text('Dismiss',
                                  style: TextStyle(color: n.mute)),
                            ),
                            FilledButton(
                              onPressed: _joining ? null : () => _join(invite),
                              child: Text(_joining ? '…' : 'Join'),
                            ),
                          ]),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Restore the last live room after a process restart. The server decides
/// whether it is still active; the saved room ID only tells us where to ask.
class _ResumeGate extends StatefulWidget {
  const _ResumeGate({required this.state});
  final AppState state;

  @override
  State<_ResumeGate> createState() => _ResumeGateState();
}

class _ResumeGateState extends State<_ResumeGate> {
  bool _checking = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  Future<void> _restore() async {
    // A cold-start notification tap (see PushNotifications) wins over the
    // ordinary "resume whatever game I was last in" flow below — the player
    // tapped something specific, that's where they meant to go.
    final pendingConversation = widget.state.pendingConversationId;
    if (pendingConversation != null) {
      widget.state.pendingConversationId = null;
      if (mounted) setState(() => _checking = false);
      await PushNotifications.openConversation(pendingConversation);
      return;
    }
    final pendingCall = widget.state.pendingIncomingCall;
    if (pendingCall != null) {
      widget.state.pendingIncomingCall = null;
      if (mounted) setState(() => _checking = false);
      // Opened from a call notification: ring here so it can be answered.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => IncomingCalls.present(pendingCall));
      return;
    }
    final pendingRoom = widget.state.pendingRoomId;
    if (pendingRoom != null) {
      widget.state.pendingRoomId = null;
      if (mounted) setState(() => _checking = false);
      await PushNotifications.openRoom(pendingRoom);
      return;
    }

    var roomId = widget.state.activeRoomId;
    try {
      if (roomId == null) {
        // An older build may have a live game but no saved room ID yet.
        final recovered = await widget.state.api.get('/rooms/active')
            .timeout(const Duration(seconds: 5));
        if (recovered is! Map) {
          if (mounted) setState(() => _checking = false);
          return;
        }
        roomId = recovered['id'] as String?;
        if (roomId == null) {
          if (mounted) setState(() => _checking = false);
          return;
        }
      }
      final raw = await widget.state.api.get('/rooms/$roomId') as Map<String, dynamic>;
      final room = RoomView.fromJson(raw);
      final isMember = room.members.any((member) => member.userId == widget.state.user?.id);
      if (!isMember || (room.status != 'lobby' && room.status != 'in_game')) {
        await widget.state.clearActiveRoom(roomId);
        if (mounted) setState(() => _checking = false);
        return;
      }
      await widget.state.rememberActiveRoom(room.id);
      if (!mounted) return;
      setState(() => _checking = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => JoinedRoomScreen(room: room)));
        }
      });
    } on ApiException catch (error) {
      if (error.status == 403 || error.status == 404) {
        await widget.state.clearActiveRoom(roomId);
        if (mounted) setState(() => _checking = false);
      } else if (mounted) {
        setState(() {
          if (roomId == null) {
            _checking = false;
          } else {
            _error = 'Could not check your game. Try again.';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (roomId == null) {
            _checking = false;
          } else {
            _error = 'Could not connect to your game. Try again.';
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checking) return const MainShell();
    return Scaffold(body: Center(child: _error == null
        ? const CircularProgressIndicator()
        : Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!),
            TextButton(onPressed: () {
              setState(() => _error = null);
              _restore();
            }, child: const Text('Retry')),
            TextButton(onPressed: () => setState(() => _checking = false),
                child: const Text('Go to home')),
          ])));
  }
}
