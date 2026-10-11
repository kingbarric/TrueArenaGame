import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/nav_art.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';

/// Owner: turn the Huud Live. Asks who to tell first — every member (pushed to
/// their phones), only the ones online now, or nobody — then goes Live.
/// Returns the Huud as it is now, or null if they backed out.
Future<HuudSpace?> goLive(BuildContext context, String huudId) async {
  final tell = await showHuudSheet<String>(context, builder: (_) => const _GoLiveSheet());
  if (tell == null || !context.mounted) return null;
  try {
    final raw = await AppScope.of(context).api.post('/huud-spaces/$huudId/live', {'notify': tell});
    if (context.mounted) huudSnack(context, "You're Live! 🔴");
    return HuudSpace.fromJson((raw as Map).cast<String, dynamic>());
  } on ApiException catch (e) {
    if (context.mounted) huudSnack(context, e.message);
  } catch (_) {
    if (context.mounted) huudSnack(context, "That didn't work — check your internet and try again.");
  }
  return null;
}

const _choices = [
  ('all', '📣', 'Tell all members', "Everyone gets a notification (unless they've muted this Huud)"),
  ('online', '🟢', 'Only people online now', 'Just members who have PlayHuud open'),
  ('none', '🤫', "Don't tell anyone", 'Go Live quietly'),
];

class _GoLiveSheet extends StatefulWidget {
  const _GoLiveSheet();

  @override
  State<_GoLiveSheet> createState() => _GoLiveSheetState();
}

class _GoLiveSheetState extends State<_GoLiveSheet> {
  String _tell = 'all';

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Center(child: NavArt('live', active: true, size: 56)),
          const SizedBox(height: 6),
          Text('Go Live',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: n.ink)),
          const SizedBox(height: 4),
          Text('Your people can come in, talk and play',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: n.mid)),
          const SizedBox(height: 18),
          Text('Who should we tell?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: n.ink)),
          const SizedBox(height: 8),
          for (final (wire, emoji, title, line) in _choices) ...[
            Semantics(
              button: true,
              selected: _tell == wire,
              label: title,
              excludeSemantics: true,
              child: GestureDetector(
                key: ValueKey('golive-$wire'),
                onTap: () => setState(() => _tell = wire),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _tell == wire ? h.orangeSoft : n.panel,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _tell == wire ? h.orange : n.line, width: _tell == wire ? 2.4 : 1.4),
                  ),
                  child: Row(children: [
                    Text(emoji, style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: n.ink)),
                        Text(line, style: TextStyle(fontSize: 13.5, color: n.mid)),
                      ]),
                    ),
                    Icon(_tell == wire ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: _tell == wire ? h.orangeText : n.mute),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          HuudButton(
            key: const ValueKey('golive-confirm'),
            label: 'Go Live',
            icon: Icons.sensors_rounded,
            big: true,
            expand: true,
            onPressed: () => Navigator.of(context).pop(_tell),
          ),
        ]),
      ),
    );
  }
}
