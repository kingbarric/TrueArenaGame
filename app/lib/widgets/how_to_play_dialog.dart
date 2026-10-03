import 'package:flutter/material.dart';

import '../theme/neon_theme.dart';

/// A short, numbered rules card — same shape for every game, just different
/// words. Meant to answer "wait, how do I play this?" in under a minute, not
/// to be a full rulebook.
Future<void> showHowToPlay(
  BuildContext context, {
  required String emoji,
  required String title,
  required String tagline,
  required List<String> steps,
}) {
  final n = context.neon;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 10),
        Expanded(child: Text('How to play $title')),
      ]),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tagline, style: TextStyle(color: n.mid)),
              const SizedBox(height: 16),
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: n.gold.withValues(alpha: 0.18)),
                        child: Text('${i + 1}',
                            style: TextStyle(
                                color: n.gold, fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(steps[i])),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Got it')),
      ],
    ),
  );
}
