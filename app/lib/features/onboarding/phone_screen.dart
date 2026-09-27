import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/motif.dart';
import '../../widgets/neon.dart';
import 'otp_screen.dart';

enum _Channel { phone, email }

/// Registration entry point — phone or email, either verified with the same
/// 6-digit OTP flow (see docs/DEV_REFERENCE.md §2). No name/username here —
/// verification comes first, then [UsernameSetupScreen] handles the handle.
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  _Channel _channel = _Channel.phone;
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final value = _controller.text.trim();
    final isEmail = _channel == _Channel.email;
    if (isEmail
        ? !value.contains('@') || !value.contains('.')
        : value.replaceAll(RegExp(r'[^0-9]'), '').length < 6) {
      setState(() => _error =
          isEmail ? 'Enter a valid email' : 'Enter a valid phone number');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final api = AppScope.of(context).api;
    try {
      await api.post('/auth/otp/request', {isEmail ? 'email' : 'phone': value});
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OtpScreen(identifier: value, isEmail: isEmail)));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _switchChannel(_Channel c) {
    if (c == _channel) return;
    setState(() {
      _channel = c;
      _controller.clear();
      _error = null;
    });
  }

  /// Two solid pill buttons side by side — plain text, no icons. The active
  /// one is a filled pill; the other sits flat until tapped.
  Widget _channelPill(NeonColors n, {required String label, required bool selected, required VoidCallback onTap}) {
    return Expanded(
      child: Bouncy(
        onTap: onTap,
        pressScale: 0.95,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? n.brand : n.plate,
            borderRadius: BorderRadius.circular(NeonRadius.pill),
            border: Border.all(color: kCabinetInk, width: 2),
          ),
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontSize: 15, color: selected ? Colors.white : n.mid),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final isEmail = _channel == _Channel.email;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign up / sign in')),
      body: Stack(
        children: [
          // Small and low so it never sits behind the form fields or the
          // Send Code button — this screen has less empty room than Home/Welcome.
          Positioned(right: -40, bottom: -20, child: DrumMotif(color: n.ink, size: 170)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('HOW DO WE REACH YOU?',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: n.mute, letterSpacing: 1.6)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _channelPill(n, label: 'Phone', selected: !isEmail, onTap: () => _switchChannel(_Channel.phone)),
                      const SizedBox(width: 10),
                      _channelPill(n, label: 'Email', selected: isEmail, onTap: () => _switchChannel(_Channel.email)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                      isEmail
                          ? 'WE’LL EMAIL YOU A CODE'
                          : 'WE’LL TEXT YOU A CODE',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: n.gold)),
                  const SizedBox(height: 6),
                  Text(
                    isEmail
                        ? 'One tap-through. Your email is the account — friends, groups, history.'
                        : 'One tap-through. Your number is the account — friends, groups, history.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: n.mid),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: ValueKey(_channel),
                    controller: _controller,
                    autofocus: true,
                    keyboardType: isEmail
                        ? TextInputType.emailAddress
                        : TextInputType.phone,
                    inputFormatters: isEmail
                        ? null
                        : [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9+ ]'))
                          ],
                    decoration: InputDecoration(
                      hintText: isEmail ? 'you@example.com' : '+1 555 010 0000',
                      prefixIcon: Icon(isEmail
                          ? Icons.alternate_email
                          : Icons.phone_outlined),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!,
                        style: TextStyle(color: n.danger, fontSize: 12)),
                  ],
                  const Spacer(),
                  NeonButton(_sending ? 'Sending…' : 'Send code',
                      onPressed: _sending ? null : _send),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
