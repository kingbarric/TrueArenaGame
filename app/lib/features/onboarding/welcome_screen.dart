import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../home/home_screen.dart';
import 'phone_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final app = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const MarqueeBar('Traitors and Faithful  •  five modes, launch-ready  •  bring your friends'),
            Align(
              alignment: Alignment.centerRight,
              child: _ThemeToggle(app: app),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TRUE\nARENA',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            fontSize: 56,
                            height: 0.92,
                            shadows: [Shadow(color: n.cyan.withValues(alpha: 0.35), blurRadius: 40)],
                          )),
                  const SizedBox(height: 14),
                  Text(
                    'A social-deduction party game. Pick a mode, open the room, and find the Traitors before they take the castle.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
              child: Column(
                children: [
                  NeonButton('Sign in with phone',
                      style: NeonStyle.go,
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const PhoneScreen()))),
                  const SizedBox(height: 10),
                  NeonButton('Play as guest',
                      style: NeonStyle.ghost, onPressed: () => _guest(context)),
                  const SizedBox(height: 12),
                  Text('Guests play one game. Verify a phone number afterwards to keep your stats.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _guest(BuildContext context) async {
    final app = AppScope.of(context);
    final nickname = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.neon.panel,
      builder: (_) => const _NicknameSheet(),
    );
    if (nickname == null || nickname.trim().isEmpty || !context.mounted) return;
    app.startGuest(nickname.trim());
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextButton.icon(
      onPressed: () => app.setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark),
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 16),
      label: Text(isDark ? 'Light' : 'Dark'),
    );
  }
}

class _NicknameSheet extends StatefulWidget {
  const _NicknameSheet();

  @override
  State<_NicknameSheet> createState() => _NicknameSheetState();
}

class _NicknameSheetState extends State<_NicknameSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 20, 22, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PICK A NAME', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.cyan)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 20,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'e.g. Sam', counterText: ''),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
          const SizedBox(height: 12),
          NeonButton('Continue', onPressed: () => Navigator.of(context).pop(_controller.text)),
        ],
      ),
    );
  }
}
