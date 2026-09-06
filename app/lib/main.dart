import 'package:flutter/material.dart';

void main() => runApp(const TrueArenaApp());

class TrueArenaApp extends StatelessWidget {
  const TrueArenaApp({super.key});

  static const String apiBase =
      String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrueArena',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF6C4CF1),
      ),
      home: const _Placeholder(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('TrueArena', style: TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text('API: ${TrueArenaApp.apiBase}'),
            const SizedBox(height: 24),
            const Text('Phase 10 builds the real app.'),
          ],
        ),
      ),
    );
  }
}
