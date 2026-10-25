import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../theme/huud_colors.dart';
import 'username_setup_screen.dart';

/// Selects a starting avatar, not a personal gender field. The saved avatar
/// uses the same account endpoint as Profile, so every Huud sees it immediately.
class AvatarSetupScreen extends StatefulWidget {
  const AvatarSetupScreen({super.key});
  @override
  State<AvatarSetupScreen> createState() => _AvatarSetupScreenState();
}

class _AvatarSetupScreenState extends State<AvatarSetupScreen> {
  String? _body;
  bool _saving = false;
  String? _error;

  Future<void> _continue() async {
    if (_body == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.of(context).api.patch('/me/huud-avatar', {
        'avatarId': _body == 'female' ? 'ella' : 'male',
        'outfitId': 'everyday',
      });
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const UsernameSetupScreen()));
    } catch (_) {
      if (mounted)
        setState(
            () => _error = 'Could not save your avatar. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = HuudColors.of(context);
    return Scaffold(
        body: SafeArea(
            child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Spacer(),
        Icon(Icons.waving_hand_rounded, size: 56, color: h.orangeText),
        const SizedBox(height: 20),
        Text('Choose your first avatar',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        const Text(
            'How would you like to appear in The Huud? Pick a male or female avatar to get started.',
            textAlign: TextAlign.center),
        const SizedBox(height: 28),
        Row(children: [
          for (final body in ['male', 'female']) ...[
            if (body == 'female') const SizedBox(width: 12),
            Expanded(
                child: Semantics(
                    selected: _body == body,
                    child: InkWell(
                      key: ValueKey('onboarding-avatar-$body'),
                      borderRadius: BorderRadius.circular(24),
                      onTap:
                          _saving ? null : () => setState(() => _body = body),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            vertical: 28, horizontal: 12),
                        decoration: BoxDecoration(
                            color: _body == body
                                ? h.orangeSoft
                                : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: _body == body
                                    ? h.orange
                                    : Theme.of(context).dividerColor,
                                width: 2)),
                        child: Column(children: [
                          Icon(
                              body == 'male'
                                  ? Icons.man_rounded
                                  : Icons.woman_rounded,
                              size: 80,
                              color: h.orangeText),
                          const SizedBox(height: 12),
                          Text(body == 'male' ? 'Male' : 'Female',
                              style: const TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          Icon(
                              _body == body
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              color: h.orangeText),
                        ]),
                      ),
                    ))),
          ]
        ]),
        const SizedBox(height: 20),
        const Text(
            'You can change your character and clothes in Profile anytime.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13)),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        const Spacer(flex: 2),
        FilledButton(
          key: const ValueKey('onboarding-avatar-continue'),
          style: FilledButton.styleFrom(
              backgroundColor: h.orange,
              foregroundColor: h.onOrange,
              padding: const EdgeInsets.all(18)),
          onPressed: _body == null || _saving ? null : _continue,
          child: Text(_saving ? 'Saving…' : 'Continue'),
        ),
      ]),
    )));
  }
}
