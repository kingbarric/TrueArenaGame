import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/playground_nav_pill.dart';
import '../chat/chat_list_screen.dart';
import '../friends/friends_screen.dart';
import '../home/home_screen.dart';
import '../onboarding/guest_gate.dart';
import '../profile/profile_screen.dart';
import '../spectate/spectator_discovery_screen.dart';

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

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _index = widget.initialIndex;
  static const _tabKey = 'ta_main_tab';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getInt(_tabKey);
      if (mounted && saved != null && saved >= 0 && saved < 5) {
        setState(() => _index = saved);
      }
    });
  }

  /// Built lazily and kept alive — a tab the user never opens costs nothing,
  /// and one they've opened doesn't reload every time they come back.
  final _built = <int, Widget>{};

  static const _tabs = [
    _Tab(icon: Icons.sports_esports_rounded, label: 'Games'),
    _Tab(icon: Icons.chat_bubble_rounded, label: 'Chats', needsAccount: true),
    _Tab(icon: Icons.people_alt_rounded, label: 'Friends', needsAccount: true),
    _Tab(icon: Icons.visibility_rounded, label: 'Watch', needsAccount: true),
    _Tab(icon: Icons.emoji_emotions_rounded, label: 'You'),
  ];

  Widget _screenFor(int i) => _built.putIfAbsent(i, () => switch (i) {
        0 => const HomeScreen(),
        1 => const ChatListScreen(),
        2 => const FriendsScreen(),
        3 => const SpectatorDiscoveryScreen(),
        _ => const ProfileScreen(),
      });

  Future<void> _select(int i) async {
    if (i == _index) return;
    // Guests can browse Home and their own profile, but the social tabs
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
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            // Must be `expand`: the default (StackFit.loose) hands children
            // unbounded constraints, which blows up any tab using Spacer /
            // Expanded / a full-width Container (i.e. all of them).
            sizing: StackFit.expand,
            children: [for (var i = 0; i < _tabs.length; i++) _screenFor(i)],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Center(
              child: SafeArea(
                top: false,
                child: PlaygroundNavPill(
                  activeIndex: _index,
                  items: [
                    for (var i = 0; i < _tabs.length; i++)
                      PlaygroundNavItem(icon: _tabs[i].icon, onTap: () => _select(i)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab {
  const _Tab({required this.icon, required this.label, this.needsAccount = false});
  final IconData icon;
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
