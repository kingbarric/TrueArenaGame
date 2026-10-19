import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_state.dart';

/// Reads a persistent server receipt, including after reconnecting to results.
class MatchCoinReward extends StatefulWidget {
  const MatchCoinReward({super.key, required this.roomId, this.foregroundColor});
  final String roomId;
  final Color? foregroundColor;
  @override
  State<MatchCoinReward> createState() => _MatchCoinRewardState();
}

class _MatchCoinRewardState extends State<MatchCoinReward> {
  Map<String, dynamic>? _reward;
  bool _started = false;
  bool _failed = false;
  Timer? _retry;
  int _attempts = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    final app = AppScope.of(context);
    if (app.identity == Identity.anonymous) return;
    try {
      final result = await app.api.get('/rooms/${widget.roomId}/coin-reward');
      if (!mounted) return;
      setState(() {
        _reward = Map<String, dynamic>.from(result as Map);
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (++_attempts < 4) {
        _retry = Timer(Duration(seconds: _attempts), _load);
      } else {
        setState(() => _failed = true);
      }
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
      style: TextStyle(color: widget.foregroundColor),
      child: Builder(builder: _buildReward));

  Widget _buildReward(BuildContext context) {
    if (AppScope.of(context).identity == Identity.anonymous)
      return const SizedBox.shrink();
    final reward = _reward;
    if (reward == null) {
      if (!_failed)
        return const Text('Checking earned coins…',
            textAlign: TextAlign.center);
      return TextButton(
          style: TextButton.styleFrom(foregroundColor: widget.foregroundColor),
          onPressed: () {
            _attempts = 0;
            setState(() => _failed = false);
            _load();
          },
          child: const Text('Check earned coins'));
    }
    final amount = (reward['amount'] as num).toInt();
    final base = (reward['baseAmount'] as num).toInt();
    final bonus = (reward['timeBonus'] as num).toInt();
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              amount > 0
                  ? '+$amount coins earned'
                  : 'No coin reward for this match',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          if (bonus > 0)
            Text('Result $base · Time bonus $bonus',
                textAlign: TextAlign.center),
          if (reward['vsAgent'] == true)
            const Text('Cyber Agent practice match',
                textAlign: TextAlign.center),
        ]));
  }
}
