import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../shell/main_shell.dart';
import 'huud_space_screen.dart';

/// Leaving a game — it ended, someone won, or you exited: a game that was
/// played in a Huud takes you back into that Huud; any other game, home.
///
/// If the Huud is already under the game on the stack, it's just popped back
/// to; otherwise (say the game was reopened on launch) home is rebuilt with
/// the Huud on top, so Back from the Huud still lands on the main tabs.
Future<void> leaveGame(BuildContext context, String roomId) async {
  final nav = Navigator.of(context);
  final huudId = await _huudOf(context, roomId);
  if (huudId != null) {
    var found = false;
    nav.popUntil((route) {
      found = route.settings.name == huudRouteName(huudId);
      return found || route.isFirst;
    });
    if (found) return;
  }
  nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainShell()), (_) => false);
  if (huudId != null) nav.push(huudRoute(huudId));
}

Future<String?> _huudOf(BuildContext context, String roomId) async {
  try {
    final raw = await AppScope.of(context).api.get('/huud-spaces/by-room/$roomId').timeout(const Duration(seconds: 4));
    if (raw is Map && raw['id'] != null && raw['status'] != 'ended') return raw['id'].toString();
  } catch (_) {
    // Not a Huud game, or we can't tell — home it is.
  }
  return null;
}
