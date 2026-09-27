import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/motif.dart';
import '../../widgets/neon.dart';
import '../shell/main_shell.dart';
import 'phone_screen.dart';
import 'username_setup_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  bool _googleBusy = false;
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  Animation<double> _pop(double start, double end) =>
      CurvedAnimation(parent: _intro, curve: Interval(start, end, curve: Curves.easeOutBack));

  // Opacity can't overshoot past 1.0 like the bouncy scale curve does, so fades
  // get their own gentler curve on the same timing window.
  Animation<double> _fade(double start, double end) =>
      CurvedAnimation(parent: _intro, curve: Interval(start, end, curve: Curves.easeOut));

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final app = AppScope.of(context);
    final title = _pop(0.0, 0.6);
    final titleFade = _fade(0.0, 0.5);
    final subtitle = _fade(0.2, 0.75);
    final buttons = _pop(0.35, 1.0);
    final buttonsFade = _fade(0.35, 0.85);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _BlobField(n: n)),
          // Three distinct spots so the shapes don't crowd each other, the
          // text, or the buttons: dice top-left, cup top-right, drum in the
          // empty middle band (placed by fraction of height, not anchored to
          // the bottom, so it never creeps under the CTA buttons).
          Positioned(left: -20, top: 70, child: DiceMotif(color: n.ink, size: 110, opacity: 0.16, rotation: -0.2)),
          Positioned(right: -15, top: 190, child: PalmWineCupMotif(color: n.ink, size: 110, opacity: 0.16, rotation: 0.1)),
          Positioned(
            left: -50,
            top: MediaQuery.sizeOf(context).height * 0.44,
            child: DrumMotif(color: n.ink, size: 220, opacity: 0.16, rotation: -0.05),
          ),
          SafeArea(
            child: Column(
              children: [
                const MarqueeBar('🎭 Traitors and Faithful  •  five modes, launch-ready  •  bring your friends'),
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
                      _grow(
                        title,
                        titleFade,
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            TextSpan(
                              style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 58, height: 0.92),
                              children: [
                                TextSpan(
                                  text: 'Top',
                                  style: TextStyle(
                                      shadows: [Shadow(color: n.gold.withValues(alpha: 0.4), blurRadius: 34)]),
                                ),
                                TextSpan(
                                  text: 'skul',
                                  style: TextStyle(
                                    color: n.brand,
                                    shadows: [Shadow(color: n.brand.withValues(alpha: 0.45), blurRadius: 34)],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FadeTransition(
                        opacity: subtitle,
                        child: Text(
                          'A social-deduction party game. Pick a mode, open the room, and find the Traitors before they take the castle. 🕵️',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                  child: _grow(
                    buttons,
                    buttonsFade,
                    Column(
                      children: [
                        NeonButton('Sign in with phone',
                            style: NeonStyle.go,
                            onPressed: () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => const PhoneScreen()))),
                        const SizedBox(height: 10),
                        NeonButton(_googleBusy ? 'Connecting…' : 'Continue with Google',
                            style: NeonStyle.gold, onPressed: _googleBusy ? null : () => _google(context)),
                        const SizedBox(height: 10),
                        NeonButton('Play as guest',
                            style: NeonStyle.ghost, onPressed: () => _guest(context)),
                        const SizedBox(height: 12),
                        Text('Play right away on this device. Verify a phone or email later to play from anywhere.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _grow(Animation<double> scale, Animation<double> fade, Widget child) => FadeTransition(
        opacity: fade,
        child: ScaleTransition(scale: scale, alignment: Alignment.bottomLeft, child: child),
      );

  Future<void> _google(BuildContext context) async {
    setState(() => _googleBusy = true);
    final app = AppScope.of(context);
    try {
      final tokens = await app.signInWithGoogle();
      if (tokens == null || !context.mounted) return; // cancelled the picker
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => tokens.newAccount ? const UsernameSetupScreen() : const MainShell()),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is StateError ? e.message : 'Google sign-in failed')));
      }
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _guest(BuildContext context) async {
    final app = AppScope.of(context);
    final nickname = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.neon.panel.withValues(alpha: 0.92),
      builder: (_) => const _NicknameSheet(),
    );
    if (nickname == null || nickname.trim().isEmpty || !context.mounted) return;
    try {
      await app.startGuest(nickname.trim());
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not reach the server')));
      }
    }
  }
}

/// A few soft, blurred color blobs sitting behind the content — the app's
/// "not a straight-edged corporate screen" signature. Purely decorative, so
/// it's excluded from the semantics tree.
class _BlobField extends StatelessWidget {
  const _BlobField({required this.n});
  final NeonColors n;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
        child: Stack(
          children: [
            Positioned(top: -60, right: -50, child: _blob(n.brand, 220)),
            Positioned(top: 220, left: -70, child: _blob(n.gold, 190)),
            Positioned(bottom: -40, right: -30, child: _blob(n.jade, 200)),
          ],
        ),
      ),
    );
  }

  Widget _blob(Color c, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: c.withValues(alpha: 0.22), shape: BoxShape.circle),
      );
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
          Text('PICK A NAME', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.gold)),
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
