import 'package:flutter/material.dart';

import '../theme/neon_theme.dart';
import 'neon.dart';

/// The bottom of every game lobby, just before play: one big Start game
/// for the host — no "Ready up", nobody has to press anything — and a
/// friendly "waiting" line for everyone else.
class LobbyStartBar extends StatelessWidget {
  const LobbyStartBar({super.key, required this.isHost, required this.onStart, this.hint});

  final bool isHost;

  /// Null while the game can't start yet (e.g. not enough players).
  final VoidCallback? onStart;

  /// Under the button: what's missing, if anything.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (isHost)
        SizedBox(
          height: 58,
          child: NeonButton('Start game', key: const ValueKey('lobby-start'), onPressed: onStart),
        )
      else
        Container(
          key: const ValueKey('lobby-waiting'),
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: n.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: n.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.hourglass_top_rounded, size: 18, color: n.mute),
            const SizedBox(width: 8),
            Text('Waiting for the host to start…',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: n.mid)),
          ]),
        ),
      if (hint != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(hint!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: n.mute)),
        ),
    ]);
  }
}
