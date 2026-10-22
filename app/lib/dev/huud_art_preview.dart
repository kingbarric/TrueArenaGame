// Local artwork QA: real Huud screens with empty, in-memory API responses.
// This entrypoint never signs in, sends notifications or changes live data.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../features/huudspace/huud_home_screen.dart';
import '../features/huudspace/live_now_panel.dart';
import '../theme/neon_theme.dart';
import '../widgets/huud_art.dart';
import '../widgets/neon.dart';
import '../widgets/playground_nav_pill.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient(
      client: MockClient((_) async => http.Response('[]', 200,
          headers: {'content-type': 'application/json'})))
    ..bearer = 'local-art-preview';
  final state = AppState(api)
    ..user = const UserView(id: 'preview', displayName: 'Riley', isGuest: false)
    ..identity = Identity.account;
  runApp(AppScope(
      state: state,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: const bool.fromEnvironment('HUUD_DARK_PREVIEW')
            ? NeonTheme.dark
            : NeonTheme.light,
        home: const _ArtPreview(),
      )));
}

class _ArtPreview extends StatefulWidget {
  const _ArtPreview();
  @override
  State<_ArtPreview> createState() => _ArtPreviewState();
}

class _ArtPreviewState extends State<_ArtPreview> {
  int page = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: page, children: [
          const LiveNowPanel(bottomPadding: 20),
          const HuudHomeScreen(),
          SafeArea(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    const Text('Huud artwork',
                        style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 20),
                    Wrap(spacing: 16, runSpacing: 16, children: [
                      for (final preset in kAvatarPresets)
                        Avatar('Player', emoji: preset, size: 64),
                    ]),
                    const SizedBox(height: 24),
                    const HuudText(
                        '🏆 Well played!  🎁 A gift for you  ✋ Ask to speak',
                        style: TextStyle(fontSize: 20)),
                  ]))),
        ]),
        bottomNavigationBar: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(8),
                child: FittedBox(
                    child: PlaygroundNavPill(activeIndex: page, items: [
                  PlaygroundNavItem(
                      icon: Icons.live_tv_rounded,
                      label: 'Live',
                      art: 'live',
                      onTap: () => setState(() => page = 0)),
                  PlaygroundNavItem(
                      icon: Icons.groups_rounded,
                      label: 'Huud',
                      art: 'huud',
                      onTap: () => setState(() => page = 1)),
                  PlaygroundNavItem(
                      icon: Icons.face_rounded,
                      label: 'Artwork',
                      art: 'you',
                      onTap: () => setState(() => page = 2)),
                ])))),
      );
}
