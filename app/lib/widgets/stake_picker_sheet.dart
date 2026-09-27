import 'package:flutter/material.dart';

import '../theme/neon_theme.dart';
import 'neon.dart';

/// The "wager or not" choice shown before creating a staked-capable room —
/// staking is opt-in per room, never required, so "Play for free" is always
/// the first and most prominent option. Returns the chosen stake (0 for
/// unstaked) or null if the sheet was dismissed without a choice.
Future<int?> showStakePicker(BuildContext context, {required int currentBalance}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StakePickerSheet(currentBalance: currentBalance),
  );
}

const _presets = [0, 50, 100, 250, 500];

class _StakePickerSheet extends StatefulWidget {
  const _StakePickerSheet({required this.currentBalance});
  final int currentBalance;

  @override
  State<_StakePickerSheet> createState() => _StakePickerSheetState();
}

class _StakePickerSheetState extends State<_StakePickerSheet> {
  int _picked = 0;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final canAfford = widget.currentBalance >= _picked;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.viewInsetsOf(context).bottom + 28),
      decoration: BoxDecoration(color: n.panel.withValues(alpha: 0.9), borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(width: 40, height: 4, decoration: BoxDecoration(color: n.line, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 18),
        Text('WAGER COINS?', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, letterSpacing: 2)),
        const SizedBox(height: 4),
        Text('Optional — everyone who joins stakes the same amount, winner takes the pot.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.monetization_on_rounded, size: 14, color: n.jade),
          const SizedBox(width: 4),
          Text('Balance: ${widget.currentBalance}', style: TextStyle(color: n.mute, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final amount in _presets) _StakeChip(amount: amount, selected: _picked == amount, onTap: () => setState(() => _picked = amount)),
          ],
        ),
        const SizedBox(height: 20),
        if (!canAfford)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Not enough coins for that stake.', style: TextStyle(color: n.danger, fontSize: 12)),
          ),
        NeonButton(
          _picked == 0 ? 'Play for free' : 'Stake $_picked coins',
          onPressed: canAfford ? () => Navigator.of(context).pop(_picked) : null,
        ),
      ]),
    );
  }
}

class _StakeChip extends StatelessWidget {
  const _StakeChip({required this.amount, required this.selected, required this.onTap});
  final int amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Bouncy(
      pressScale: 0.94,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? n.jade.withValues(alpha: 0.18) : n.bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? n.jade : n.line, width: selected ? 2 : 1),
        ),
        child: Text(amount == 0 ? 'Free' : '$amount', style: TextStyle(color: selected ? n.jade : n.mid, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
