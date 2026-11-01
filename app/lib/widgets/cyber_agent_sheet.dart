import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/neon_theme.dart';
import 'neon.dart';
import 'cyber_agent_difficulty.dart';

/// Room-scoped choices for one reusable system Cyber Agent.
class AgentChoice {
  const AgentChoice(this.name, this.difficulty);

  final String name;
  final String difficulty;
}

const cyberAgentNames = [
  'max', 'tan', 'kim', 'zed', 'ivy', 'rex', 'jax', 'kai', 'lux', 'ace', //
  'dex', 'neo', 'sky', 'ray', 'leo', 'mia', 'nia', 'obi', 'ama', 'kofi',
  'zola', 'tobi', 'femi', 'ike', 'yaw', 'esi', 'sol', 'pip', 'jin', 'lia',
  'fox', 'jet', 'kit', 'ren', 'vic', 'zia', 'nova', 'remi', 'tayo', 'kemi',
];

/// What a new Cyber Agent is called: cyber_max, cyber_kim — a name nobody at
/// the table has yet, never "Cyber 2". The server names agents the same way
/// for older apps that still send the numbered names.
String cyberAgentName(Iterable<String?> taken, [Random? random]) {
  final used = {
    for (final n in taken)
      if (n != null) n.trim().toLowerCase()
  };
  final r = random ?? Random();
  final free = [
    for (final n in cyberAgentNames)
      if (!used.contains('cyber_$n')) 'cyber_$n'
  ];
  if (free.isNotEmpty) return free[r.nextInt(free.length)];
  for (var i = 2;; i++) {
    final n = 'cyber_${cyberAgentNames[r.nextInt(cyberAgentNames.length)]}$i';
    if (!used.contains(n)) return n;
  }
}

/// Every lobby uses the same direct flow: name the agent, choose its level,
/// and add it to this Huud. There is no personal agent inventory to manage,
/// and no per-game filtering — every Cyber Agent comes from one shared pool.
/// [taken] is everyone already at the table, so the suggested name is new.
Future<AgentChoice?> showCyberAgentPicker(BuildContext context,
    {Iterable<String?> taken = const []}) {
  final defaultName = cyberAgentName(taken);
  return showModalBottomSheet<AgentChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.neon.panel.withValues(alpha: 0.96),
    builder: (_) => AddCyberAgentSheet(defaultName: defaultName),
  );
}

class AddCyberAgentSheet extends StatefulWidget {
  const AddCyberAgentSheet({super.key, required this.defaultName});

  final String defaultName;

  @override
  State<AddCyberAgentSheet> createState() => _AddCyberAgentSheetState();
}

class _AddCyberAgentSheetState extends State<AddCyberAgentSheet> {
  late final _controller = TextEditingController(text: widget.defaultName);
  String _difficulty = 'medium';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            22, 20, 22, MediaQuery.viewInsetsOf(context).bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ADD A CYBER AGENT',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: n.gold)),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('cyber-agent-name'),
              controller: _controller,
              autofocus: true,
              maxLength: 24,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  hintText: 'Agent name', counterText: ''),
            ),
            const SizedBox(height: 16),
            Text('DIFFICULTY',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: n.mute, letterSpacing: 2)),
            const SizedBox(height: 8),
            CyberAgentDifficulty(
              value: _difficulty,
              onChanged: (value) => setState(() => _difficulty = value),
            ),
            const SizedBox(height: 18),
            NeonButton('Add Cyber Agent',
                key: const ValueKey('confirm-cyber-agent'), onPressed: () {
              final name = _controller.text.trim();
              Navigator.of(context).pop(AgentChoice(
                  name.isEmpty ? widget.defaultName : name, _difficulty));
            }),
          ],
        ),
      ),
    );
  }
}
