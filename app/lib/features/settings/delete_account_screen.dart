import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/app_state.dart';
import '../../core/api_client.dart';
import '../../theme/neon_theme.dart';
import '../onboarding/welcome_screen.dart';

/// Account erasure is distinct from sign out and is available to guests too.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _delete() async {
    final app = AppScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Permanently delete your account?'),
        content: const Text(
            'Your profile, messages, posts, friends, coins and personal game records '
            'will be removed. Groups and Huuds you host will be removed and games you are in will end. '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep account')),
          TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text('Delete permanently',
                  style: TextStyle(color: context.neon.danger))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final requirements = await app.api
          .get('/me/account/deletion-requirements') as Map<String, dynamic>;
      final body = <String, dynamic>{'confirmed': true};
      if (requirements['appleLinked'] == true) {
        if (requirements['appleRevocationReady'] != true) {
          if (mounted) {
            setState(() => _message =
                'Account deletion is temporarily unavailable. Please try again later.');
          }
          return;
        }
        final challenge =
            await app.api.post('/auth/apple/challenge') as Map<String, dynamic>;
        final nonce = challenge['nonce'] as String;
        final credential = await SignInWithApple.getAppleIDCredential(
            scopes: const [], nonce: nonce);
        body.addAll({
          'appleIdToken': credential.identityToken,
          'appleNonce': nonce,
          'appleAuthorizationCode': credential.authorizationCode,
        });
      }
      await app.deleteAccount(body);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false);
    } on SignInWithAppleAuthorizationException catch (error) {
      if (mounted && error.code != AuthorizationErrorCode.canceled) {
        setState(() => _message =
            'Apple could not confirm your account. Nothing has been deleted.');
      }
    } catch (_) {
      if (mounted) setState(() => _message = userRetryMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Delete account')),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Permanently remove your PlayHuud account',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text(
              'This removes your profile and personal data, including your messages, posts, '
              'friends, coins and personal game records. Guest accounts can be deleted here too.'),
          const SizedBox(height: 12),
          const Text(
              'Groups and Huuds you host will be removed. Games involving your account will end. '
              'Other players keep their own accounts and rating records, without your player identity.'),
          const SizedBox(height: 12),
          const Text(
              'Stored outfit images are queued for removal. Limited backup copies expire under '
              'our privacy policy. Signing in again creates a new account; it does not restore deleted data.'),
          const SizedBox(height: 12),
          const Text(
              'If you use Sign in with Apple, Apple will ask you to confirm that account before deletion.'),
          const SizedBox(height: 24),
          if (_message != null) ...[
            Text(_message!),
            const SizedBox(height: 16)
          ],
          FilledButton(
            onPressed: _busy ? null : _delete,
            style: FilledButton.styleFrom(backgroundColor: context.neon.danger),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Delete account'),
          ),
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Keep account')),
        ])),
      );
}
