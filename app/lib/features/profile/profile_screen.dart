import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../notifications/notifications_screen.dart';
import '../onboarding/guest_save_session_card.dart';
import '../settings/settings_screen.dart';
import '../wallet/wallet_screen.dart';
import '../draughts/championships_screen.dart';
import '../competitive/competitive_api.dart';
import '../competitive/competitive_models.dart';
import '../competitive/player_profile_screen.dart';

/// Reached from Home by tapping the avatar/name row. Appearance is available
/// here, with the rest of the device preferences in [SettingsScreen].
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  StatsView? _stats;
  String? _statsError;
  List<Map<String, dynamic>> _championshipBadges = const [];
  CompetitiveProfile? _competitive;
  List<String> _ratedGames = const ['draughts'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) { _loadStats(); _loadBadges(); _loadCompetitive(); });
  }

  /// PlayHuud number, founding status, location and per-game ratings. Never
  /// blocks the rest of the profile — on failure the section just doesn't show.
  Future<void> _loadCompetitive() async {
    final app = AppScope.of(context);
    if (app.identity == Identity.anonymous) return;
    final api = CompetitiveApi(app.api);
    try {
      final results = await Future.wait([api.mine(), api.ratedGames()]);
      if (mounted) {
        setState(() {
          _competitive = results[0] as CompetitiveProfile;
          _ratedGames = results[1] as List<String>;
        });
      }
    } catch (_) {/* optional section */}
  }

  Future<void> _loadBadges() async {
    try {
      final rows = await AppScope.of(context).api.get('/championships/badges/mine') as List;
      if (mounted) {
        setState(() => _championshipBadges = rows
            .map((e) => (e as Map).cast<String, dynamic>()).toList());
      }
    } catch (_) { /* Badges do not block the rest of the profile. */ }
  }

  Future<void> _loadStats() async {
    final app = AppScope.of(context);
    if (app.identity == Identity.anonymous) return;
    try {
      final stats = await app.fetchStats();
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
      if (mounted) setState(() => _statsError = 'Could not load your stats');
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final app = AppScope.of(context);
    // Your own profile shows your username only; full names are shown to
    // you for friends, not for yourself.
    final isGuest = app.identity == Identity.guest;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Order: the player cards, then "complete your profile", then the
            // wallet, then everything else. (Photo, username, theme and sign
            // out live in Settings.)
            if (_competitive != null)
              CompetitiveRecordSection(
                key: const ValueKey('profile-competitive-record'),
                profile: _competitive!,
                own: true,
                ratedGames: _ratedGames,
                onChanged: _loadCompetitive,
                horizontalPadding: 0, // this list is already padded
                belowPrompt: Bouncy(
      pressScale: 0.98,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen())),
      child: NeonCard(
        accent: n.jade,
        child: Row(children: [
          Icon(Icons.diamond_rounded, color: n.jade, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Wallet', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('Coins, tier, and history', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
            ]),
          ),
          Icon(Icons.chevron_right, color: n.mute, size: 20),
        ]),
      ),
    ),
              )
            else
              Bouncy(
      pressScale: 0.98,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen())),
      child: NeonCard(
        accent: n.jade,
        child: Row(children: [
          Icon(Icons.diamond_rounded, color: n.jade, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Wallet', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('Coins, tier, and history', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
            ]),
          ),
          Icon(Icons.chevron_right, color: n.mute, size: 20),
        ]),
      ),
    ),
            const SizedBox(height: 28),
            if (_championshipBadges.isNotEmpty) ...[
              Text('CHAMPIONSHIP BADGES', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.gold)),
              const SizedBox(height: 8),
              ..._championshipBadges.map((badge) => Card(child: ListTile(
                leading: const Text('🏆', style: TextStyle(fontSize: 25)),
                title: Text('${badge['name']} Champion'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChampionshipDetailScreen(id: badge['championshipId'] as String))),
              ))),
              const SizedBox(height: 16),
            ],
            Text('MATCH HISTORY', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.gold)),
            const SizedBox(height: 12),
            if (isGuest) ...[
              const GuestSaveSessionCard(),
              const SizedBox(height: 12),
            ],
            if (_statsError != null)
              NeonCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_statsError!, style: TextStyle(color: n.danger, fontSize: 12)),
                  const SizedBox(height: 10),
                  NeonButton('Retry', style: NeonStyle.ghost, expand: false, onPressed: () {
                    setState(() => _statsError = null);
                    _loadStats();
                  }),
                ]),
              )
            else if (_stats == null)
              const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            else
              _statsGrid(n, _stats!),
          ],
        ),
      ),
    );
  }

  Widget _statsGrid(NeonColors n, StatsView s) {
    final winPct = (s.winRate * 100).round();
    return Column(
      children: [
        Row(children: [
          Expanded(child: _statTile(n, 'GAMES PLAYED', '${s.gamesPlayed}', n.gold)),
          const SizedBox(width: 10),
          Expanded(child: _statTile(n, 'WIN RATE', s.gamesPlayed == 0 ? '—' : '$winPct%', n.jade)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _statTile(n, 'AS TRAITOR', s.traitorGames == 0 ? '—' : '${s.traitorWins}/${s.traitorGames}', n.brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statTile(
              n,
              'AS FAITHFUL',
              (s.gamesPlayed - s.traitorGames) == 0
                  ? '—'
                  : '${s.wins - s.traitorWins}/${s.gamesPlayed - s.traitorGames}',
              n.gold,
            ),
          ),
        ]),
      ],
    );
  }

  Widget _statTile(NeonColors n, String label, String value, Color accent) => NeonCard(
        accent: accent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: n.mute, fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 26, color: accent)),
        ]),
      );
}
