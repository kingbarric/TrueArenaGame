import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_state.dart';
import '../../core/game_music.dart';
import '../../core/game_sfx.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../competitive/competitive_api.dart';
import '../competitive/competitive_models.dart';
import '../competitive/competitive_setup_screen.dart';
import '../competitive/player_profile_screen.dart' show ProfileVisibilitySwitch, locationLine;
import '../notifications/notifications_screen.dart';
import '../onboarding/sign_out.dart';

/// Everything about you and your device: edit profile (photo, username,
/// where you compete, who can see your cards), appearance, sound,
/// notifications, and sign out. The Profile tab is just your player cards.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _picking = false;
  bool _musicOn = GameMusic.enabled;
  bool _sfxOn = GameSfx.enabled;
  CompetitiveProfile? _competitive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCompetitive());
  }

  Future<void> _loadCompetitive() async {
    final app = AppScope.of(context);
    if (app.identity != Identity.account) return;
    try {
      final p = await CompetitiveApi(app.api).mine();
      if (mounted) setState(() => _competitive = p);
    } catch (_) {/* the rows below just don't show */}
  }

  Future<void> _editUsername(AppState app) async {
    final controller = TextEditingController(text: app.user?.username ?? '');
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.neon.panel,
      builder: (_) => _UsernameSheet(controller: controller),
    );
    controller.dispose();
    if (result == null || result.isEmpty || !mounted) return;
    try {
      await app.setUsername(result);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().contains('409') ? 'That username is taken' : 'Could not update username')));
      }
    }
  }

  Future<void> _editLocation() async {
    final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => CompetitiveSetupScreen(initial: _competitive)));
    if (saved == true) _loadCompetitive();
  }

  Future<void> _upload(AppState app) async {
    setState(() => _picking = true);
    try {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 320, maxHeight: 320,
          imageQuality: 65);
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
                  InkWell(
                    onTap: _picking ? null : () => _upload(app),
                    borderRadius: BorderRadius.circular(48),
                    child: Stack(alignment: Alignment.bottomRight, children: [
                      Avatar(name,
                          size: 84,
                          emoji: app.avatarEmoji,
                          imagePath: app.avatarImagePath,
                          imageUrl: app.user?.avatarUrl),
                      CircleAvatar(
                          radius: 15,
                          backgroundColor: n.gold,
                          child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.black)),
                    ]),
                  ),
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
            if (app.identity == Identity.account) ...[
              Text('EDIT PROFILE', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.gold)),
              const SizedBox(height: 12),
              NeonCard(
                key: const ValueKey('settings-username'),
                onTap: () => _editUsername(app),
                child: Row(children: [
                  Icon(Icons.alternate_email, color: n.mid),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Username', style: Theme.of(context).textTheme.bodyMedium),
                      Text('@${app.user?.username ?? '—'}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.gold)),
                    ]),
                  ),
                  Icon(Icons.edit, color: n.mute, size: 18),
                ]),
              ),
              if (_competitive != null) ...[
                const SizedBox(height: 10),
                NeonCard(
                  key: const ValueKey('settings-location'),
                  onTap: _editLocation,
                  child: Row(children: [
                    Icon(Icons.flag_rounded, color: n.mid),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Where you compete', style: Theme.of(context).textTheme.bodyMedium),
                        Text(
                            locationLine(_competitive!.location).isEmpty
                                ? 'Not set — add it to unlock National & State rankings'
                                : locationLine(_competitive!.location),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
                      ]),
                    ),
                    Icon(Icons.chevron_right, color: n.mute, size: 20),
                  ]),
                ),
                const SizedBox(height: 4),
                ProfileVisibilitySwitch(profile: _competitive!, onChanged: _loadCompetitive),
              ],
              const SizedBox(height: 28),
            ],
            Text('NOTIFICATIONS',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: n.gold)),
            const SizedBox(height: 12),
            NeonCard(
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
              child: Row(children: [
                Icon(Icons.notifications_outlined, color: n.mid),
                const SizedBox(width: 12),
                Expanded(
                    child: Text('Notifications',
                        style: Theme.of(context).textTheme.bodyMedium)),
                Icon(Icons.chevron_right, color: n.mute, size: 20),
              ]),
            ),
            const SizedBox(height: 28),
            Text('PROFILE PICTURE',
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

class _UsernameSheet extends StatelessWidget {
  const _UsernameSheet({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 20, 22, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CHANGE USERNAME', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.gold)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 24,
            decoration: const InputDecoration(
                hintText: 'e.g. king_of_traitors', counterText: '', prefixIcon: Icon(Icons.alternate_email)),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          const SizedBox(height: 12),
          NeonButton('Save', onPressed: () => Navigator.of(context).pop(controller.text.trim())),
        ],
      ),
    );
  }
}
