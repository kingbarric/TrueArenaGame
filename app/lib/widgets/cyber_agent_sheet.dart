import 'package:flutter/material.dart';

import '../theme/neon_theme.dart';
import 'neon.dart';
import 'neon_form.dart';

/// Room-scoped choices for one reusable system Cyber Agent.
class AgentChoice {
  const AgentChoice(this.name, this.difficulty);

  final String name;
  final String difficulty;
}

/// Every lobby uses the same direct flow: name the agent, choose its level,
/// and add it to this Huud. There is no personal agent inventory to manage,
/// and no per-game filtering — every Cyber Agent comes from one shared pool.
Future<AgentChoice?> showCyberAgentPicker(BuildContext context,
    {String defaultName = 'Cyber'}) {
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
            NeonSegmented<String>(
              options: const [
                SegOption('easy', 'Amateur'),
                SegOption('medium', 'Pro'),
                SegOption('hard', 'Legend'),
              ],
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
