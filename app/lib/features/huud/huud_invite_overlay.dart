import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../core/hangout_state.dart';
import 'social_huud_models.dart';
import 'social_huud_screen.dart';

Future<void> openHuudInvite(AppState state, String code) async {
  final raw =
      await state.api.post('/huuds/sessions/code', {'code': code}) as Map;
  final navigator = HangoutState.instance.navigationKey.currentState;
  if (navigator == null) return;
  await navigator.push(MaterialPageRoute(
      builder: (_) => SocialHuudScreen(
          initial: SocialHuud.fromJson(raw.cast<String, dynamic>()))));
}

class HuudInviteOverlay extends StatefulWidget {
  const HuudInviteOverlay(
      {super.key, required this.state, required this.child});
  final AppState state;
  final Widget child;
  @override
  State<HuudInviteOverlay> createState() => _HuudInviteOverlayState();
}

class _HuudInviteOverlayState extends State<HuudInviteOverlay> {
  bool _opening = false;
  Future<void> _open(String code) async {
    setState(() => _opening = true);
    try {
      widget.state.dismissHuudInvite();
      await openHuudInvite(widget.state, code);
    } catch (_) {
      final context = HangoutState.instance.navigationKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('This Huud is unavailable. Try its code again.')));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.state.pendingHuudInvite;
    return Stack(children: [
      widget.child,
      if (invite != null)
        Positioned(
            top: 0,
            left: 12,
            right: 12,
            child: SafeArea(
                child: Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                        child: Text(
                            'You’re invited to ${invite['name'] ?? 'a Huud'}')),
                    TextButton(
                        onPressed:
                            _opening ? null : widget.state.dismissHuudInvite,
                        child: const Text('Dismiss')),
                    FilledButton(
                        onPressed: _opening
                            ? null
                            : () => _open(invite['code'] as String),
                        child: const Text('Watch')),
                  ])),
            ))),
    ]);
  }
}
