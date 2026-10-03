import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';
import '../theme/neon_theme.dart';
import 'neon.dart';
import 'neon_form.dart';

/// What the lobby should do once the player has picked an agent: either put
/// one they already own back on the table ([agentId]), or create a new one
/// ([name] + [difficulty]).
class AgentChoice {
  const AgentChoice.existing(this.agentId)
      : name = null,
        difficulty = null;
  const AgentChoice.create(this.name, this.difficulty) : agentId = null;

  final String? agentId;
  final String? name;
  final String? difficulty;

  bool get isExisting => agentId != null;
}

/// One saved agent in the shared, cross-game roster.
class SavedAgent {
  SavedAgent(this.id, this.displayName, this.difficulty);

  factory SavedAgent.fromJson(Map<String, dynamic> j) => SavedAgent(
      j['userId'] as String,
      j['displayName'] as String,
      j['difficulty'] as String? ?? 'medium');

  final String id;
  String displayName;
  final String difficulty;
}

const _difficultyLabels = {
  'easy': 'Amateur',
  'medium': 'Pro',
  'hard': 'Legend'
};
const _maxCyberAgents = 5;

String _nextCyberName(Iterable<SavedAgent> agents) {
  var highest = 0;
  final numbered = RegExp(r'^cyber(\d+)$', caseSensitive: false);
  for (final agent in agents) {
    final match = numbered.firstMatch(agent.displayName.trim());
    if (match != null) {
      final number = int.tryParse(match.group(1)!);
      if (number != null && number > highest) highest = number;
    }
  }
  return 'cyber${highest + 1}';
}

/// The entry point every lobby uses. Agents are kept between games, so the
/// common case is picking one you already made — the naming form only comes
/// up on its own when you have none for this game yet.
Future<AgentChoice?> showCyberAgentPicker(BuildContext context,
    {required String gameType}) async {
  final app = AppScope.of(context);
  List<SavedAgent> saved = const [];
  try {
    final res = await app.api.get('/agents?gameType=$gameType');
    saved = ((res as List?) ?? const [])
        .map((e) => SavedAgent.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  } catch (_) {
    // Offline or the roster call failed — fall through to creating a new
    // one, which is what the player could do before agents were saved.
  }
  if (!context.mounted) return null;
  if (saved.isEmpty) return showAddCyberAgentSheet(context);

  return showModalBottomSheet<AgentChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.neon.panel.withValues(alpha: 0.92),
    builder: (_) => _PickAgentSheet(agents: saved),
  );
}

/// The "name it and set its level" form. Shown on its own when the player
/// has no agents for this game, and reachable from the picker's
/// "Create another" when they do.
Future<AgentChoice?> showAddCyberAgentSheet(BuildContext context,
    {Iterable<SavedAgent> existing = const []}) {
  if (existing.length >= _maxCyberAgents) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('You can have up to 5 Cyber Agents. Reuse or delete one.'),
    ));
    return Future.value(null);
  }
  return showModalBottomSheet<AgentChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.neon.panel.withValues(alpha: 0.92),
    builder: (_) => AddCyberAgentSheet(defaultName: _nextCyberName(existing)),
  );
}

class _PickAgentSheet extends StatefulWidget {
  const _PickAgentSheet({required this.agents});

  final List<SavedAgent> agents;

  @override
  State<_PickAgentSheet> createState() => _PickAgentSheetState();
}

class _PickAgentSheetState extends State<_PickAgentSheet> {
  late final List<SavedAgent> _agents = List.of(widget.agents);

  Future<void> _rename(SavedAgent agent) async {
    final name = await showRenameAgentDialog(context, agent.displayName);
    if (name == null || !mounted) return;
    try {
      await AppScope.of(context)
          .api
          .patch('/agents/${agent.id}', {'name': name});
      setState(() => agent.displayName = name);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not rename that agent')));
      }
    }
  }

  /// Retiring an agent is permanent, so it asks first. The server refuses
  /// while the agent is still sitting in a live room — deleting a player
  /// mid-game would strand whoever is playing against it.
  Future<void> _delete(SavedAgent agent) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${agent.displayName}?'),
        content: const Text(
            'This agent is gone for good. You can always make a new one.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await AppScope.of(context).api.delete('/agents/${agent.id}');
      if (!mounted) return;
      setState(() => _agents.removeWhere((a) => a.id == agent.id));
      // Nothing left to pick from — fall through to making one.
      if (_agents.isEmpty && mounted) {
        Navigator.of(context).pop(await showAddCyberAgentSheet(context));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not delete that agent')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR CYBER AGENTS',
              style: t.labelLarge?.copyWith(color: n.gold)),
          Text('${_agents.length}/$_maxCyberAgents saved agents',
              style: t.labelSmall?.copyWith(color: n.mute)),
          const SizedBox(height: 12),
          for (final agent in _agents)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  OnlineAvatar(agent.displayName,
                      size: 36, emoji: '🤖', online: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(agent.displayName,
                            style: t.bodyLarge,
                            overflow: TextOverflow.ellipsis),
                        Text(
                            _difficultyLabels[agent.difficulty] ??
                                agent.difficulty,
                            style: t.labelSmall?.copyWith(color: n.mute)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Rename',
                    icon: Icon(Icons.edit_outlined, size: 18, color: n.mute),
                    onPressed: () => _rename(agent),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 18, color: n.mute),
                    onPressed: () => _delete(agent),
                  ),
                  NeonButton(
                    'Add',
                    expand: false,
                    onPressed: () => Navigator.of(context)
                        .pop(AgentChoice.existing(agent.id)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          if (_agents.length < _maxCyberAgents)
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create another agent'),
              onPressed: () async {
                final created =
                    await showAddCyberAgentSheet(context, existing: _agents);
                if (created != null && context.mounted) {
                  Navigator.of(context).pop(created);
                }
              },
            )
          else
            Text('Maximum reached. Reuse or delete an agent to make another.',
                style: t.labelSmall?.copyWith(color: n.mute)),
        ],
      ),
    );
  }
}

/// Asks for a new display name for an agent, returning null if cancelled.
/// Used by the picker and by the friends list, where a player's agents show
/// up alongside their friends.
Future<String?> showRenameAgentDialog(BuildContext context, String current) {
  return showDialog<String>(
      context: context, builder: (_) => _RenameDialog(current: current));
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename agent'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 24,
        textCapitalization: TextCapitalization.words,
        decoration:
            const InputDecoration(hintText: 'Agent name', counterText: ''),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isNotEmpty) Navigator.of(context).pop(name);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Names a new Cyber Agent and sets its level — shown to players as
/// Amateur/Pro/Legend over the plain easy/medium/hard the backend expects
/// (see `Difficulty` in ta-api).
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
    return Padding(
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
            controller: _controller,
            autofocus: true,
            maxLength: 24,
            textCapitalization: TextCapitalization.words,
            decoration:
                const InputDecoration(hintText: 'Agent name', counterText: ''),
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
            onChanged: (v) => setState(() => _difficulty = v),
          ),
          const SizedBox(height: 18),
          NeonButton('Add Cyber Agent', onPressed: () {
            final name = _controller.text.trim();
            Navigator.of(context).pop(AgentChoice.create(
                name.isEmpty ? widget.defaultName : name, _difficulty));
          }),
        ],
      ),
    );
  }
}
