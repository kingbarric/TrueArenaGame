import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/hangout_state.dart';
import '../core/models.dart';
import '../features/lobby/joined_room_screen.dart';

/// Check before showing setup sheets: an existing code keeps its original rules.
Future<bool> resumePendingHuud(
    BuildContext context, AppState app, String gameType) async {
  if (app.identity == Identity.anonymous) return false;
  final raw = await app.api.get('/rooms/pending/$gameType');
  if (raw == null) return false;
  final room = RoomView.fromJson((raw as Map).cast<String, dynamic>());
  if (HangoutState.instance.active) {
    await app.api.post('/rooms/${room.id}/play-together');
  }
  await app.rememberActiveRoom(room.id);
  if (!context.mounted) return true;
  Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => JoinedRoomScreen(room: room)));
  return true;
}

bool handleCancelledHuud(
    BuildContext context, Map<String, dynamic> envelope, String roomId) {
  if (envelope['type'] != 'EVENT' ||
      (envelope['payload'] as Map?)?['type'] != 'ROOM_CANCELLED') return false;
  AppScope.of(context).clearActiveRoom(roomId);
  ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The host cancelled this Huud')));
  Navigator.of(context).pop();
  return true;
}
