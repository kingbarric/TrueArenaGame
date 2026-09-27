import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/neon_theme.dart';

/// Status tier over lifetime coins earned — mirrors backend `CoinTier`
/// (`ta-api/.../coins/CoinTier.java`), never derived independently here.
/// Tier only ever goes up (lifetime coins, not current balance), so the
/// badge reads as a permanent status symbol, not a fluctuating wallet
/// number — parsed straight out of `GET /me/wallet`'s `tier` object.
class CoinTierInfo {
  const CoinTierInfo(this.tier, this.lifetimeCoins, this.nextTier, this.coinsToNextTier, this.progress);

  final String tier;
  final int lifetimeCoins;
  final String? nextTier;
  final int? coinsToNextTier;
  final double progress;

  static CoinTierInfo fromWallet(Map<String, dynamic> json) {
    final t = json['tier'] as Map<String, dynamic>;
    return CoinTierInfo(
      t['tier'] as String,
      (t['lifetimeCoins'] as num).toInt(),
      t['nextTier'] as String?,
      (t['coinsToNextTier'] as num?)?.toInt(),
      (t['tierProgress'] as num).toDouble(),
    );
  }
}

// Same ladder as CoinTier.java, colored as a rising sequence (dull → warm
// metal → jewel tones) so the badge itself reads "how far up" at a glance,
// not just its label.
const Map<String, Color> _tierColors = {
  'Rookie': Color(0xFF9C8A82),
  'Rising Star': Color(0xFF7FD1D1),
  'Rose': Color(0xFFE8879B),
  'Bronze': Color(0xFFB08050),
  'Silver': Color(0xFFCCCCC4),
  'Gold': Color(0xFFF0C242),
  'Platinum': Color(0xFF7FE0C9),
  'Diamond': Color(0xFF6FD3FF),
  'Crown': Color(0xFFFFB03A),
  'Legend': Color(0xFFFF7A5C),
};

Color tierColor(String tier) => _tierColors[tier] ?? _tierColors['Rookie']!;

class WalletTransaction {
  const WalletTransaction(this.delta, this.balanceAfter, this.reason, this.createdAt);

  final int delta;
  final int balanceAfter;
  final String reason;
  final DateTime createdAt;

  factory WalletTransaction.fromJson(Map<String, dynamic> j) => WalletTransaction(
        (j['delta'] as num).toInt(),
        (j['balanceAfter'] as num).toInt(),
        j['reason'] as String,
        DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

// Mirrors CoinService's reason constants — a human label + icon per reason
// so the ledger reads as a story ("won a match", "hired a Cyber Agent")
// rather than raw enum strings.
const Map<String, String> _reasonLabels = {
  'match_win': 'Match won',
  'match_loss': 'Match played',
  'match_tie': 'Match tied',
  'bot_added': 'Cyber Agent hired',
};

const Map<String, IconData> _reasonIcons = {
  'match_win': Icons.emoji_events_rounded,
  'match_loss': Icons.sports_esports_rounded,
  'match_tie': Icons.handshake_rounded,
  'bot_added': Icons.smart_toy_rounded,
};

String reasonLabel(String reason) => _reasonLabels[reason] ?? reason;
IconData reasonIcon(String reason) => _reasonIcons[reason] ?? Icons.swap_horiz_rounded;

class WalletInfo {
  const WalletInfo(this.balance, this.tier, this.recent);

  final int balance;
  final CoinTierInfo tier;
  final List<WalletTransaction> recent;

  factory WalletInfo.fromJson(Map<String, dynamic> j) => WalletInfo(
        (j['balance'] as num).toInt(),
        CoinTierInfo.fromWallet(j),
        ((j['recent'] as List?) ?? const [])
            .map((e) => WalletTransaction.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// A small pill badge — tier name on a color-coded chip, tap-through to
/// show the coins-to-next-tier line. Kept intentionally compact so it drops
/// straight into the profile row next to the avatar without a bespoke
/// wallet screen (that's a separate, larger build).
class CoinTierBadge extends StatelessWidget {
  const CoinTierBadge({super.key, required this.info});

  final CoinTierInfo info;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final color = tierColor(info.tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.diamond_rounded, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            info.tier.toUpperCase(),
            style: GoogleFonts.baloo2(
              fontSize: 11,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: n.mid,
            ),
          ),
        ],
      ),
    );
  }
}
