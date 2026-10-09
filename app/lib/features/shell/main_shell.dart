import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_state.dart';
import '../../core/push_notifications.dart';
import '../../widgets/hide_on_scroll_nav.dart';
import '../../widgets/playground_nav_pill.dart';
import '../friends/friends_screen.dart';
import '../home/home_screen.dart';
import '../huud/huud_screen.dart';
import '../huudspace/huud_home_screen.dart';
import '../huudspace/huud_kit.dart' show huudIcon, huudIconSnack;
import '../onboarding/guest_gate.dart';
import '../profile/profile_screen.dart';

/// The app's persistent nav shell. Before this, the pill nav lived only on
/// Home and everything else was a pushed route, so reaching Chats from
/// Friends (or anything from anything) meant backing all the way out to
/// Home first. Now the five primary destinations live in an [IndexedStack]
/// under one always-visible pill — switching is instant, each tab keeps its
/// own scroll position and loaded state, and every destination is one tap
/// from every other.
///
/// Deeper screens (a conversation, a lobby, a call, the wallet) are still
/// pushed on top of the shell, which is the right split: they're
/// full-attention screens, not destinations you flip between.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  /// Live (what's on now + the feed), for anything that wants to open it — a
  /// challenge push tapped while the app was in the background.
  static const liveTab = 0;

  /// Making a Huud and your Huud history.
  static const huudSpacesTab = 1;

  /// The game catalogue.
  static const gamesTab = 2;

  /// Friends, messages and friend requests.
  static const friendsTab = 3;

  /// Set from outside the widget tree — a push tap only has the root
  /// navigator — and picked up by whichever shell is mounted.
  static final requestedTab = ValueNotifier<int?>(null);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _index = widget.initialIndex;
  // v4: Live · Huud · Games · Friends · You (Chats moved inside Friends),
  // which shifted every saved index — a fresh key rather than reopening
  // someone on the tab next to theirs.
  static const _tabKey = 'ta_main_tab_v4';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getInt(_tabKey);
      if (mounted && saved != null && saved >= 0 && saved < _tabs.length) {
        setState(() => _index = saved);
      }
    });
    MainShell.requestedTab.addListener(_onTabRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onTabRequested();
      _huudEvents = AppScope.of(context).huudSpaceEvents.listen(_onHuudEvent);
    });
  }

  StreamSubscription? _huudEvents;

  static const _bannerFor = {
    'invited': "You're invited to a Huud!",
    'request': 'Someone is asking you something in your Huud ✋',
    'accepted-join': "You're in! The host let you into the Huud",
    'picked': "You're picked to play! Open the Huud and press Ready 🎮",
  };

  /// Invites, requests and answers while you're on the main tabs — inside a
  /// Huud its own screen says so.
  void _onHuudEvent(Map<String, dynamic> event) {
    final data = (event['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final text = _bannerFor[data['event']];
    final id = data['huudSpaceId'] as String?;
    if (text == null || id == null || !mounted || ModalRoute.of(context)?.isCurrent != true) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          huudIconSnack(text, action: SnackBarAction(label: 'Open', onPressed: () => PushNotifications.openHuud(id))));
  }

  @override
  void dispose() {
    MainShell.requestedTab.removeListener(_onTabRequested);
    _huudEvents?.cancel();
    super.dispose();
  }

  void _onTabRequested() {
    final requested = MainShell.requestedTab.value;
    if (requested == null || !mounted) return;
    MainShell.requestedTab.value = null;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _select(requested);
  }

  /// Built lazily and kept alive — a tab the user never opens costs nothing,
  /// and one they've opened doesn't reload every time they come back.
  final _built = <int, Widget>{};

  static const _tabs = [
    _Tab(icon: Icons.live_tv_rounded, label: 'Live'),
    _Tab(icon: Icons.groups_rounded, label: 'Huud', image: huudIcon),
    _Tab(icon: Icons.sports_esports_rounded, label: 'Games'),
    _Tab(icon: Icons.people_alt_rounded, label: 'Friends', needsAccount: true),
    _Tab(icon: Icons.emoji_emotions_rounded, label: 'You'),
  ];

  Widget _screenFor(int i) => _built.putIfAbsent(
      i,
      () => switch (i) {
            0 => const HuudScreen(),
            1 => const HuudHomeScreen(),
            2 => const HomeScreen(),
            3 => const FriendsScreen(),
            _ => const ProfileScreen(),
          });

  Future<void> _select(int i) async {
    if (i == _index) return;
    // Guests can browse Home, the Huud lobby and their own profile, but the social tabs
    // need a verified account — prompt once here rather than letting them
    // land on an empty screen and wonder why.
    if (_tabs[i].needsAccount && !await canUseFriendsOrPromptToVerify(context)) return;
    if (!mounted) return;
    setState(() => _index = i);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_tabKey, i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The menu slides away while you scroll down and returns when you
      // scroll up; switching tabs always brings it back.
      body: HideOnScrollNav(
        resetKey: _index,
        body: IndexedStack(
          index: _index,
          // Must be `expand`: the default (StackFit.loose) hands children
          // unbounded constraints, which blows up any tab using Spacer /
          // Expanded / a full-width Container (i.e. all of them).
          sizing: StackFit.expand,
          children: [for (var i = 0; i < _tabs.length; i++) _screenFor(i)],
        ),
        nav: Center(
          child: SafeArea(
            top: false,
            // Labelled tabs — shrink rather than overflow on the narrowest phones.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: PlaygroundNavPill(
                  activeIndex: _index,
                  items: [
                    for (var i = 0; i < _tabs.length; i++)
                      PlaygroundNavItem(
                          icon: _tabs[i].icon, label: _tabs[i].label, image: _tabs[i].image, onTap: () => _select(i)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab {
  const _Tab({required this.icon, required this.label, this.needsAccount = false, this.image});
  final IconData icon;
  final String? image;
  final String label;
  final bool needsAccount;
}

/// Jump the shell to one of its tabs from anywhere below it (a lobby's
/// "back to chats", a conversation's "see friends"). Falls back to a plain
/// pop when the shell isn't an ancestor, so a screen that's also reachable
/// outside the shell doesn't have to care.
void goToShellTab(BuildContext context, int index) {
  final shell = context.findAncestorStateOfType<_MainShellState>();
  if (shell == null) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    return;
  }
  Navigator.of(context).popUntil((r) => r.isFirst);
  shell._select(index);
}
