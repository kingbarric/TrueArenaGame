import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_state.dart';
import '../../core/game_music.dart';
import '../../core/game_sfx.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../onboarding/sign_out.dart';

/// Reached by tapping the profile row on Home. Everything here is a
/// per-device preference (avatar, theme) — there's no backend profile
/// endpoint yet, so nothing here syncs across devices.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _picking = false;
  bool _musicOn = GameMusic.enabled;
  bool _sfxOn = GameSfx.enabled;

  Future<void> _upload(AppState app) async {
    setState(() => _picking = true);
    try {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 640, maxHeight: 640);
      if (picked != null) await app.setAvatarImage(picked.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open your photo library')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final app = AppScope.of(context);
    final name = app.user?.displayName ?? 'Player';
    final mode = app.themeMode;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Column(
                children: [
                  Avatar(name,
                      size: 84,
                      emoji: app.avatarEmoji,
                      imagePath: app.avatarImagePath),
                  const SizedBox(height: 10),
                  Text(name, style: Theme.of(context).textTheme.titleMedium),
                  if (app.user?.phone != null)
                    Text(app.user!.phone!,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: n.mute)),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text('PROFILE ICON',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: n.gold)),
            const SizedBox(height: 4),
            Text('Pick a preset, or upload your own photo.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: n.mid)),
            const SizedBox(height: 12),
            NeonButton(
              _picking ? 'Opening photos…' : 'Upload a photo',
              style: NeonStyle.ghost,
              onPressed: _picking ? null : () => _upload(app),
            ),
            const SizedBox(height: 14),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 5,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                for (final e in kAvatarPresets)
                  _PresetTile(
                    emoji: e,
                    selected:
                        app.avatarImagePath == null && app.avatarEmoji == e,
                    onTap: () => app.setAvatarEmoji(e),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Text('APPEARANCE',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: n.gold)),
            const SizedBox(height: 12),
            VisualThemePicker(
                value: app.visualTheme, onChanged: app.setVisualTheme),
            const SizedBox(height: 10),
            Text('Choose the look of your app and games.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: n.mid)),
            const SizedBox(height: 18),
            NeonSegmentedThemePicker(mode: mode, onChanged: app.setThemeMode),
            const SizedBox(height: 28),
            Text('MUSIC',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: n.gold)),
            const SizedBox(height: 4),
            Text(
              'Soft piano while you play. Every game draws a different set of '
              'pieces, so it never loops the same minute at you.',
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(color: n.mid),
            ),
            const SizedBox(height: 12),
            NeonCard(
              child: Row(children: [
                Expanded(
                    child: Text('Play music in games',
                        style: Theme.of(context).textTheme.bodyMedium)),
                Switch(
                  value: _musicOn,
                  onChanged: (v) async {
                    setState(() => _musicOn = v);
                    await GameMusic.setEnabled(v);
                  },
                ),
              ]),
            ),
            const SizedBox(height: 10),
            NeonCard(
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Game sounds',
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 2),
                        Text('Taps, moves and captures on the board.',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: n.mute)),
                      ]),
                ),
                Switch(
                  value: _sfxOn,
                  onChanged: (v) async {
                    setState(() => _sfxOn = v);
                    await GameSfx.setEnabled(v);
                  },
                ),
              ]),
            ),
            const SizedBox(height: 28),
            Text('WORD BLUFF VOICE MATCH',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: n.gold)),
            const SizedBox(height: 4),
            Text(
              'While you\'re describing, listen for your team\'s guess and auto-lock '
              'in "Got it" when it sounds close enough — no need to say the word exactly.',
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(color: n.mid),
            ),
            const SizedBox(height: 12),
            NeonCard(
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Text('Listen for guesses',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                  Switch(
                      value: app.voiceMatchEnabled,
                      onChanged: (v) => app.setVoiceMatchEnabled(v)),
                ]),
                if (app.voiceMatchEnabled) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Text('Looser',
                        style: TextStyle(fontSize: 11, color: n.mute)),
                    Expanded(
                      child: Slider(
                        value: app.voiceMatchThreshold,
                        min: 0.5,
                        max: 1.0,
                        divisions: 10,
                        label: '${(app.voiceMatchThreshold * 100).round()}%',
                        onChanged: (v) => app.setVoiceMatchThreshold(v),
                      ),
                    ),
                    Text('Exact',
                        style: TextStyle(fontSize: 11, color: n.mute)),
                  ]),
                  Text(
                    'Match threshold: ${(app.voiceMatchThreshold * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: n.mute),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 28),
            Text('ACCOUNT',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: n.gold)),
            const SizedBox(height: 12),
            NeonButton(
              'Sign out',
              style: NeonStyle.ghost,
              onPressed: () => confirmSignOut(context, app),
            ),
          ],
        ),
      ),
    );
  }
}

class VisualThemePicker extends StatelessWidget {
  const VisualThemePicker(
      {super.key, required this.value, required this.onChanged});

  final VisualTheme value;
  final ValueChanged<VisualTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = context.neon;
    Widget option(
        VisualTheme choice, String title, String subtitle, NeonColors swatch) {
      final selected = value == choice;
      return SizedBox(
        width: 152,
        child: Semantics(
          button: true,
          selected: selected,
          label: '$title theme',
          child: Bouncy(
            onTap: () => onChanged(choice),
            pressScale: 0.97,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: current.panel,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: selected ? current.gold : current.line,
                    width: selected ? 2 : 1),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 88,
                      decoration: choice == VisualTheme.supercar
                          ? ShapeDecoration(
                              gradient: LinearGradient(colors: [swatch.bg, swatch.panel]),
                              shape: BeveledRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  side: BorderSide(color: swatch.gold, width: 1.5)),
                            )
                          : BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                  choice == VisualTheme.nebula ? 24 : 14),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  swatch.bg,
                                  swatch.panel,
                                  swatch.brand.withValues(alpha: 0.8)
                                ],
                              ),
                              border: choice == VisualTheme.nebula
                                  ? Border.all(color: swatch.gold.withValues(alpha: 0.6))
                                  : null,
                            ),
                      child: Stack(children: [
                        Positioned(
                            right: 12,
                            top: 12,
                            child: Icon(
                                switch (choice) {
                                  VisualTheme.palmWine => Icons.casino_rounded,
                                  VisualTheme.nebula =>
                                    Icons.auto_awesome_rounded,
                                  VisualTheme.supercar => Icons.speed_rounded,
                                },
                                color: swatch.gold,
                                size: 24)),
                        Positioned(
                            left: 10,
                            bottom: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 5),
                              decoration: choice == VisualTheme.supercar
                                  ? ShapeDecoration(
                                      color: swatch.brand,
                                      shape: BeveledRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          side: BorderSide(color: swatch.gold)),
                                    )
                                  : BoxDecoration(
                                      color: swatch.brand,
                                      borderRadius: BorderRadius.circular(999)),
                              child: const Text('PLAY',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 9,
                                      letterSpacing: 1)),
                            )),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: current.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: current.mute, fontSize: 10)),
                  ]),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        option(VisualTheme.palmWine, 'Palm Wine', 'Original', NeonColors.dark),
        const SizedBox(width: 10),
        option(VisualTheme.nebula, 'Nebula', 'Cosmic arcade',
            NeonColors.nebulaDark),
        const SizedBox(width: 10),
        option(VisualTheme.supercar, 'Supercar', 'Racing dashboard',
            NeonColors.supercarDark),
      ]),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile(
      {required this.emoji, required this.selected, required this.onTap});
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Bouncy(
      onTap: onTap,
      pressScale: 0.9,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected ? n.brand.withValues(alpha: 0.16) : n.plate,
          shape: BoxShape.circle,
          border: Border.all(
              color: selected ? n.brand : n.line, width: selected ? 2 : 1.2),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: n.brand.withValues(alpha: 0.35),
                      blurRadius: 14,
                      spreadRadius: -3)
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

/// Light / Dark / System — same underlying [AppState.setThemeMode] the old
/// header toggle used, just surfaced properly in Settings now.
class NeonSegmentedThemePicker extends StatelessWidget {
  const NeonSegmentedThemePicker(
      {super.key, required this.mode, required this.onChanged});
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    Widget option(ThemeMode m, IconData icon, String label) {
      final selected = mode == m;
      return Expanded(
        child: Bouncy(
          onTap: () => onChanged(m),
          pressScale: 0.95,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: selected ? n.gold.withValues(alpha: 0.14) : n.plate,
              borderRadius: BorderRadius.circular(NeonRadius.control),
              border: Border.all(
                  color: selected ? n.gold : n.line, width: selected ? 1.6 : 1),
            ),
            child: Column(
              children: [
                Icon(icon, size: 20, color: selected ? n.gold : n.mute),
                const SizedBox(height: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? n.ink : n.mute)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(children: [
      option(ThemeMode.light, Icons.light_mode_outlined, 'Light'),
      option(ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
      option(ThemeMode.system, Icons.smartphone_outlined, 'Auto'),
    ]);
  }
}
