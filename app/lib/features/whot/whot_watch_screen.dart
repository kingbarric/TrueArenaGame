import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../core/game_socket.dart';
import '../../core/models.dart';
import 'whot_game_screen.dart';

/// Opens a spectator connection without joining the room or taking a seat.
class WhotWatchScreen extends StatefulWidget {
  const WhotWatchScreen({super.key, required this.roomId});
  final String roomId;
  @override
  State<WhotWatchScreen> createState() => _WhotWatchScreenState();
}

class _WhotWatchScreenState extends State<WhotWatchScreen> {
  GameSocket? _socket;
  String _selfId = '';
  String? _roomCode;
  Map<String, String> _names = {};
  Map<String, String> _avatars = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_socket != null) return;
    final app = AppScope.of(context);
    _selfId = app.user?.id ?? '';
    // WhotGameScreen owns and closes this connection, including reconnects.
    _socket = GameSocket.connect(app.api, widget.roomId, spectate: true);
    app.api.get('/rooms/${widget.roomId}').then((raw) {
      if (!mounted) return;
      final room = RoomView.fromJson((raw as Map).cast<String, dynamic>());
      setState(() {
        _roomCode = room.code;
        _names = {
          for (var i = 0; i < room.members.length; i++)
            room.members[i].userId:
                room.members[i].nickname ?? 'Player ${i + 1}',
        };
        _avatars = {
          for (final member in room.members)
            if (member.avatarUrl?.isNotEmpty == true)
              member.userId: member.avatarUrl!
            else if (member.isBot)
              member.userId: '🤖'
        };
      });
    }).catchError((_) {
      // Public game snapshots still render if fetching display names fails.
    });
  }

  @override
  Widget build(BuildContext context) => WhotGameScreen(
        socket: _socket!,
        selfId: _selfId,
        roomId: widget.roomId,
        roomCode: _roomCode,
        nicknames: _names,
        avatars: _avatars,
        spectating: true,
      );
}
