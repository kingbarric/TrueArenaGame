import 'package:flutter/material.dart';
import 'slay_theme.dart';
import '../../theme/neon_theme.dart';

/// The same gear-menu pattern used by Chess and Whot, on every Slay screen.
class SlayGameMenu extends StatelessWidget {
  const SlayGameMenu(
      {super.key,
      required this.onExit,
      this.onBrief,
      this.onReset,
      this.exitLabel = 'Leave SlayHuud'});
  final VoidCallback onExit;
  final VoidCallback? onBrief;
  final VoidCallback? onReset;
  final String exitLabel;

  static Future<void> showHelp(BuildContext context) =>
      showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (sheet) => SafeArea(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('How to play SlayHuud',
                            style: Theme.of(sheet).textTheme.headlineSmall),
                        const SizedBox(height: 18),
                        for (final step in const [
                          (
                            '1. Choose a challenge',
                            'Read the theme and required items before styling.'
                          ),
                          (
                            '2. Create your look',
                            'Choose an avatar, outfit, hair and shoes. Drag to rotate and pinch to zoom.'
                          ),
                          (
                            '3. Submit your look',
                            'In solo challenges, your theme fit and item tags determine the score. Timed rooms close at the deadline.'
                          ),
                          (
                            '4. Vote and compete',
                            'Community voting compares anonymous looks. Style Battle is 1v1; groups rank multiple looks; Slay or Pass eliminates contestants across rounds.'
                          ),
                        ]) ...[
                          Text(step.$1,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(step.$2),
                          const SizedBox(height: 18),
                        ],
                        const Text(
                            'Judge styling, creativity and theme fit. Your wardrobe grows through earned coins and achievements.'),
                        const SizedBox(height: 20),
                        SizedBox(
                            width: double.infinity,
                            child: SlayButton(
                                onPressed: () => Navigator.pop(sheet),
                                child: const Text('Got it'))),
                      ]))));

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
      key: const ValueKey('slay-game-menu'),
      tooltip: 'Game settings',
      icon: const Icon(Icons.settings_rounded, size: 21),
      color: context.neon.panel,
      onSelected: (value) {
        switch (value) {
          case 'help':
            showHelp(context);
          case 'brief':
            onBrief?.call();
          case 'reset':
            onReset?.call();
          case 'exit':
            onExit();
        }
      },
      itemBuilder: (_) => [
            _item(context, 'help', Icons.help_outline_rounded, 'How to play'),
            if (onBrief != null)
              _item(context, 'brief', Icons.assignment_outlined,
                  'Challenge brief'),
            if (onReset != null)
              _item(context, 'reset', Icons.restart_alt_rounded,
                  'Start a fresh look'),
            _item(context, 'exit', Icons.logout_rounded, exitLabel),
          ]);

  PopupMenuItem<String> _item(
          BuildContext context, String value, IconData icon, String label) =>
      PopupMenuItem(
          value: value,
          child: Row(children: [
            Icon(icon, size: 18, color: context.neon.gold),
            const SizedBox(width: 10),
            Text(label),
          ]));
}

void leaveSlayScreen(BuildContext context) => Navigator.of(context).maybePop();
