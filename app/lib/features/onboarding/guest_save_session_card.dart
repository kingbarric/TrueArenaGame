import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import 'phone_screen.dart';
import '../shell/main_shell.dart';
import '../../core/api_client.dart';

/// Shown on a Results screen when the player who just finished a game is a
/// guest — the natural moment to ask, since they've just seen the app deliver
/// value and are about to either leave or want to host their own game next.
/// A no-op (renders nothing) for a real account. Verifying here upgrades the
/// same guest id in place (`AppState.startGuest` / `POST /auth/guest` +
/// `/otp/verify`'s upgrade path — see docs/DEV_REFERENCE.md), so nothing
/// about the game just played is lost.
class GuestSaveSessionCard extends StatelessWidget {
  const GuestSaveSessionCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.identity != Identity.guest) return const SizedBox.shrink();
    final n = context.neon;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: NeonCard(
        accent: n.jade,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Save this session?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Verify a phone, email, or Google account to keep today\'s games and host your own next time — '
            'no need to play as a guest again.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: n.mid),
          ),
          const SizedBox(height: 12),
          NeonButton(
            'Verify a phone or email',
            style: NeonStyle.ghost,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PhoneScreen())),
          ),
          const SizedBox(height: 8),
          NeonButton(
            'Continue with Google',
            style: NeonStyle.gold,
            onPressed: () async {
              try {
                final tokens = await app.signInWithGoogle();
                if (tokens == null || !context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MainShell()), (route) => false);
              } on ApiException catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Google sign-in failed')));
                }
              }
            },
          ),
        ]),
      ),
    );
  }
}
