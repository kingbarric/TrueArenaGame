import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import 'welcome_screen.dart';

/// Shared by every screen that offers a way to sign out (Profile, Settings —
/// deliberately more than one, since burying it behind a single path is
/// exactly what made it hard to find before). Confirms first for a real
/// session, clears it, then always lands on Welcome regardless of how deep
/// in the navigator stack the tap happened — see the comment inline for why
/// that last part needs doing explicitly rather than relying on `AppState`'s
/// `notifyListeners()` alone.
Future<void> confirmSignOut(BuildContext context, AppState app) async {
  final n = context.neon;
  final wasAnonymous = app.identity == Identity.anonymous;
  final confirmed = wasAnonymous
      ? true // nothing to confirm — there's no session to lose, just take them home
      : await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Sign out?'),
            content: Text(app.identity == Identity.guest
                ? 'This device\'s guest session will be cleared — add an email first if you want to keep it.'
                : 'You\'ll need to sign in again to host or join real games.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('Sign out', style: TextStyle(color: n.danger)),
              ),
            ],
          ),
        );
  if (confirmed != true) return;
  if (!wasAnonymous) await app.signOut();
  if (!context.mounted) return;
  // Sign-out flips AppState.identity, but MaterialApp's `home` only reads
  // that at a fresh app launch — the navigator's existing stack (Profile →
  // Settings, or deeper) isn't retroactively unwound by it, and the root
  // route itself was built once with whatever screen was current back then,
  // not a live reflection of identity. Replace the whole stack explicitly so
  // Sign out always actually lands on Welcome, from anywhere it's called.
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    (route) => false,
  );
}
