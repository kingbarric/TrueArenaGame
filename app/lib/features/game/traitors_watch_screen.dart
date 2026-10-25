import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/game_socket.dart';
import '../../core/models.dart';
import 'game_screen.dart';

/// Watching a Traitors game without a seat: the real table — everyone around
/// it by name, the round-table talk, the countdown reveals — read-only, with
/// the audience's own comments and reactions.
class TraitorsWatchScreen extends StatefulWidget {
  const TraitorsWatchScreen({super.key, required this.roomId});
  final String roomId;

  @override
  State<TraitorsWatchScreen> createState() => _TraitorsWatchScreenState();
}

class _TraitorsWatchScreenState extends State<TraitorsWatchScreen> {
  GameSocket? _socket;
  String _selfId = '';
  Map<String, String> _names = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_socket != null) return;
    final app = AppScope.of(context);
    _selfId = app.user?.id ?? '';
    // GameScreen owns and closes this connection, including reconnects.
    _socket = GameSocket.connect(app.api, widget.roomId, spectate: true);
    app.api.get('/rooms/${widget.roomId}').then((raw) {
      if (!mounted) return;
      final room = RoomView.fromJson((raw as Map).cast<String, dynamic>());
      setState(() => _names = {
            for (var i = 0; i < room.members.length; i++)
              room.members[i].userId: room.members[i].nickname ?? 'Player ${i + 1}',
          });
    }).catchError((_) {
      // The table still plays out without names; seats fall back to short ids.
    });
  }

  @override
  Widget build(BuildContext context) =>
      GameScreen(socket: _socket!, selfId: _selfId, isHost: false, nicknames: _names, spectating: true);
}
