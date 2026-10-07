import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../competitive/competitive_models.dart' show gameDisplayName;
import 'spectate_screen.dart';

/// The server refuses a join with this message when the game has already
/// started (`RoomService.ALREADY_PLAYING`). Keep the two in step.
const kAlreadyPlaying = 'already playing';

/// True when a join failed only because the game is live — in which case the
/// person should be taken to watch it, not shown an error.
bool isAlreadyPlaying(Object error) =>
    error is ApiException && error.status == 409 && error.message.toLowerCase().contains(kAlreadyPlaying);

/// Opens the live view of the huud with [code]. Returns whether it opened;
/// when it can't (the game isn't live, a private match) the reason is shown
/// as a message and false is returned.
///
/// Pass the navigator from the app root ([navigator]) when there's no screen
/// context to push from — the in-app game-invite banner has none.
Future<bool> watchHuudByCode(
  AppState app,
  String code, {
  BuildContext? context,
  NavigatorState? navigator,
  ScaffoldMessengerState? messenger,
}) async {
  final nav = navigator ?? (context == null ? null : Navigator.of(context));
  final msg = messenger ?? (context == null ? null : ScaffoldMessenger.of(context));
  try {
    final raw = await app.api.post('/rooms/watch', {'code': code}) as Map;
    final room = RoomView.fromJson(raw.cast<String, dynamic>());
    nav?.push(MaterialPageRoute(
        builder: (_) => SpectateScreen(
              roomId: room.id,
              gameType: room.gameType,
              title: 'Watching ${gameDisplayName(room.gameType)}',
            )));
    return nav != null;
  } on ApiException catch (e) {
    msg?.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    msg?.showSnackBar(const SnackBar(content: Text('Could not reach the server')));
  }
  return false;
}

/// Tells the person what happened as they're taken to the live view.
void announceWatching(ScaffoldMessengerState? messenger) => messenger?.showSnackBar(
    const SnackBar(content: Text('That game has already started — you’re watching it live.')));
