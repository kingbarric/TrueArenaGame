import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import 'phone_screen.dart';

/// Guests can browse every screen and join any room, but hosting (creating)
/// a game needs a real account — see `RoomService.create`'s server-side
/// enforcement, which this mirrors client-side with a friendlier prompt
/// instead of just letting the request come back a 403. Call this right at
/// the moment a guest would actually create a room (tapping "Open the room"
/// / picking a game to host), not any earlier — they should still be able to
/// browse mode/game selection freely.
///
/// Returns `true` if it's fine to proceed with hosting. Returns `false` if
/// the caller is a guest — the dialog itself offers a way to verify right
/// there, so the caller doesn't need to.
Future<bool> canHostOrPromptToVerify(BuildContext context) async {
  final app = AppScope.of(context);
  if (app.identity != Identity.guest) return true;

  final verify = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Register to host a game'),
      content: const Text(
        'Guests can join any game with a room code, but starting a new one needs a '
        'phone or email — that way there\'s a way to reach you and hand the room off '
        'to you if you reconnect.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Not now')),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Verify now'),
        ),
      ],
    ),
  );
  if (verify == true && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PhoneScreen()));
  }
  return false;
}

/// Same shape as [canHostOrPromptToVerify], for the friends feature — a
/// guest has no durable identity to be found by or reconnect as, so friends
/// (and the invites/spectating/messaging built on top of it) are registered-
/// players only.
Future<bool> canUseFriendsOrPromptToVerify(BuildContext context) async {
  final app = AppScope.of(context);
  if (app.identity != Identity.guest) return true;

  final verify = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Register to add friends'),
      content: const Text(
        'Friends need a real account on both sides — a guest identity clears when '
        'this device stops playing, so there\'d be nothing to stay friends with.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Not now')),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Verify now'),
        ),
      ],
    ),
  );
  if (verify == true && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PhoneScreen()));
  }
  return false;
}
