import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/app_state.dart';
import 'core/models.dart';
import 'features/shell/main_shell.dart';
import 'features/lobby/joined_room_screen.dart';
import 'features/onboarding/welcome_screen.dart';
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
            title: 'Topskul',
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
                ? const MainShell()
                : const WelcomeScreen(),
            builder: (context, child) {
              final content = _GameInviteOverlay(
                  state: state, child: child ?? const SizedBox.shrink());
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
    'draughts': 'Draft',
    'goosi': 'Goosi',
    'whot': 'Whot'
  };

  Future<void> _join(Map<String, dynamic> invite) async {
    setState(() => _joining = true);
    try {
      final res = await widget.state.api.post(
          '/rooms/join', {'code': invite['roomCode']}) as Map<String, dynamic>;
      widget.state.dismissGameInvite();
      final room = RoomView.fromJson(res);
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
