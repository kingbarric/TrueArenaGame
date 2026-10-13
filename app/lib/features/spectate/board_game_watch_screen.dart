import '../../core/api_client.dart' show userErrorMessage;
import '../monopoly/monopoly_game_screen.dart';
import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/game_socket.dart';
import '../../core/models.dart';
import '../chess/chess_game_screen.dart';
import '../draughts/draughts_game_screen.dart';
import '../goosi/goosi_game_screen.dart';
import '../wordbluff/wordbluff_game_screen.dart';

/// Opens the game board on a spectator-only socket.
class BoardGameWatchScreen extends StatefulWidget {
  const BoardGameWatchScreen({super.key, required this.roomId, this.title, this.subtitle});

  final String roomId;

  /// A championship's name and round, for the top of a Chess or Draughts board.
  final String? title, subtitle;

  @override
  State<BoardGameWatchScreen> createState() => _BoardGameWatchScreenState();
}

class _BoardGameWatchScreenState extends State<BoardGameWatchScreen> {
  RoomView? _room;
  GameSocket? _socket;
  String _selfId = '';
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final app = AppScope.of(context);
    _selfId = app.user?.id ?? '';
    app.api.get('/rooms/${widget.roomId}').then((raw) {
      if (!mounted) return;
      final room = RoomView.fromJson((raw as Map).cast<String, dynamic>());
      final socket = GameSocket.connect(app.api, room.id, spectate: true);
      setState(() {
        _room = room;
        _socket = socket;
      });
    }).catchError((_) {
      if (mounted) setState(() => _error = userErrorMessage);
    });
  }

  @override
  void dispose() {
    if (_room == null) _socket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final socket = _socket;
    if (room == null || socket == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Watch live')),
        body: Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : Text(userErrorMessage)),
      );
    }
    final names = {
      for (final member in room.members)
        member.userId: member.nickname ?? member.userId,
    };
    if (room.gameType == 'monopoly') {
      return MonopolyGameScreen(
          socket: socket,
          selfId: _selfId,
          nicknames: names,
          roomCode: room.code,
          spectating: true);
    }
    if (room.gameType == 'chess') {
      return ChessGameScreen(
        socket: socket,
        selfId: _selfId,
        nicknames: names,
        roomCode: room.code,
        agents: {
          for (final member in room.members)
            if (member.isBot) member.userId
        },
        spectating: true,
        title: widget.title,
        subtitle: widget.subtitle,
      );
    }
    if (room.gameType == 'draughts') {
      return DraughtsGameScreen(
        socket: socket,
        selfId: _selfId,
        nicknames: names,
        spectating: true,
        title: widget.title,
        subtitle: widget.subtitle,
      );
    }
    if (room.gameType == 'wordbluff') {
      return WordBluffGameScreen(
        socket: socket,
        selfId: _selfId,
        isHost: false,
        nicknames: names,
        spectating: true,
      );
    }
    return GoosiGameScreen(
      socket: socket,
      selfId: _selfId,
      roomCode: room.code,
      nicknames: names,
      agents: {
        for (final member in room.members)
          if (member.isBot) member.userId
      },
      spectating: true,
    );
  }
}
