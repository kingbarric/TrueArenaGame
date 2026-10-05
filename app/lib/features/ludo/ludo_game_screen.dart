import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/game_music.dart';
import '../../core/game_sfx.dart';
import '../../core/game_socket.dart';
import '../../core/app_state.dart';
import '../../widgets/copyable_huud_code.dart';
import '../../widgets/game_voice_control.dart';
import '../../widgets/how_to_play_dialog.dart';
import '../../widgets/table_chat.dart';

enum _LudoBoardTheme { classic, glass, wood }

class LudoGameScreen extends StatefulWidget {
  const LudoGameScreen(
      {super.key,
      required this.socket,
      required this.selfId,
      required this.nicknames,
      required this.roomCode,
      this.agents = const {},
      this.spectating = false});

  final GameSocket socket;
  final String selfId, roomCode;
  final Map<String, String> nicknames;
  final Set<String> agents;
  final bool spectating;

  @override
  State<LudoGameScreen> createState() => _LudoGameScreenState();
}

class _LudoGameScreenState extends State<LudoGameScreen>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xff180d20);
  static const _panel = Color(0xff26142d);
  static const _gold = Color(0xffffcf66);
  static const _cream = Color(0xffffeee1);
  static const _colors = [
    Color(0xffe83d47),
    Color(0xff17ad67),
    Color(0xffffcd21),
    Color(0xff2474df)
  ];
  static final _track = <(int, int)>[
    for (var c = 1; c <= 5; c++) (6, c),
    for (var r = 5; r >= 0; r--) (r, 6),
    (0, 7),
    (0, 8),
    for (var r = 1; r <= 5; r++) (r, 8),
    for (var c = 9; c <= 14; c++) (6, c),
    (7, 14),
    for (var c = 14; c >= 9; c--) (8, c),
    for (var r = 9; r <= 14; r++) (r, 8),
    (14, 7),
    (14, 6),
    for (var r = 13; r >= 9; r--) (r, 6),
    for (var c = 5; c >= 0; c--) (8, c),
    (7, 0),
    (6, 0),
  ];
  late final AnimationController _cup;
  StreamSubscription? _sub;
  Timer? _ticker, _rollTimer, _rollFeedbackTimer;
  final _chatController = TextEditingController();
  final _chat = <TableChatLine>[];
  Map<String, dynamic> _state = {};
  int _seconds = 60;
  int? _selectedDie;
  List<int> _lastRolled = [];
  String? _rollOwner;
  bool _noMoveRoll = false;
  bool _rolling = false, _connected = false, _pending = false;
  bool _matchUnavailable = false;
  String? _error;
  _LudoBoardTheme _boardTheme = _LudoBoardTheme.classic;

  List<String> get _players => (_state['players'] as List? ?? const [])
      .map((e) => e.toString())
      .toList();
  List<int> get _seats => (_state['seats'] as List? ?? const [])
      .map((e) => (e as num).toInt())
      .toList();
  List<int> get _dice => (_state['dice'] as List? ?? const [])
      .map((e) => (e as num).toInt())
      .toList();
  List<Map<String, dynamic>> get _legal =>
      (_state['legalMoves'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
  String get _turn => _state['turnPlayer']?.toString() ?? '';
  bool get _myTurn =>
      !widget.spectating &&
      _turn == widget.selfId &&
      _state['phase'] == 'Turn' &&
      _state['paused'] != true;
  bool get _finished => _state['phase'] == 'Results';
  bool get _paused => _state['paused'] == true;
  String _name(String id) =>
      widget.nicknames[id] ?? (id == widget.selfId ? 'You' : 'Player');

  Color? _playerColor(String player) {
    final index = _players.indexOf(player);
    return index < 0 || index >= _seats.length ? null : _colors[_seats[index]];
  }

  @override
  void initState() {
    super.initState();
    _cup = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _sub = widget.socket.envelopes.listen(_onFrame);
    _connected = widget.socket.isConnected;
    unawaited(_restoreBoardTheme());
    widget.socket.send('HELLO', {'lastSeq': 0});
    unawaited(GameSfx.warmUp());
    GameMusic.start(GameMusic.moodFor('ludo'));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _seconds > 0 && _state['paused'] != true) {
        setState(() => _seconds--);
      }
    });
  }

  Future<void> _restoreBoardTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('ludo_board_theme');
    if (!mounted) return;
    setState(() => _boardTheme = _LudoBoardTheme.values.firstWhere(
        (theme) => theme.name == saved,
        orElse: () => _LudoBoardTheme.classic));
  }

  Future<void> _setBoardTheme(_LudoBoardTheme theme) async {
    setState(() => _boardTheme = theme);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ludo_board_theme', theme.name);
  }

  void _showBoardThemes() {
    showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Ludo board'),
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final theme in _LudoBoardTheme.values)
                  ListTile(
                    key: ValueKey('ludo-theme-${theme.name}'),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _gold),
                        gradient: switch (theme) {
                          _LudoBoardTheme.classic => const LinearGradient(
                                colors: [
                                  Color(0xffe83d47),
                                  Color(0xff17ad67),
                                  Color(0xffffcd21),
                                  Color(0xff2474df)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight),
                          _LudoBoardTheme.glass => const LinearGradient(
                                colors: [
                                  Color(0xffeffcff),
                                  Color(0xff57bec7),
                                  Color(0xff344858)
                                ]),
                          _LudoBoardTheme.wood => const LinearGradient(colors: [
                              Color(0xffc49865),
                              Color(0xff735039),
                              Color(0xffd7b98c)
                            ]),
                        },
                      ),
                    ),
                    title: Text(switch (theme) {
                      _LudoBoardTheme.classic => 'Classic',
                      _LudoBoardTheme.glass => 'Glass',
                      _LudoBoardTheme.wood => 'Weathered wood',
                    }),
                    trailing: _boardTheme == theme
                        ? const Icon(Icons.check_circle_rounded, color: _gold)
                        : null,
                    onTap: () {
                      Navigator.pop(dialogContext);
                      unawaited(_setBoardTheme(theme));
                    },
                  ),
              ]),
            ));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _rollTimer?.cancel();
    _rollFeedbackTimer?.cancel();
    _sub?.cancel();
    _cup.dispose();
    _chatController.dispose();
    widget.socket.close();
    unawaited(GameMusic.stop());
    super.dispose();
  }

  void _onFrame(Map<String, dynamic> env) {
    if (!mounted) return;
    final payload =
        (env['payload'] as Map? ?? const {}).cast<String, dynamic>();
    switch (env['type']) {
      case 'CONNECTION':
        setState(() => _connected = payload['connected'] == true);
      case 'SNAPSHOT':
        if (payload['lobby'] == true) {
          setState(() {
            _matchUnavailable = true;
            _state = {};
            _pending = false;
            _rolling = false;
            _cup.stop();
            _error =
                'This match is no longer running. Start a new HUUD to play.';
          });
          return;
        }
        final old = _state;
        final oldDice = (old['dice'] as List? ?? const []).length;
        final nextDice = (payload['dice'] as List? ?? const []).length;
        if (old['pieces'] != null &&
            old['pieces'].toString() != payload['pieces'].toString()) {
          GameSfx.move();
        }
        if (nextDice > oldDice && _rolling) {
          _rollTimer?.cancel();
          _rollTimer = Timer(const Duration(milliseconds: 650), () {
            if (mounted) {
              setState(() {
                _rolling = false;
                _cup.stop();
              });
            }
          });
        }
        setState(() {
          _matchUnavailable = false;
          _state = payload;
          _seconds = (payload['secondsLeft'] as num?)?.toInt() ?? _seconds;
          _pending = false;
          _error = null;
          _lastRolled = (payload['rolledDice'] as List? ?? const [])
              .whereType<num>()
              .map((value) => value.toInt())
              .toList();
          _rollOwner =
              _lastRolled.isEmpty ? null : payload['rollPlayer']?.toString();
          _noMoveRoll = false;
          if (!_dice.contains(_selectedDie)) _selectedDie = _dice.firstOrNull;
        });
      case 'PHASE':
        setState(() =>
            _seconds = (payload['secondsLeft'] as num?)?.toInt() ?? _seconds);
      case 'EVENT':
        final type = payload['type']?.toString();
        final data =
            (payload['data'] as Map? ?? const {}).cast<String, dynamic>();
        if (type == 'CHAT_MESSAGE') {
          setState(() {
            _chat.insert(
                0,
                TableChatLine(
                    who: _name(data['from']?.toString() ?? ''),
                    text: data['text']?.toString() ?? '',
                    isAgent: data['channel'] == 'agent',
                    isSpectator: data['channel'] == 'spectate'));
            if (_chat.length > 80) _chat.removeLast();
          });
        } else if (type == 'DICE_ROLLED') {
          final rolled = (data['dice'] as List? ?? const [])
              .whereType<num>()
              .map((value) => value.toInt())
              .toList();
          if (_dice.isEmpty) {
            _rollTimer?.cancel();
            _rollFeedbackTimer?.cancel();
            setState(() {
              _lastRolled = rolled;
              _rollOwner = data['player']?.toString();
              _noMoveRoll = true;
              _rolling = false;
              _pending = false;
              _cup.stop();
            });
            _rollFeedbackTimer = Timer(const Duration(seconds: 2), () {
              if (mounted) {
                setState(() {
                  _lastRolled = [];
                  _rollOwner = null;
                  _noMoveRoll = false;
                });
              }
            });
          }
        } else if (type == 'PIECE_MOVED') {
          if ((data['captured'] as List? ?? const []).isNotEmpty) {
            GameSfx.capture();
          }
        } else if (type == 'GAME_PAUSED' || type == 'GAME_RESUMED') {
          setState(() {
            _state['paused'] = type == 'GAME_PAUSED';
            _seconds = (data['secondsLeft'] as num?)?.toInt() ?? _seconds;
          });
        } else if (type == 'SPECTATOR_COUNT') {
          setState(() => _state['spectatorCount'] = data['count']);
        } else if (type == 'SPECTATORS_MUTED' || type == 'SPECTATORS_UNMUTED') {
          setState(
              () => _state['spectatorsMuted'] = type == 'SPECTATORS_MUTED');
        }
      case 'ERROR':
        setState(() {
          _pending = false;
          _rolling = false;
          _cup.stop();
          if (payload['code'] == 'NOT_STARTED') {
            _matchUnavailable = true;
            _state = {};
            _error =
                'This match is no longer running. Start a new HUUD to play.';
          } else {
            _error =
                payload['message']?.toString() ?? 'Could not make that move';
          }
        });
    }
  }

  void _startRollPress() {
    if (_matchUnavailable ||
        !_myTurn ||
        _dice.isNotEmpty ||
        _pending ||
        _rolling ||
        !_connected) {
      return;
    }
    setState(() {
      _rolling = true;
      _error = null;
      _lastRolled = [];
      _rollOwner = null;
      _noMoveRoll = false;
    });
    _cup.repeat();
    GameSfx.diceRoll();
  }

  void _releaseRoll() {
    if (!_rolling || _pending) return;
    if (_matchUnavailable || !_myTurn || _dice.isNotEmpty || !_connected) {
      _cancelRollPress();
      return;
    }
    setState(() => _pending = true);
    widget.socket.send('PLAYER_ACTION', {'action': 'ROLL', 'data': {}});
    _rollTimer?.cancel();
    _rollTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _rolling = false;
          _pending = false;
          _cup.stop();
        });
      }
    });
  }

  void _cancelRollPress() {
    if (!_rolling || _pending) return;
    setState(() => _rolling = false);
    _cup.stop();
  }

  void _tapToken(String player, int token) {
    if (_matchUnavailable ||
        !_myTurn ||
        player != widget.selfId ||
        _pending ||
        !_connected) {
      return;
    }
    final options =
        _legal.where((m) => (m['token'] as num?)?.toInt() == token).toList();
    if (options.isEmpty) {
      GameSfx.illegal();
      return;
    }
    final chosen =
        options.any((m) => (m['die'] as num?)?.toInt() == _selectedDie)
            ? _selectedDie!
            : (options.first['die'] as num).toInt();
    setState(() {
      _pending = true;
      _selectedDie = chosen;
    });
    GameSfx.select();
    widget.socket.send('PLAYER_ACTION', {
      'action': 'MOVE',
      'data': {'die': chosen, 'token': token}
    });
  }

  void _sendChat() {
    final message = _chatController.text.trim();
    if (message.isEmpty || !_connected) return;
    widget.socket.send('CHAT_SEND',
        {'channel': widget.spectating ? 'spectate' : 'table', 'text': message});
    _chatController.clear();
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Leave Ludo?'),
              content:
                  const Text('Your place in this match will be forfeited.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Stay')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Leave'))
              ],
            ));
    if (leave == true && mounted) {
      final app = AppScope.of(context);
      try {
        if (!_finished) {
          await app.api.post('/rooms/${widget.socket.roomId}/leave-ludo');
        }
        await app.clearActiveRoom(widget.socket.roomId);
        if (mounted) Navigator.of(context).pop();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Could not leave the game. Try again.')));
        }
      }
    }
  }

  Future<void> _returnToGames() async {
    await AppScope.of(context).clearActiveRoom(widget.socket.roomId);
    if (mounted) Navigator.of(context).pop();
  }

  void _showHelp() {
    showHowToPlay(context,
        emoji: '🎲',
        title: 'Ludo',
        tagline:
            'Bring all ${(_state['pieceCount'] as num?)?.toInt() ?? 4} pieces to the centre first.',
        steps: [
          'Tap the cup to roll two dice. Use each die on a piece; choose the same piece twice or two different pieces.',
          'A six brings a piece out of its home box onto its starting square. Only double six earns another roll.',
          'Land on a rival on an ordinary square to send it home. Stars and coloured starting squares are safe.',
          'Enter your own coloured lane after a lap. Reach the centre with an exact roll.',
        ]);
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        height: 42,
        child: Row(children: [
          Icon(icon, size: 18, color: _gold),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _cream, fontSize: 13))),
        ]),
      );

  void _onMenuSelected(String value) {
    switch (value) {
      case 'help':
        _showHelp();
      case 'theme':
        _showBoardThemes();
      case 'pause':
        if (_connected) widget.socket.send('PAUSE_TOGGLE');
      case 'music':
        unawaited(GameMusic.setEnabled(!GameMusic.enabled).then((_) {
          if (mounted) setState(() {});
        }));
      case 'sfx':
        unawaited(GameSfx.setEnabled(!GameSfx.enabled).then((_) {
          if (mounted) setState(() {});
        }));
      case 'spectators':
        if (_connected) widget.socket.send('MUTE_SPECTATORS_TOGGLE');
      case 'exit':
        if (widget.spectating) {
          Navigator.of(context).pop();
        } else {
          _confirmLeave();
        }
    }
  }

  Widget _playArea() => Column(children: [
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final side =
              math.min(constraints.maxWidth - 16, constraints.maxHeight);
          return Center(
              child: SizedBox.square(dimension: side, child: _board(side)));
        })),
        _diceTray(),
      ]);

  Widget _pausedOverlay() => Positioned.fill(
        child: Container(
          key: const ValueKey('ludo-paused-overlay'),
          color: const Color(0x99100916),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _gold),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.pause_rounded, color: _gold),
                SizedBox(width: 8),
                Text('GAME PAUSED',
                    style: TextStyle(
                        color: _cream,
                        fontSize: 14,
                        fontWeight: FontWeight.w900)),
              ]),
              if (!widget.spectating) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('ludo-resume-button'),
                  onPressed: _connected
                      ? () => widget.socket.send('PAUSE_TOGGLE')
                      : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Resume game'),
                ),
              ] else ...[
                const SizedBox(height: 8),
                const Text('Waiting for a player to resume',
                    style: TextStyle(color: _cream, fontSize: 11)),
              ],
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: _finished || widget.spectating || _matchUnavailable,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            foregroundColor: _cream,
            title: Row(children: [
              const Text('LUDO', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(width: 12),
              Flexible(
                  child: CopyableHuudCode(
                code: widget.roomCode,
                child: Text('HUUD ${widget.roomCode}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: _gold)),
              ))
            ]),
            actions: [
              if (!_finished)
                GameVoiceControl(
                  roomId: widget.socket.roomId,
                  socket: widget.socket,
                  selfId: widget.selfId,
                  nicknames: widget.nicknames,
                  spectating: widget.spectating,
                ),
              IconButton(
                  tooltip: GameSfx.enabled
                      ? 'Mute sound effects'
                      : 'Enable sound effects',
                  icon: Icon(GameSfx.enabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded),
                  onPressed: () async {
                    await GameSfx.setEnabled(!GameSfx.enabled);
                    if (mounted) setState(() {});
                  }),
              PopupMenuButton<String>(
                key: const ValueKey('ludo-settings-menu'),
                tooltip: 'Game settings',
                icon: const Icon(Icons.settings_rounded),
                color: _panel,
                onSelected: _onMenuSelected,
                itemBuilder: (_) => [
                  _menuItem('help', Icons.help_outline_rounded, 'How to play'),
                  _menuItem('theme', Icons.palette_outlined, 'Board theme'),
                  if (!widget.spectating && !_finished)
                    _menuItem(
                        'pause',
                        _paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        _paused ? 'Resume' : 'Pause'),
                  _menuItem(
                      'music',
                      GameMusic.enabled
                          ? Icons.music_note_rounded
                          : Icons.music_off_rounded,
                      GameMusic.enabled ? 'Mute music' : 'Play music'),
                  _menuItem(
                      'sfx',
                      GameSfx.enabled
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      GameSfx.enabled
                          ? 'Mute game sounds'
                          : 'Play game sounds'),
                  if (!widget.spectating)
                    _menuItem(
                        'spectators',
                        _state['spectatorsMuted'] == true
                            ? Icons.comments_disabled_rounded
                            : Icons.chat_bubble_outline_rounded,
                        _state['spectatorsMuted'] == true
                            ? 'Let spectators comment'
                            : 'Mute spectator comments'),
                  _menuItem('exit', Icons.logout_rounded,
                      widget.spectating ? 'Stop watching' : 'Leave game'),
                ],
              ),
            ],
          ),
          body: SafeArea(
              child: Column(children: [
            _status(),
            Expanded(
                child: Stack(children: [
              Positioned.fill(
                  child: _paused
                      ? ClipRect(
                          child: ImageFiltered(
                            key: const ValueKey('ludo-paused-board-blur'),
                            imageFilter:
                                ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                            child: _playArea(),
                          ),
                        )
                      : _playArea()),
              if (_paused) _pausedOverlay(),
              if (_matchUnavailable)
                Positioned.fill(
                  child: ColoredBox(
                    color: _bg,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wifi_off_rounded,
                                size: 42, color: _gold),
                            const SizedBox(height: 14),
                            const Text('MATCH NO LONGER RUNNING',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: _cream,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 8),
                            const Text('Return to games and start a new HUUD.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _cream)),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              key: const ValueKey('ludo-return-to-games'),
                              onPressed: _returnToGames,
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: const Text('Return to games'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ])),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: Color(0xffff8b72), fontSize: 11))),
            TableChatPanel(
                lines: _chat,
                controller: _chatController,
                onSend: _sendChat,
                spectatorCount:
                    (_state['spectatorCount'] as num?)?.toInt() ?? 0,
                amSpectator: widget.spectating,
                height: 98,
                canSend: _connected &&
                    !(widget.spectating && _state['spectatorsMuted'] == true)),
          ])),
        ));
  }

  Widget _status() {
    final winner = _state['winner']?.toString();
    final label = winner != null
        ? '${_name(winner)} wins'
        : _state['paused'] == true
            ? 'Game paused'
            : _turn.isEmpty
                ? 'Waiting for table'
                : _myTurn
                    ? 'Your turn'
                    : '${_name(_turn)} to play';
    final seat = _players.indexOf(_turn);
    final color =
        seat < 0 || seat >= _seats.length ? _gold : _colors[_seats[seat]];
    return Container(
      height: 64,
      color: _panel,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _gold, width: 3)),
            child: Text('$_seconds',
                style: const TextStyle(
                    color: _gold, fontWeight: FontWeight.bold))),
        const SizedBox(width: 16),
        Expanded(
            child: Text(label.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 16, fontWeight: FontWeight.w900))),
        if (!_connected) const Icon(Icons.wifi_off_rounded, color: _cream),
      ]),
    );
  }

  Widget _board(double side) {
    final frame = math.max(7.0, side * .028);
    final boardSide = side - frame * 2;
    final cell = boardSide / 15;
    final pieces = (_state['pieces'] as Map? ?? const {});
    return CustomPaint(
      key: const ValueKey('ludo-wood-frame'),
      painter: _LudoWoodFramePainter(frame),
      child: Padding(
        padding: EdgeInsets.all(frame),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(children: [
              CustomPaint(
                  key: ValueKey('ludo-board-${_boardTheme.name}'),
                  size: Size.square(boardSide),
                  painter: _LudoBoardPainter(
                      _colors,
                      _track,
                      (_state['pieceCount'] as num?)?.toInt() ?? 4,
                      _seats.toSet(),
                      _boardTheme)),
              for (var i = 0; i < _players.length; i++)
                if (_players[i] == _turn && !_finished)
                  Positioned(
                      left: (_seats[i] == 0 || _seats[i] == 3 ? 0 : 9) * cell,
                      top: (_seats[i] < 2 ? 0 : 9) * cell,
                      width: 6 * cell,
                      height: 6 * cell,
                      child: IgnorePointer(
                        child: Container(
                          key: const ValueKey('ludo-active-home'),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: _colors[_seats[i]], width: 3),
                            boxShadow: [
                              BoxShadow(
                                  color:
                                      _colors[_seats[i]].withValues(alpha: .6),
                                  blurRadius: 5),
                            ],
                          ),
                        ),
                      )),
              for (var i = 0; i < _players.length; i++)
                _playerLabel(_players[i], _seats[i], cell),
              for (var i = 0; i < _players.length; i++)
                for (var token = 0;
                    token < (pieces[_players[i]] as List? ?? const []).length;
                    token++)
                  _token(_players[i], _seats[i], token,
                      (pieces[_players[i]] as List)[token] as int, cell),
            ])),
      ),
    );
  }

  Widget _playerLabel(String player, int seat, double cell) {
    final left = (seat == 0 || seat == 3 ? 0.35 : 9.25) * cell;
    final top = (seat < 2 ? 0.2 : 9.2) * cell;
    return Positioned(
      left: left,
      top: top,
      width: 5.4 * cell,
      height: 0.9 * cell,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: _colors[seat],
              borderRadius: BorderRadius.circular(4),
              border:
                  player == _turn ? Border.all(color: _gold, width: 2) : null),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(
                widget.agents.contains(player)
                    ? Icons.smart_toy_rounded
                    : Icons.person_rounded,
                size: 12,
                color: Colors.white),
            const SizedBox(width: 2),
            Flexible(
                child: Text(player == widget.selfId ? 'You' : _name(player),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.white))),
          ])),
    );
  }

  Widget _token(String player, int seat, int token, int progress, double cell) {
    final pieceCount = (_state['pieceCount'] as num?)?.toInt() ?? 4;
    final (row, col) = _position(seat, token, progress, pieceCount);
    final pieceScale = progress == 56 ? (pieceCount == 8 ? .32 : .46) : .78;
    final pieceInset = (1 - pieceScale) / 2;
    final active = _myTurn &&
        player == widget.selfId &&
        _legal.any((m) => m['token'] == token);
    return AnimatedPositioned(
      key: ValueKey('$player:$token'),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOut,
      left: (col + pieceInset) * cell,
      top: (row + pieceInset) * cell,
      width: cell * pieceScale,
      height: cell * pieceScale,
      child: GestureDetector(
          onTap: () => _tapToken(player, token),
          child: Container(
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _boardTheme == _LudoBoardTheme.classic
                    ? _colors[seat]
                    : null,
                gradient: _boardTheme == _LudoBoardTheme.classic
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                            Color.lerp(
                                _colors[seat],
                                Colors.white,
                                _boardTheme == _LudoBoardTheme.glass
                                    ? .58
                                    : .18)!,
                            _colors[seat],
                            Color.lerp(
                                _colors[seat],
                                Colors.black,
                                _boardTheme == _LudoBoardTheme.glass
                                    ? .30
                                    : .38)!,
                          ]),
                border: Border.all(
                    color: _boardTheme == _LudoBoardTheme.wood
                        ? const Color(0xfff2dfb9)
                        : Colors.white,
                    width: active ? 2.5 : 1),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .45),
                      blurRadius: active ? 8 : 3,
                      offset: const Offset(0, 2))
                ]),
            child: active
                ? const Icon(Icons.touch_app_rounded,
                    size: 12, color: Colors.white)
                : null,
          )),
    );
  }

  (double, double) _position(
      int seat, int token, int progress, int pieceCount) {
    if (progress == -1) {
      if (pieceCount == 8) {
        final r = seat < 2 ? 1.55 : 10.55;
        final c = seat == 0 || seat == 3 ? 1.05 : 10.05;
        return (r + (token ~/ 4) * 2.1, c + (token % 4) * 1.05);
      }
      final r = seat < 2 ? 1.65 : 10.65;
      final c = seat == 0 || seat == 3 ? 1.65 : 10.65;
      return (r + (token ~/ 2) * 2.05, c + (token % 2) * 2.05);
    }
    if (progress == 56) {
      final columns = pieceCount == 8 ? 4 : 2;
      final across = token % columns;
      final deep = token ~/ columns;
      final spreadAcross = pieceCount == 8 ? .42 : .50;
      final spreadDeep = pieceCount == 8 ? .34 : .46;
      final cross = (across - (columns - 1) / 2) * spreadAcross;
      final inward = (deep - .5) * spreadDeep;

      // Keep completed pieces inside their own colored center wedge. Sharing
      // one center coordinate made a legitimate finish look like a missed capture.
      return switch (seat) {
        0 => (6.15 + inward, 7.0 + cross),
        1 => (7.0 + cross, 7.85 - inward),
        2 => (7.85 - inward, 7.0 - cross),
        _ => (7.0 - cross, 6.15 + inward),
      };
    }
    if (progress >= 51) {
      final step = progress - 50;
      return switch (seat) {
        0 => (7, step.toDouble()),
        1 => (step.toDouble(), 7),
        2 => (7, (14 - step).toDouble()),
        _ => ((14 - step).toDouble(), 7),
      };
    }
    final point = _track[(seat * 13 + progress) % 52];
    return (point.$1.toDouble(), point.$2.toDouble());
  }

  Widget _diceTray() {
    final dice = _dice;
    final shownDice = _lastRolled.isNotEmpty ? _lastRolled : dice;
    final remaining = List<int>.of(dice);
    final available = <bool>[];
    for (final value in shownDice) {
      final index = remaining.indexOf(value);
      available.add(index >= 0);
      if (index >= 0) remaining.removeAt(index);
    }
    final displayPlayer = _rollOwner ?? _turn;
    final faded = displayPlayer.isNotEmpty &&
        (widget.spectating || displayPlayer != widget.selfId);
    final borderColor = _playerColor(displayPlayer) ?? const Color(0xff5b3158);
    final canRoll =
        _myTurn && dice.isEmpty && !_pending && !_rolling && _connected;
    final cupLabel = _rolling
        ? _pending
            ? 'ROLLING'
            : 'RELEASE'
        : !_connected
            ? 'CONNECTING'
            : !_myTurn
                ? 'WAIT TURN'
                : dice.isNotEmpty
                    ? 'USE DICE'
                    : 'HOLD CUP';
    return AnimatedContainer(
      key: const ValueKey('ludo-dice-tray'),
      duration: const Duration(milliseconds: 180),
      height: 92,
      margin: const EdgeInsets.fromLTRB(10, 5, 10, 7),
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: borderColor, width: 2.5)),
      child: Opacity(
          key: const ValueKey('ludo-dice-content'),
          opacity: faded ? .72 : 1,
          child: Row(children: [
            Semantics(
                key: const ValueKey('ludo-dice-cup'),
                button: true,
                enabled: canRoll,
                label: 'Roll dice',
                onTap: canRoll
                    ? () {
                        _startRollPress();
                        _releaseRoll();
                      }
                    : null,
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _startRollPress(),
                    onTapUp: (_) => _releaseRoll(),
                    onTapCancel: _cancelRollPress,
                    child: SizedBox(
                        width: 66,
                        height: 80,
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              RotationTransition(
                                  turns: _cup,
                                  child: CustomPaint(
                                      size: const Size(51, 51),
                                      painter: _DiceCupPainter())),
                              const SizedBox(height: 3),
                              Text(cupLabel,
                                  style: const TextStyle(
                                      color: _cream, fontSize: 9)),
                            ])))),
            const SizedBox(width: 15),
            for (var i = 0; i < shownDice.length; i++) ...[
              TweenAnimationBuilder<double>(
                  key: ValueKey('${_state['rollCount']}:$i:${shownDice[i]}'),
                  tween: Tween(begin: -0.65, end: 0),
                  duration: const Duration(milliseconds: 480),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) => Transform.translate(
                      offset: Offset(value * 55, 0), child: child),
                  child: Opacity(
                      key: ValueKey('ludo-die-$i'),
                      opacity: available[i] ? 1 : .42,
                      child: GestureDetector(
                          onTap: available[i] && _myTurn
                              ? () =>
                                  setState(() => _selectedDie = shownDice[i])
                              : null,
                          child: Container(
                              width: 48,
                              height: 48,
                              margin: const EdgeInsets.only(right: 9),
                              alignment: Alignment.center,
                              child: CustomPaint(
                                  key: ValueKey('ludo-3d-die-$i'),
                                  size: const Size(48, 48),
                                  painter: _Die3DPainter(
                                      shownDice[i],
                                      available[i] &&
                                          _myTurn &&
                                          _selectedDie == shownDice[i])))))),
            ],
            const Spacer(),
            if (_noMoveRoll && _lastRolled.isNotEmpty)
              const Text('NO MOVE',
                  style: TextStyle(
                      color: _gold, fontSize: 10, fontWeight: FontWeight.bold)),
            if (_myTurn && dice.isNotEmpty)
              const Text('TAP A\nPIECE',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: _gold, fontSize: 10, fontWeight: FontWeight.bold)),
            if (faded && shownDice.isNotEmpty && !_noMoveRoll)
              SizedBox(
                  width: 58,
                  child: Text('${_name(displayPlayer)}\nDICE',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          color: _cream,
                          fontSize: 9,
                          fontWeight: FontWeight.bold))),
          ])),
    );
  }
}

class _DiceCupPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final body = Path()
      ..moveTo(3, 10)
      ..quadraticBezierTo(25, 5, 48, 10)
      ..lineTo(41, 44)
      ..quadraticBezierTo(25, 51, 10, 44)
      ..close();
    canvas.drawPath(
        body,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xff391946), Color(0xff793c81), Color(0xff32153d)],
          ).createShader(Offset.zero & size));
    canvas.drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xffffcf66));
    canvas.drawOval(const Rect.fromLTWH(3, 5, 45, 11),
        Paint()..color = const Color(0xffffcf66));
    canvas.drawOval(const Rect.fromLTWH(6, 7, 39, 7),
        Paint()..color = const Color(0xff210f2b));
    final mark = Paint()..color = const Color(0xffffcf66);
    for (final point in [
      const Offset(20, 30),
      const Offset(30, 30),
      const Offset(20, 37),
      const Offset(30, 37)
    ]) {
      canvas.drawCircle(point, 2.2, mark);
    }
  }

  @override
  bool shouldRepaint(covariant _DiceCupPainter oldDelegate) => false;
}

class _Die3DPainter extends CustomPainter {
  const _Die3DPainter(this.value, this.selected);
  final int value;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final front = RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 8, size.width - 10, size.height - 10),
        const Radius.circular(7));
    canvas.drawRRect(
        front.shift(const Offset(3, 4)),
        Paint()
          ..color = Colors.black.withValues(alpha: .35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

    final top = Path()
      ..moveTo(7, 8)
      ..lineTo(13, 2)
      ..lineTo(size.width - 2, 2)
      ..lineTo(size.width - 8, 8)
      ..close();
    canvas.drawPath(
        top,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xffffffff), Color(0xffdce2e8)],
          ).createShader(Offset.zero & size));

    final side = Path()
      ..moveTo(size.width - 8, 8)
      ..lineTo(size.width - 2, 2)
      ..lineTo(size.width - 2, size.height - 12)
      ..lineTo(size.width - 8, size.height - 2)
      ..close();
    canvas.drawPath(
        side,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xffd9e0e7), Color(0xff9ca7b2)],
          ).createShader(Offset.zero & size));

    canvas.drawRRect(
        front,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffffffff), Color(0xfff4f5f6), Color(0xffcbd2d9)],
            stops: [0, .6, 1],
          ).createShader(front.outerRect));
    canvas.drawRRect(
        front,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.7 : 1
          ..color =
              selected ? const Color(0xffffcf66) : const Color(0xff9ca6af));

    canvas.drawArc(
        Rect.fromLTWH(5, 11, size.width - 17, size.height - 18),
        math.pi * 1.05,
        math.pi * .65,
        false,
        Paint()
          ..color = Colors.white.withValues(alpha: .9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4);

    final spots = switch (value) {
      1 => [4],
      2 => [0, 8],
      3 => [0, 4, 8],
      4 => [0, 2, 6, 8],
      5 => [0, 2, 4, 6, 8],
      _ => [0, 2, 3, 5, 6, 8],
    };
    for (final spot in spots) {
      final x = 3 + (spot % 3 + 1) * (size.width - 12) / 4;
      final y = 8 + (spot ~/ 3 + 1) * (size.height - 10) / 4;
      canvas.drawCircle(Offset(x + .7, y + 1), 3.1,
          Paint()..color = Colors.white.withValues(alpha: .7));
      canvas.drawCircle(
          Offset(x, y),
          2.75,
          Paint()
            ..shader = const RadialGradient(
              colors: [Color(0xff3b3040), Color(0xff0f0b12)],
            ).createShader(Rect.fromCircle(center: Offset(x, y), radius: 3)));
    }
  }

  @override
  bool shouldRepaint(covariant _Die3DPainter oldDelegate) =>
      value != oldDelegate.value || selected != oldDelegate.selected;
}

class _LudoWoodFramePainter extends CustomPainter {
  const _LudoWoodFramePainter(this.inset);
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final outer =
        RRect.fromRectAndRadius(bounds.deflate(1), const Radius.circular(9));
    canvas.drawRRect(
        outer.shift(const Offset(0, 2)),
        Paint()
          ..color = Colors.black.withValues(alpha: .42)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawRRect(
        outer,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xffd19a58),
              Color(0xff87512f),
              Color(0xff4d2c20),
              Color(0xffa66b3c),
            ],
            stops: [0, .38, .72, 1],
          ).createShader(bounds));

    final framePath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(outer)
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(
              inset, inset, size.width - inset * 2, size.height - inset * 2),
          const Radius.circular(3)));
    canvas.save();
    canvas.clipPath(framePath);
    final grain = Paint()
      ..color = const Color(0xff3d2118).withValues(alpha: .26)
      ..strokeWidth = .7
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 42; i++) {
      final y = (i * 23 % 43) / 43 * size.height;
      final bend = (i % 5 - 2) * .8;
      canvas.drawPath(
          Path()
            ..moveTo(-8, y)
            ..quadraticBezierTo(size.width * .48, y + bend, size.width + 8,
                y + (i.isEven ? 1.2 : -1.2)),
          grain);
    }
    canvas.restore();

    canvas.drawRRect(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = const Color(0xffffcf76).withValues(alpha: .75));
    final inner = RRect.fromRectAndRadius(
        Rect.fromLTWH(inset - 1, inset - 1, size.width - (inset - 1) * 2,
            size.height - (inset - 1) * 2),
        const Radius.circular(4));
    canvas.drawRRect(
        inner,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = const Color(0xff321a13));
    canvas.drawLine(
        Offset(inset + 2, inset + 1),
        Offset(size.width - inset - 2, inset + 1),
        Paint()
          ..color = const Color(0xffffd691).withValues(alpha: .55)
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _LudoWoodFramePainter oldDelegate) =>
      inset != oldDelegate.inset;
}

class _LudoBoardPainter extends CustomPainter {
  _LudoBoardPainter(
      this.colors, this.track, this.pieceCount, this.activeSeats, this.theme);
  final List<Color> colors;
  final List<(int, int)> track;
  final int pieceCount;
  final Set<int> activeSeats;
  final _LudoBoardTheme theme;
  static const _line = Color(0xff252027);

  void _surface(Canvas canvas, Rect rect, Color color) {
    if (theme == _LudoBoardTheme.classic) {
      canvas.drawRect(rect, Paint()..color = color);
      return;
    }
    final top = theme == _LudoBoardTheme.glass
        ? Color.lerp(color, Colors.white, .34)!
        : Color.lerp(color, const Color(0xffd2ad7d), .22)!;
    final bottom = theme == _LudoBoardTheme.glass
        ? Color.lerp(color, const Color(0xff12303c), .22)!
        : Color.lerp(color, const Color(0xff553a2c), .30)!;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [top, color, bottom]).createShader(rect));
    if (theme == _LudoBoardTheme.glass) {
      canvas.drawLine(
          rect.topLeft + const Offset(1, 1),
          rect.topRight + const Offset(-1, 1),
          Paint()
            ..color = Colors.white.withValues(alpha: .53)
            ..strokeWidth = 1.1);
      canvas.drawLine(
          rect.topLeft + const Offset(1, 1),
          rect.bottomLeft + const Offset(1, -1),
          Paint()
            ..color = Colors.white.withValues(alpha: .35)
            ..strokeWidth = 1);
    }
  }

  void _texture(Canvas canvas, Size size) {
    if (theme != _LudoBoardTheme.wood) return;
    final grain = Paint()
      ..color = const Color(0xff503728).withValues(alpha: .15)
      ..strokeWidth = .7
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 90; i++) {
      final y = (i * 37 % 97) / 97 * size.height;
      final x = (i * 71 % 101) / 101 * size.width;
      final length = size.width * (.09 + (i % 7) * .019);
      final path = Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(x + length * .5, y + (i % 3 - 1) * 2,
            math.min(x + length, size.width), y);
      canvas.drawPath(path, grain);
    }
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height),
          Paint()..color = const Color(0xff513929).withValues(alpha: .17));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 15;
    final paint = Paint();
    _surface(canvas, Offset.zero & size,
        theme == _LudoBoardTheme.wood ? const Color(0xffd9bc91) : Colors.white);
    for (var seat = 0; seat < 4; seat++) {
      final x = (seat == 0 || seat == 3 ? 0 : 9) * cell;
      final y = (seat < 2 ? 0 : 9) * cell;
      _surface(canvas, Rect.fromLTWH(x, y, 6 * cell, 6 * cell), colors[seat]);
      _surface(
          canvas,
          Rect.fromLTWH(x + cell, y + cell, 4 * cell, 4 * cell),
          theme == _LudoBoardTheme.wood
              ? const Color(0xffead9bb)
              : Colors.white);
      final holes = pieceCount == 8 && activeSeats.contains(seat) ? 8 : 4;
      for (var t = 0; t < holes; t++) {
        final cx =
            x + (holes == 8 ? 1.55 + t % 4 * 1.05 : 2.15 + t % 2 * 2.05) * cell;
        final cy = y +
            (holes == 8 ? 2.05 + t ~/ 4 * 2.1 : 2.15 + t ~/ 2 * 2.05) * cell;
        canvas.drawCircle(Offset(cx, cy), cell * .43,
            paint..color = colors[seat].withValues(alpha: .25));
      }
    }
    for (final (row, col) in track) {
      final rect = Rect.fromLTWH(col * cell, row * cell, cell, cell);
      _surface(
          canvas,
          rect,
          theme == _LudoBoardTheme.wood
              ? const Color(0xffead9bb)
              : Colors.white);
      canvas.drawRect(
          rect,
          paint
            ..color = _line
            ..style = PaintingStyle.stroke
            ..strokeWidth = .6);
      paint.style = PaintingStyle.fill;
    }
    for (var seat = 0; seat < 4; seat++) {
      final (r, c) = track[seat * 13];
      _surface(
          canvas, Rect.fromLTWH(c * cell, r * cell, cell, cell), colors[seat]);
      for (var step = 1; step <= 5; step++) {
        final (rr, cc) = switch (seat) {
          0 => (7, step),
          1 => (step, 7),
          2 => (7, 14 - step),
          _ => (14 - step, 7),
        };
        final rect = Rect.fromLTWH(cc * cell, rr * cell, cell, cell);
        _surface(canvas, rect, colors[seat]);
        canvas.drawRect(
            rect,
            paint
              ..color = _line
              ..style = PaintingStyle.stroke
              ..strokeWidth = .6);
        paint.style = PaintingStyle.fill;
      }
    }
    for (var i = 0; i < 4; i++) {
      final center = Offset(7.5 * cell, 7.5 * cell);
      final a = [
        Offset(6 * cell, 6 * cell),
        Offset(9 * cell, 6 * cell),
        Offset(9 * cell, 9 * cell),
        Offset(6 * cell, 9 * cell)
      ][i];
      final b = [
        Offset(6 * cell, 9 * cell),
        Offset(6 * cell, 6 * cell),
        Offset(9 * cell, 6 * cell),
        Offset(9 * cell, 9 * cell)
      ][i];
      canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy)
            ..lineTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy)
            ..close(),
          paint..color = colors[i]);
    }
    for (final index in [8, 21, 34, 47]) {
      final (r, c) = track[index];
      final center = Offset((c + .5) * cell, (r + .5) * cell);
      final path = Path();
      for (var p = 0; p < 10; p++) {
        final radius = (p.isEven ? .38 : .18) * cell;
        final angle = -math.pi / 2 + p * math.pi / 5;
        final point =
            center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
        if (p == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path..close(), paint..color = colors[(index ~/ 13) % 4]);
    }
    _texture(canvas, size);
    if (theme == _LudoBoardTheme.glass) {
      canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..color = const Color(0xff9be4eb).withValues(alpha: .55));
    }
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = theme == _LudoBoardTheme.wood ? 4 : 2
          ..color =
              theme == _LudoBoardTheme.wood ? const Color(0xff513728) : _line);
  }

  @override
  bool shouldRepaint(covariant _LudoBoardPainter oldDelegate) =>
      theme != oldDelegate.theme ||
      pieceCount != oldDelegate.pieceCount ||
      !setEquals(activeSeats, oldDelegate.activeSeats);
}
