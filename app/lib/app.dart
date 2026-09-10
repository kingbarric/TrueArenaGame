import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/welcome_screen.dart';
import 'theme/neon_theme.dart';

class TrueArenaApp extends StatelessWidget {
  const TrueArenaApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          return MaterialApp(
            title: 'TrueArena',
            debugShowCheckedModeBanner: false,
            theme: NeonTheme.light,
            darkTheme: NeonTheme.dark,
            themeMode: state.themeMode,
            home: state.identity == Identity.account ? const HomeScreen() : const WelcomeScreen(),
          );
        },
      ),
    );
  }
}
