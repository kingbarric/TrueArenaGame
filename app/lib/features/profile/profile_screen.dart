import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../onboarding/phone_screen.dart';
import '../onboarding/sign_out.dart';
import '../settings/settings_screen.dart';
import '../wallet/wallet_screen.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
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

  Future<void> _editUsername(AppState app) async {
    final controller = TextEditingController(text: app.user?.username ?? '');
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.neon.panel,
      builder: (_) => _UsernameSheet(controller: controller),
    );
    if (result == null || result.isEmpty || !mounted) return;
    try {
      await app.setUsername(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().contains('409') ? 'That username is taken' : 'Could not update username')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final app = AppScope.of(context);
    final user = app.user;
    final name = user?.displayName ?? 'Player';
    final isGuest = app.identity == Identity.guest;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
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
            Center(
              child: Column(
                children: [
                  Avatar(name, size: 84, emoji: app.avatarEmoji, imagePath: app.avatarImagePath),
                  const SizedBox(height: 12),
                  Text(name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  if (isGuest)
                    Text('Guest — this device only', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute))
                  else
                    Bouncy(
                      onTap: () => _editUsername(app),
                      pressScale: 0.96,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('@${user?.username ?? '—'}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.gold, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 4),
                          Icon(Icons.edit, size: 13, color: n.mute),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
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
            Text('APPEARANCE',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: n.gold)),
            const SizedBox(height: 6),
            Text('Choose the look of your app and games.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: n.mid)),
            const SizedBox(height: 12),
            VisualThemePicker(
                value: app.visualTheme, onChanged: app.setVisualTheme),
            const SizedBox(height: 16),
            NeonSegmentedThemePicker(
                mode: app.themeMode, onChanged: app.setThemeMode),
            const SizedBox(height: 28),
            Text('MATCH HISTORY', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.gold)),
            const SizedBox(height: 12),
            if (isGuest) ...[
              NeonCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Verify a phone or email to keep this session — your games so far carry over, '
                      'and you can host new games from any device.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: n.mid)),
                  const SizedBox(height: 10),
                  NeonButton(
                    'Verify now',
                    style: NeonStyle.ghost,
                    expand: false,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PhoneScreen())),
                  ),
                ]),
              ),
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
            const SizedBox(height: 28),
            NeonButton(
              'Sign out',
              style: NeonStyle.ghost,
              onPressed: () => confirmSignOut(context, app),
            ),
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

class _UsernameSheet extends StatelessWidget {
  const _UsernameSheet({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 20, 22, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CHANGE USERNAME', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.gold)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 24,
            decoration: const InputDecoration(hintText: 'e.g. king_of_traitors', counterText: '', prefixIcon: Icon(Icons.alternate_email)),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          const SizedBox(height: 12),
          NeonButton('Save', onPressed: () => Navigator.of(context).pop(controller.text.trim())),
        ],
      ),
    );
  }
}
