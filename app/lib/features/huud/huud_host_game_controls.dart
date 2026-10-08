import 'package:flutter/material.dart';
import '../../core/game_socket.dart';

/// An admin may run a hidden-role game without receiving a player's secret state.
class HuudHostGameControls extends StatelessWidget {
  const HuudHostGameControls(
      {super.key,
      required this.socket,
      required this.state,
      required this.names});
  final GameSocket socket;
  final Map<String, dynamic> state;
  final Map<String, String> names;
  void _send(String action, [Map<String, dynamic> data = const {}]) =>
      socket.send('PLAYER_ACTION', {'action': action, 'data': data});
  Future<String?> _pick(BuildContext context, String title, List<String> ids) =>
      showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                ListTile(title: Text(title)),
                for (final id in ids)
                  ListTile(
                      title: Text(names[id] ?? 'Player'),
                      onTap: () => Navigator.pop(ctx, id)),
              ])));
  @override
  Widget build(BuildContext context) {
    final phase = state['phase'];
    final alive = ((state['alive'] as List?) ?? []).cast<String>();
    return Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
      if (const [
        'RoleReveal',
        'MorningReveal',
        'RoundTable',
        'VoteReview',
        'Elimination',
        'WinCheck'
      ].contains(phase))
        FilledButton(
            onPressed: () => _send('ADVANCE_PHASE'),
            child: const Text('Continue Game')),
      if (phase == 'VoteReview')
        TextButton(
            onPressed: () => _send('REVEAL_NEXT'),
            child: const Text('Reveal Next Vote')),
      if (phase == 'HostDecision')
        FilledButton(
            onPressed: () async {
              final target = await _pick(context, 'Break the tie',
                  ((state['tieCandidates'] as List?) ?? []).cast<String>());
              if (target != null) _send('CHOOSE_TIE', {'target': target});
            },
            child: const Text('Break Tie')),
      if (phase == 'RoundTable' && state['immunityAvailable'] == true)
        TextButton(
            onPressed: () async {
              final target = await _pick(context, 'Award immunity', alive);
              if (target != null) _send('AWARD_IMMUNITY', {'target': target});
            },
            child: const Text('Award Immunity')),
      if (phase == 'HostAssignVotes')
        FilledButton(
            onPressed: () async {
              final voter = await _pick(context, 'Choose missing voter',
                  ((state['missingVoters'] as List?) ?? []).cast<String>());
              if (voter == null || !context.mounted) return;
              final target = await _pick(context, 'Assign their vote',
                  alive.where((id) => id != voter).toList());
              if (target != null) {
                _send('HOST_ASSIGN_VOTE', {'voter': voter, 'target': target});
              }
            },
            child: const Text('Assign Missing Vote')),
    ]);
  }
}
