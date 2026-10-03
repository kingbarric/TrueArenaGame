import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/motif.dart';
import '../../widgets/neon.dart';
import 'otp_screen.dart';

/// Email code sign in. Phone/SMS delivery is shelved for now.
class EmailScreen extends StatefulWidget {
  const EmailScreen({super.key});

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
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
    if (!value.contains('@') || !value.contains('.')) {
      setState(() => _error = 'Enter a valid email');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final api = AppScope.of(context).api;
    try {
      await api.post('/auth/otp/request', {'email': value});
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OtpScreen(identifier: value, isEmail: true)));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in with email')),
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
                  Text('YOUR EMAIL',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: n.mute, letterSpacing: 1.6)),
                  const SizedBox(height: 18),
                  Text('WE’LL EMAIL YOU A CODE',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: n.gold)),
                  const SizedBox(height: 6),
                  Text(
                    'Your email keeps your friends, groups, and game history.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: n.mid),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'you@example.com',
                      prefixIcon: Icon(Icons.alternate_email),
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
