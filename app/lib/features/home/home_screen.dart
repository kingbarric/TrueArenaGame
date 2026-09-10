import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../modes/mode_select_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final app = AppScope.of(context);
    final name = app.user?.displayName ?? 'Player';
    final isGuest = app.identity == Identity.guest;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MarqueeBar('Friday Crew  •  season 1  •  game 12 of 100  •  your move'),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
              child: Row(
                children: [
                  Avatar(name, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: Theme.of(context).textTheme.titleMedium),
                        Text(isGuest ? 'Guest — one game' : 'Signed in',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      app.setThemeMode(
                        Theme.of(context).brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
                      );
                    },
                    icon: Icon(Theme.of(context).brightness == Brightness.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text('START A\nGAME',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 46, height: 0.92)),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: NeonButton('New game', onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ModeSelectScreen()));
              }),
            ),
            if (isGuest) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: NeonCard(
                  accent: n.acid,
                  child: Row(children: [
                    Icon(Icons.workspace_premium_outlined, color: n.acid, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Verify a phone number to keep your stats after this game.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: n.mid)),
                    ),
                  ]),
                ),
              ),
            ],
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
