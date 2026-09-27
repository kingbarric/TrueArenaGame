import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../shell/main_shell.dart';
import 'username_setup_screen.dart';

const _kResendCooldown = Duration(seconds: 60);

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.identifier, required this.isEmail});

  final String identifier;
  final bool isEmail;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _controller = TextEditingController();
  bool _verifying = false;
  String? _error;

  bool _resending = false;
  int _secondsLeft = _kResendCooldown.inSeconds;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _controller.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsLeft = _kResendCooldown.inSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    final api = AppScope.of(context).api;
    try {
      await api.post('/auth/otp/request', {widget.isEmail ? 'email' : 'phone': widget.identifier});
      if (!mounted) return;
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Code resent to ${widget.identifier}')));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verify() async {
    final code = _controller.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    final app = AppScope.of(context);
    try {
      final res = await app.api.post('/auth/otp/verify', {
        widget.isEmail ? 'email' : 'phone': widget.identifier,
        'code': code,
      });
      final tokens = AuthTokens.fromJson(res as Map<String, dynamic>);
      await app.completeAccountSignIn(tokens);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => tokens.newAccount ? const UsernameSetupScreen() : const MainShell()),
        (route) => false,
      );
    } on ApiException catch (e) {
      setState(() => _error = e.status == 401 ? 'That code didn’t work — try again' : e.message);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: const Text('Enter code')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('SENT TO ${widget.identifier}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.gold)),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 34, letterSpacing: 10),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(counterText: '', hintText: '••••••'),
                onSubmitted: (_) => _verify(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: TextStyle(color: n.danger, fontSize: 12)),
              ],
              const SizedBox(height: 14),
              Center(
                child: _secondsLeft > 0
                    ? Text('Resend code in ${_secondsLeft}s',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute))
                    : TextButton(
                        onPressed: _resending ? null : _resend,
                        child: Text(_resending ? 'Resending…' : 'Resend code',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.gold)),
                      ),
              ),
              const Spacer(),
              NeonButton(_verifying ? 'Checking…' : 'Verify', onPressed: _verifying ? null : _verify),
            ],
          ),
        ),
      ),
    );
  }
}
