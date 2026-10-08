import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/game_socket.dart';
import '../../core/models.dart';
import '../chess/chess_game_screen.dart';
import '../draughts/draughts_game_screen.dart';
import '../goosi/goosi_game_screen.dart';
import '../whot/whot_game_screen.dart';
import '../ludo/ludo_game_screen.dart';
import '../wordbluff/wordbluff_game_screen.dart';
import '../game/game_screen.dart';
import '../spectate/spectate_screen.dart';
import 'social_huud_controller.dart';
import 'social_huud_screen.dart';

/// Keeps the Huud controller and its chat/voice around the temporary game screen.
class SocialHuudGameScreen extends StatefulWidget {
  const SocialHuudGameScreen(
      {super.key, required this.controller, this.onBrowse});
  final SocialHuudController controller;
  final ValueChanged<int>? onBrowse;
  @override
  State<SocialHuudGameScreen> createState() => _SocialHuudGameScreenState();
}

class _SocialHuudGameScreenState extends State<SocialHuudGameScreen> {
  late final String _roomId = widget.controller.huud.currentRoomId!;
  RoomView? _room;
  GameSocket? _socket;
  String? _error;
  bool _closing = false;
  bool? _player;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await widget.controller.api.get('/rooms/$_roomId') as Map;
      if (!mounted) return;
      final room = RoomView.fromJson(raw.cast<String, dynamic>());
      final player = widget.controller.huud.selectedPlayers
          .contains(widget.controller.userId);
      setState(() {
        _player = player;
        _room = room;
        if (room.gameType != 'truearena' || player) {
          _socket = GameSocket.connect(widget.controller.api, _roomId,
              spectate: !player);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Could not open the game. Return to your Huud to retry.');
      }
    }
  }

  void _changed() {
    final c = widget.controller;
    if (!mounted || _closing) return;
    if (c.unavailable ||
        c.huud.currentRoomId != _roomId ||
        c.huud.activity == 'idle' ||
        c.huud.waiting) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } else if (_player != null &&
        _player != c.huud.selectedPlayers.contains(c.userId)) {
      _player = null;
      _socket?.close();
      _socket = null;
      setState(() => _room = null);
      _load();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _socket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, room = _room, socket = _socket;
    if (room == null) {
      return Scaffold(
          appBar: AppBar(title: Text(c.huud.name)),
          body: Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!)));
    }
    final names = {
      for (final m in room.members) m.userId: m.nickname ?? 'Player'
    };
    final avatars = {
      for (final m in room.members)
        if (m.avatarUrl != null) m.userId: m.avatarUrl!
    };
    final watching = !c.huud.selectedPlayers.contains(c.userId);
    final canBrowse =
        watching && !c.huud.participant && !c.isHost && widget.onBrowse != null;
    final Widget game = switch (room.gameType) {
      'draughts' => DraughtsGameScreen(
          socket: socket!,
          selfId: c.userId,
          nicknames: names,
          spectating: watching),
      'whot' => WhotGameScreen(
          socket: socket!,
          selfId: c.userId,
          roomId: room.id,
          roomCode: c.huud.code,
          nicknames: names,
          avatars: avatars,
          spectating: watching),
      'chess' => ChessGameScreen(
          socket: socket!,
          selfId: c.userId,
          nicknames: names,
          roomCode: c.huud.code,
          avatars: avatars,
          spectating: watching),
      'ludo' => LudoGameScreen(
          socket: socket!,
          selfId: c.userId,
          nicknames: names,
          roomCode: c.huud.code,
          spectating: watching),
      'goosi' => GoosiGameScreen(
          socket: socket!,
          selfId: c.userId,
          nicknames: names,
          roomCode: c.huud.code,
          avatars: avatars,
          spectating: watching),
      'wordbluff' => WordBluffGameScreen(
          socket: socket!,
          selfId: c.userId,
          isHost: c.isHost,
          nicknames: names,
          spectating: watching),
      _ => watching
          ? SpectateScreen(
              roomId: room.id, title: c.huud.name, gameType: room.gameType)
          : GameScreen(
              socket: socket!,
              selfId: c.userId,
              isHost: c.isHost,
              nicknames: names),
    };
    return SocialHuudScope(
        controller: c,
        child: Column(children: [
          Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                  bottom: false,
                  child: Row(children: [
                    TextButton.icon(
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Huud'),
                        onPressed: () => Navigator.of(context).pop()),
                    Expanded(
                        child: Text(c.huud.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    IconButton(
                        tooltip: 'Huud people and controls',
                        icon: const Icon(Icons.people_outline),
                        onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            backgroundColor:
                                Theme.of(context).colorScheme.surface,
                            builder: (_) => SizedBox(
                                height: MediaQuery.sizeOf(context).height * .8,
                                child: ListenableBuilder(
                                    listenable: c,
                                    builder: (context, _) =>
                                        HuudContents(controller: c))))),
                  ]))),
          if (canBrowse)
            const Text('Swipe up for the next Huud · down for the previous'),
          if (watching && c.huud.gameRequestStatus == 'closed')
            const Text('Not selected for this game · You’re watching'),
          Expanded(
              child: GestureDetector(
                  onVerticalDragEnd: canBrowse
                      ? (details) {
                          final speed = details.primaryVelocity ?? 0;
                          if (speed.abs() > 250) {
                            widget.onBrowse!(speed < 0 ? 1 : -1);
                          }
                        }
                      : null,
                  child: game)),
        ]));
  }
}
