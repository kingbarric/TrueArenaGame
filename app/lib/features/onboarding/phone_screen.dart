import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import 'otp_screen.dart';

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final phone = _controller.text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.length < 6) {
      setState(() => _error = 'Enter a valid phone number');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final api = AppScope.of(context).api;
    try {
      await api.post('/auth/otp/request', {'phone': phone});
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => OtpScreen(phone: phone)));
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
      appBar: AppBar(title: const Text('Your number')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('WE’LL TEXT YOU A CODE',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.cyan)),
              const SizedBox(height: 6),
              Text('One tap-through. Your number is the account — friends, groups, history.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: n.mid)),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                decoration: const InputDecoration(hintText: '+1 555 010 0000', prefixIcon: Icon(Icons.phone_outlined)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: n.danger, fontSize: 12)),
              ],
              const Spacer(),
              NeonButton(_sending ? 'Sending…' : 'Send code', onPressed: _sending ? null : _send),
            ],
          ),
        ),
      ),
    );
  }
}
