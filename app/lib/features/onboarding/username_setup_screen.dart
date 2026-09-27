import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../shell/main_shell.dart';

/// Shown once, right after a brand-new account's first OTP verify (see
/// `AuthTokens.newAccount`). A username already exists at this point — the
/// backend auto-generated one at signup — this just offers the chance to
/// pick a real one instead of keeping the random handle.
class UsernameSetupScreen extends StatefulWidget {
  const UsernameSetupScreen({super.key});

  @override
  State<UsernameSetupScreen> createState() => _UsernameSetupScreenState();
}

class _UsernameSetupScreenState extends State<UsernameSetupScreen> {
  late final _controller = TextEditingController(text: AppScope.of(context).user?.username ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final username = _controller.text.trim();
    if (username.length < 3) {
      setState(() => _error = 'At least 3 characters');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final app = AppScope.of(context);
    try {
      if (username != app.user?.username) {
        await app.setUsername(username);
      }
      _goHome();
    } catch (e) {
      setState(() => _error = e.toString().contains('409') ? 'That username is taken' : 'Could not save — try another');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainShell()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Text('🎭', style: TextStyle(fontSize: 48), textAlign: TextAlign.center),
              const SizedBox(height: 14),
              Text('Pick your username', textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28)),
              const SizedBox(height: 8),
              Text(
                'This is how other players see you at the table. We picked one for you — keep it, or change it now.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 24,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]'))],
                decoration: const InputDecoration(hintText: 'king_of_traitors', counterText: '', prefixIcon: Icon(Icons.alternate_email)),
                onSubmitted: (_) => _save(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: n.danger, fontSize: 12)),
              ],
              const Spacer(flex: 2),
              NeonButton(_saving ? 'Saving…' : 'Save and continue', onPressed: _saving ? null : _save),
              const SizedBox(height: 10),
              NeonButton('Keep this one', style: NeonStyle.ghost, onPressed: _saving ? null : _goHome),
            ],
          ),
        ),
      ),
    );
  }
}
