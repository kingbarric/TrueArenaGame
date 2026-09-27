import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/coin_tier_badge.dart';
import '../../widgets/neon.dart';

/// Balance, tier progress, and recent ledger history — the destination
/// behind `ProfileScreen`'s "Wallet" card, and the natural home for the
/// coin tier system beyond just the profile-row badge.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Future<WalletInfo>? _future;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    // Start the request first, then assign it inside a *block*-bodied
    // setState. An arrow body (`setState(() => _future = ...)`) returns the
    // Future, which trips Flutter's "setState callback returned a Future"
    // assertion — and because that throws before the assignment lands, the
    // screen sat on its spinner forever instead of loading.
    final pending = AppScope.of(context).fetchWallet();
    setState(() {
      _future = pending;
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: SafeArea(
        child: FutureBuilder<WalletInfo>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError || !snap.hasData) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('Could not load your wallet', style: TextStyle(color: n.mid)),
                    const SizedBox(height: 12),
                    NeonButton('Retry', style: NeonStyle.ghost, expand: false, onPressed: _load),
                  ]),
                ),
              );
            }
            final wallet = snap.data!;
            return RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  _BalanceCard(wallet: wallet),
                  const SizedBox(height: 10),
                  _TierCard(tier: wallet.tier),
                  const SizedBox(height: 18),
                  Text('HISTORY', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.gold)),
                  const SizedBox(height: 8),
                  if (wallet.recent.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No coins earned yet — finish a match to start.',
                            textAlign: TextAlign.center, style: TextStyle(color: n.mute)),
                      ),
                    )
                  else
                    for (final tx in wallet.recent) _HistoryTile(tx: tx),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The big coin count — sized and colored like the "hero number" every
/// wallet-style screen leads with.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.wallet});
  final WalletInfo wallet;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: n.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kCabinetInk, width: 2.5),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 0, offset: Offset(3, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('BALANCE', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, letterSpacing: 2)),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Icon(Icons.monetization_on_rounded, color: n.jade, size: 26),
          const SizedBox(width: 8),
          Text('${wallet.balance}',
              style: GoogleFonts.baloo2(fontSize: 36, fontWeight: FontWeight.w700, color: n.ink, height: 1)),
        ]),
      ]),
    );
  }
}

/// Tier badge + progress bar toward the next tier — the same `CoinTierInfo`
/// the profile-row badge reads, just with room to show the "how far" story.
class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier});
  final CoinTierInfo tier;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final color = tierColor(tier.tier);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: n.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CoinTierBadge(info: tier),
          const Spacer(),
          Text('${tier.lifetimeCoins} lifetime', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: tier.progress.clamp(0, 1)),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 7,
              backgroundColor: n.line,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          tier.nextTier == null
              ? 'You\'ve reached the top tier — Legend.'
              : '${tier.coinsToNextTier} coins to ${tier.nextTier}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute),
        ),
      ]),
    );
  }
}

/// A compact ledger line so several coin changes remain visible at once.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.tx});
  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final positive = tx.delta > 0;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: n.line, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
      child: Row(children: [
        Icon(reasonIcon(tx.reason), size: 16, color: positive ? n.jade : n.danger),
        const SizedBox(width: 9),
        Expanded(
          child: Text(reasonLabel(tx.reason),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: n.ink, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Text(_relativeTime(tx.createdAt),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
        const SizedBox(width: 12),
        Text('${positive ? '+' : ''}${tx.delta}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: positive ? n.jade : n.danger,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
