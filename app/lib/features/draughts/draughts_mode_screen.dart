import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../onboarding/guest_gate.dart';
import '../competitive/leaderboard_screen.dart';
import 'championships_screen.dart';
import 'draughts_lobby_screen.dart';

/// The ways into Draughts — a classic match, a championship, or the rankings.
class DraughtsModeScreen extends StatelessWidget {
  const DraughtsModeScreen({super.key});

  Future<void> _openClassic(BuildContext context) async {
    if (!await canHostOrPromptToVerify(context) || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const DraughtsLobbyScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: const Text('Draughts')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Choose a mode',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            NeonCard(
              key: const ValueKey('draft-classic-mode'),
              onTap: () => _openClassic(context),
              child: Row(children: [
                Icon(Icons.sports_esports_outlined, color: n.gold, size: 34),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Classic 1 on 1',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Play a single match with a friend or bot.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: n.mid)),
                  ],
                )),
                Icon(Icons.chevron_right, color: n.mute),
              ]),
            ),
            const SizedBox(height: 12),
            NeonCard(
              key: const ValueKey('draft-championship-mode'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ChampionshipsScreen(
                  inviteCode: AppScope.of(context).pendingChampionshipCode,
                ),
              )),
              child: Row(children: [
                Icon(Icons.emoji_events_outlined, color: n.gold, size: 34),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Championship',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Enter or host a knockout tournament.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: n.mid)),
                  ],
                )),
                Icon(Icons.chevron_right, color: n.mute),
              ]),
            ),
            const SizedBox(height: 12),
            NeonCard(
              key: const ValueKey('draft-rankings'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const LeaderboardScreen(gameType: 'draughts'),
              )),
              child: Row(children: [
                Icon(Icons.leaderboard_rounded, color: n.gold, size: 34),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rankings',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Global, national, state and friends.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: n.mid)),
                  ],
                )),
                Icon(Icons.chevron_right, color: n.mute),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
