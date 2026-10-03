import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/game_socket.dart';
import '../../core/models.dart';
import 'ludo_game_screen.dart';

class LudoWatchScreen extends StatefulWidget {
  const LudoWatchScreen({super.key, required this.roomId});
  final String roomId;

  @override
  State<LudoWatchScreen> createState() => _LudoWatchScreenState();
}

class _LudoWatchScreenState extends State<LudoWatchScreen> {
  GameSocket? _socket;
  String _selfId = '', _code = '';
  Map<String, String> _names = {};
  Set<String> _agents = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_socket != null) return;
    final app = AppScope.of(context);
    _selfId = app.user?.id ?? '';
    _socket = GameSocket.connect(app.api, widget.roomId, spectate: true);
    app.api.get('/rooms/${widget.roomId}').then((raw) {
      if (!mounted) return;
      final room = RoomView.fromJson((raw as Map).cast<String, dynamic>());
      setState(() {
        _code = room.code;
        _names = {
          for (final m in room.members) m.userId: m.nickname ?? m.userId
        };
        _agents = {
          for (final m in room.members)
            if (m.isBot) m.userId
        };
      });
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => LudoGameScreen(
      socket: _socket!,
      selfId: _selfId,
      roomCode: _code,
      nicknames: _names,
      agents: _agents,
      spectating: true);
}
