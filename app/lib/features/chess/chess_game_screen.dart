import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/game_music.dart';
import '../../core/game_sfx.dart';
import '../../core/game_socket.dart';
import '../../widgets/copyable_huud_code.dart';
import '../../widgets/fireworks.dart';
import '../../widgets/game_voice_control.dart';
import '../../widgets/how_to_play_dialog.dart';
import '../../widgets/neon.dart';
import '../../widgets/table_chat.dart';
import '../onboarding/guest_save_session_card.dart';
import '../shell/main_shell.dart';
import '../status/victory_status.dart';
import '../../widgets/var_tv_icon.dart';
import 'chess_piece.dart';
import 'chess_var.dart';
import 'chess_view.dart';

/// Standard chess, played against the server's `ChessModule`. The same
/// SNAPSHOT/PHASE/EVENT-in, PLAYER_ACTION-out contract as Draughts and Macala.
///
/// The screen holds no rules of its own. Every snapshot carries the moves
/// the engine will accept (`legalMoves`), the clocks and the draw state, and
/// the server pushes a fresh one after every move — so a piece can only be
/// picked up if it has somewhere to go, and only dropped where it may land.
///
/// Clocks belong to the server too. The app counts the mover's clock down
/// between snapshots so it reads live, but a flag only falls when the server
/// says so.
class ChessGameScreen extends StatefulWidget {
  const ChessGameScreen({
    super.key,
    required this.socket,
    required this.selfId,
    required this.nicknames,
    this.roomCode = '',
    this.avatars = const {},
    this.agents = const {},
    this.spectating = false,
  });

  final GameSocket socket;
  final String selfId;
  final Map<String, String> nicknames;
  final String roomCode;
  final Map<String, String> avatars;

  /// Seats held by Cyber Agents, shown with a robot instead of a photo.
  final Set<String> agents;
  final bool spectating;

  @override
  State<ChessGameScreen> createState() => _ChessGameScreenState();
}

class _ChessGameScreenState extends State<ChessGameScreen>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xff150b22);
  static const _bgTop = Color(0xff24133a);
  static const _panel = Color(0xff22143a);
  static const _panelDeep = Color(0xff120a1e);
  static const _gold = Color(0xffffcf66);
  static const _goldDeep = Color(0xffd9a43c);
  static const _cream = Color(0xfffff1dc);
  static const _mute = Color(0xffa894c4);
  static const _lightSquare = Color(0xffeeeed2);
  static const _darkSquare = Color(0xff769656);
  static const _danger = Color(0xffe0604a);

  StreamSubscription? _sub;
  Timer? _ticker;
  final _tick = ValueNotifier<int>(0);

  /// What the server last said, and what's on screen — the two differ only
  /// for the moment between dropping a piece and the server confirming it.
  ChessView _server = const ChessView();
  ChessView _view = const ChessView();

  int? _selected;
  bool _actionLocked = false;

  /// The mover's clock at the moment the last snapshot arrived; the display
  /// counts down from here.
  int _moverBaseMs = 0;
  final Stopwatch _sinceSnapshot = Stopwatch();

  /// The piece sliding into place after the opponent's move.
  late final AnimationController _slide = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260));
  int? _slideFrom;
  int? _slideTo;
  String? _slidePiece;

  final List<TableChatLine> _feed = [];
  final TextEditingController _chatController = TextEditingController();
  int _spectatorCount = 0;
  bool _spectatorsMuted = false;
  int? _coinsAwarded;
  bool _showResults = true;
  bool _musicOn = GameMusic.enabled;
  bool _sfxOn = GameSfx.enabled;
  bool _leaving = false;

  /// Either player can pause. Both clocks stop and nobody can move until
  /// someone resumes.
  bool _paused = false;
  String? _pausedBy;

  /// The last move played, kept for VAR.
  ChessVarMove? _lastVar;

  @override
  void initState() {
    super.initState();
    _sub = widget.socket.envelopes.listen(_onEnvelope);
    GameMusic.start(GameMusic.moodFor('chess'));
    GameSfx.warmUp();
    // Always 0 so the server answers with a full snapshot, never a replay
    // that might have nothing in it — see DraughtsGameScreen.initState.
    widget.socket.send('HELLO', {'lastSeq': 0});
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && !_view.finished && _view.hasBoard) _tick.value++;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _slide.dispose();
    _tick.dispose();
    _chatController.dispose();
    widget.socket.close();
    GameMusic.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------- state

  bool get _amSpectator =>
      widget.spectating ||
      (_view.white.isNotEmpty &&
          widget.selfId != _view.white &&
          widget.selfId != _view.black);
  String get _mySide => widget.selfId == _view.black ? 'black' : 'white';
  String get _myColor => _mySide == 'white' ? 'w' : 'b';
  String get _opponentSide => _mySide == 'white' ? 'black' : 'white';
  bool get _flipped => !_amSpectator && _mySide == 'black';
  bool get _myTurn =>
      !_amSpectator && !_view.finished && !_paused && _view.turn == _mySide;

  String _label(String id) =>
      widget.nicknames[id] ?? (id.length > 6 ? id.substring(0, 6) : id);

  /// A side's clock as it should read right now.
  int _clockMs(String side) {
    if (!_view.finished && _view.turn == side && _sinceSnapshot.isRunning) {
      return _moverBaseMs - _sinceSnapshot.elapsedMilliseconds;
    }
    if (!_view.finished && _view.turn == side) return _moverBaseMs;
    return side == 'white' ? _view.whiteMs : _view.blackMs;
  }

  // ------------------------------------------------------------- network

  void _onEnvelope(Map<String, dynamic> env) {
    switch (env['type']) {
      case 'CONNECTION':
        final connected = (env['payload'] as Map)['connected'] == true;
        _actionLocked = false;
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
        if (!connected) {
          messenger.showSnackBar(const SnackBar(
            content: Text('Connection lost. Reconnecting to the game…'),
            duration: Duration(minutes: 5),
          ));
        }
      case 'SNAPSHOT':
        final p = (env['payload'] as Map).cast<String, dynamic>();
        if (p['lobby'] == true) return;
        _applySnapshot(p);
      case 'EVENT':
        _applyEvent((env['payload'] as Map).cast<String, dynamic>());
      case 'ERROR':
        final msg = (env['payload'] as Map)['message']?.toString() ??
            'something went wrong';
        GameSfx.illegal();
        setState(() {
          _actionLocked = false;
          _selected = null;
          _view = _server; // undo the optimistic move
        });
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
    }
  }

  void _applySnapshot(Map<String, dynamic> p) {
    final next = ChessView.fromJson(p);
    final previous = _view;
    // A new move from the other side slides in; your own already moved
    // under your finger and just settles.
    final freshMove = previous.hasBoard &&
        next.moves.length > _server.moves.length &&
        next.lastFrom != null &&
        next.lastTo != null &&
        !(previous.lastFrom == next.lastFrom && previous.lastTo == next.lastTo);
    // One new move on a board we already had: remember it for VAR.
    if (_server.hasBoard &&
        next.hasBoard &&
        next.moves.length == _server.moves.length + 1 &&
        next.lastFrom != null &&
        next.lastTo != null) {
      _lastVar = ChessVarMove(
        side: next.turn == 'white' ? 'black' : 'white',
        san: next.moves.last,
        from: next.lastFrom!,
        to: next.lastTo!,
        before: List<String?>.unmodifiable(_server.board),
        after: List<String?>.unmodifiable(next.board),
      );
    }
    setState(() {
      _server = next;
      _view = next;
      _actionLocked = false;
      _spectatorCount = p['spectatorCount'] as int? ?? _spectatorCount;
      _spectatorsMuted = p['spectatorsMuted'] as bool? ?? _spectatorsMuted;
      _paused = p['paused'] as bool? ?? _paused;
      if (_selected != null && !next.legalMoves.containsKey(_selected)) {
        _selected = null;
      }
      final live = (p['clockMsLeft'] as num?)?.toInt();
      _moverBaseMs =
          live ?? (next.turn == 'white' ? next.whiteMs : next.blackMs);
      _sinceSnapshot
        ..reset()
        ..stop();
      if (!next.finished && !_paused && live != null) _sinceSnapshot.start();
      if (freshMove) {
        _slideFrom = next.lastFrom;
        _slideTo = next.lastTo;
        _slidePiece = next.board[next.lastTo!];
      }
    });
    if (freshMove) _slide.forward(from: 0);
  }

  void _applyEvent(Map<String, dynamic> payload) {
    final type = payload['type'] as String? ?? '';
    final data =
        ((payload['data'] as Map?) ?? const {}).cast<String, dynamic>();
    switch (type) {
      case 'CHAT_MESSAGE':
        final text = data['text']?.toString().trim() ?? '';
        if (text.isEmpty) return;
        final from = data['from']?.toString();
        setState(() => _feed.insert(
            0,
            TableChatLine(
              who: from == null ? 'Cyber Agent' : _label(from),
              text: text,
              isAgent: data['channel'] == 'agent',
              isSpectator: data['channel'] == 'spectate',
            )));
      case 'MOVE_PLAYED':
        _moveSound(data);
      case 'DRAW_OFFERED':
        final by = data['by']?.toString() ?? '';
        _system(by == widget.selfId
            ? 'You offered a draw.'
            : '${_label(by)} offers a draw.');
      case 'DRAW_DECLINED':
        final by = data['by']?.toString() ?? '';
        _system(data['implicit'] == true
            ? 'Draw offer lapsed — ${_label(by)} played on.'
            : '${_label(by)} declined the draw.');
      case 'GAME_OVER':
        final winner = data['winningSide']?.toString();
        if (!_amSpectator && winner != 'draw') {
          GameMusic.playOutcome(won: winner == _mySide);
        }
        setState(() => _showResults = true);
        _system(winner == 'draw'
            ? 'Draw · ${describeResult(data['reason']?.toString())}'
            : '${_label(_view.playerFor(winner ?? 'white'))} wins · '
                '${describeResult(data['reason']?.toString())}');
      case 'COINS_AWARDED':
        setState(() => _coinsAwarded = data['amount'] as int?);
      case 'SPECTATOR_COUNT':
        setState(
            () => _spectatorCount = data['count'] as int? ?? _spectatorCount);
      case 'GAME_PAUSED':
        final by = data['by']?.toString();
        setState(() {
          // Freeze on the server's own figure so both screens agree.
          _moverBaseMs =
              (data['clockMsLeft'] as num?)?.toInt() ?? _clockMs(_view.turn);
          _sinceSnapshot
            ..reset()
            ..stop();
          _paused = true;
          _pausedBy = by;
          _selected = null;
        });
        _system(by == null ? 'Game paused.' : '${_label(by)} paused the game.');
      case 'GAME_RESUMED':
        setState(() {
          _moverBaseMs = (data['clockMsLeft'] as num?)?.toInt() ?? _moverBaseMs;
          _sinceSnapshot.reset();
          if (!_view.finished) _sinceSnapshot.start();
          _paused = false;
          _pausedBy = null;
        });
        _system('Game resumed.');
      case 'SPECTATORS_MUTED':
        setState(() => _spectatorsMuted = true);
      case 'SPECTATORS_UNMUTED':
        setState(() => _spectatorsMuted = false);
    }
  }

  void _system(String line) =>
      setState(() => _feed.insert(0, TableChatLine.system(line)));

  void _moveSound(Map<String, dynamic> data) {
    if (data['check'] == true) {
      GameSfx.king();
    } else if (data['captured'] != null) {
      final mine = data['side'] == _mySide;
      mine ? GameSfx.capture() : GameSfx.captured();
    } else if (data['castle'] != null) {
      GameSfx.chain(2);
    } else {
      GameSfx.move();
    }
  }

  void _send(String action, [Map<String, dynamic> data = const {}]) =>
      widget.socket.send('PLAYER_ACTION', {'action': action, 'data': data});

  // ------------------------------------------------------------- moving

  List<int> _targetsFrom(int square) => _view.legalMoves[square] ?? const [];

  bool _canMove(int from, int to) => _targetsFrom(from).contains(to);

  void _tapSquare(int square) {
    if (!_myTurn || _actionLocked) return;
    final piece = _view.board[square];
    final selected = _selected;
    if (selected != null && _canMove(selected, square)) {
      _attemptMove(selected, square);
      return;
    }
    if (colorOf(piece) == _myColor) {
      if (_targetsFrom(square).isEmpty) {
        GameSfx.illegal();
        setState(() => _selected = null);
        return;
      }
      GameSfx.select();
      setState(() => _selected = square == selected ? null : square);
      return;
    }
    setState(() => _selected = null);
  }

  Future<void> _attemptMove(int from, int to) async {
    String? promotion;
    final piece = _view.board[from];
    if (needsPromotion(piece, to)) {
      promotion = await _pickPromotion();
      if (promotion == null || !mounted) {
        setState(() => _selected = null);
        return;
      }
    }
    _commitMove(from, to, promotion);
  }

  void _commitMove(int from, int to, String? promotion) {
    final board = List<String?>.of(_view.board);
    final piece = board[from];
    if (piece == null) return;
    final kind = piece[1];
    final captured = board[to];
    // Castling moves the rook too; en passant takes the pawn beside you.
    if (kind == 'K' && (fileOf(to) - fileOf(from)).abs() == 2) {
      final kingside = fileOf(to) > fileOf(from);
      final rookFrom = rankOf(from) * 8 + (kingside ? 7 : 0);
      final rookTo = rankOf(from) * 8 + (kingside ? 5 : 3);
      board[rookTo] = board[rookFrom];
      board[rookFrom] = null;
    }
    var tookEnPassant = false;
    if (kind == 'P' && captured == null && fileOf(to) != fileOf(from)) {
      board[rankOf(from) * 8 + fileOf(to)] = null;
      tookEnPassant = true;
    }
    board[to] =
        promotion == null ? piece : '${piece[0]}${promotion.toUpperCase()}';
    board[from] = null;

    if (captured != null || tookEnPassant) {
      GameSfx.capture();
    } else {
      GameSfx.move();
    }
    final myMs = _clockMs(_mySide);
    _sinceSnapshot.stop();
    setState(() {
      _actionLocked = true;
      _selected = null;
      _view = ChessView(
        phase: _view.phase,
        white: _view.white,
        black: _view.black,
        turn: _opponentSide,
        board: board,
        moves: _view.moves,
        lastFrom: from,
        lastTo: to,
        capturedByWhite: _view.capturedByWhite,
        capturedByBlack: _view.capturedByBlack,
        whiteMs: _mySide == 'white' ? myMs : _view.whiteMs,
        blackMs: _mySide == 'black' ? myMs : _view.blackMs,
        incrementMs: _view.incrementMs,
        pendingDrawOffer:
            _view.pendingDrawOffer == widget.selfId ? widget.selfId : null,
      );
      _moverBaseMs = _mySide == 'white' ? _server.blackMs : _server.whiteMs;
    });
    _send('MOVE', {
      'from': squareName(from),
      'to': squareName(to),
      if (promotion != null) 'promotion': promotion,
    });
  }

  Future<String?> _pickPromotion() {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Promote to',
            style: TextStyle(color: _cream, fontWeight: FontWeight.w900)),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final (letter, name) in const [
              ('q', 'Queen'),
              ('r', 'Rook'),
              ('b', 'Bishop'),
              ('n', 'Knight'),
            ])
              Tooltip(
                message: name,
                child: InkWell(
                  key: ValueKey('chess-promote-$letter'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.of(context).pop(letter),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _lightSquare,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _gold, width: 2),
                    ),
                    child: ChessPieceGlyph(
                        code: '$_myColor${letter.toUpperCase()}', size: 46),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- actions

  void _requestUndo() {
    widget.socket
        .send('CHAT_SEND', {'channel': 'table', 'text': 'requests an undo.'});
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request sent to your opponent.')));
  }

  void _drawButton() {
    final pending = _view.pendingDrawOffer;
    if (pending != null && pending != widget.selfId) {
      _send('ACCEPT_DRAW');
      return;
    }
    if (pending == widget.selfId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Waiting for your opponent to answer.')));
      return;
    }
    _send('OFFER_DRAW');
  }

  Future<void> _confirmResign() async {
    final resign = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Resign this game?', style: TextStyle(color: _cream)),
        content: const Text('Your opponent wins. This can\'t be undone.',
            style: TextStyle(color: _mute)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep playing')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Resign', style: TextStyle(color: _danger))),
        ],
      ),
    );
    if (resign == true) _send('RESIGN');
  }

  Future<void> _leave() async {
    if (widget.spectating || _amSpectator) {
      Navigator.of(context).pop();
      return;
    }
    final vsAgent = widget.agents.contains(_view.playerFor(_opponentSide));
    if (!_view.finished) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _panel,
          title: const Text('Leave the game?', style: TextStyle(color: _cream)),
          content: Text(
              vsAgent
                  ? 'Leaving ends the game — the Cyber Agent takes the win.'
                  : 'Your clock keeps running while you\'re away. Rejoin with '
                      'the huud code before it runs out.',
              style: const TextStyle(color: _mute)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Stay')),
            TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Leave')),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    if (_leaving) return;
    _leaving = true;
    final app = AppScope.of(context);
    var ended = _view.finished;
    if (!ended && vsAgent) {
      // Against an agent nobody is waiting on you to come back: end it now.
      try {
        ended = await app.api
                .post('/rooms/${widget.socket.roomId}/leave-draughts') ==
            true;
      } catch (_) {
        _leaving = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Server error. Please try again.')));
        }
        return;
      }
    }
    if (ended) {
      await app.clearActiveRoom(widget.socket.roomId).catchError((_) {});
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()), (r) => false);
  }

  void _togglePause() => widget.socket.send('PAUSE_TOGGLE');

  Widget _pauseOverlay() {
    final by = _pausedBy;
    return Container(
      key: const ValueKey('chess-paused'),
      color: const Color(0xcc0d0618),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.pause_circle_filled_rounded, size: 56, color: _gold),
        const SizedBox(height: 8),
        const Text('PAUSED',
            style: TextStyle(
                color: _gold,
                fontSize: 22,
                letterSpacing: 4,
                fontWeight: FontWeight.w700,
                fontFamily: 'Georgia',
                fontFamilyFallback: ['Times New Roman', 'serif'])),
        const SizedBox(height: 4),
        Text(
            by == null
                ? 'Both clocks are stopped.'
                : '${by == widget.selfId ? 'You' : _label(by)} paused · both clocks are stopped',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _mute, fontSize: 12)),
        if (!_amSpectator) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('chess-resume'),
            style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: const Color(0xff2a1600)),
            onPressed: _togglePause,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Resume',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ]),
    );
  }

  Future<void> _toggleSfx() async {
    final next = !_sfxOn;
    setState(() => _sfxOn = next);
    await GameSfx.setEnabled(next);
    if (next) GameSfx.select();
  }

  Future<void> _toggleMusic() async {
    final next = !_musicOn;
    setState(() => _musicOn = next);
    await GameMusic.setEnabled(next);
  }

  void _sendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    widget.socket.send('CHAT_SEND',
        {'channel': _amSpectator ? 'spectate' : 'table', 'text': text});
    _chatController.clear();
  }

  void _showRules() {
    showHowToPlay(
      context,
      emoji: '♞',
      title: 'Chess',
      tagline: 'Standard FIDE rules. Checkmate the king, or win on time.',
      steps: const [
        'Tap a piece, then tap a lit square — or drag it there. Only legal moves light up.',
        'Castle by moving your king two squares toward a rook. You can\'t castle out of, through, or into check.',
        'A pawn that reaches the last rank promotes — pick a queen, rook, bishop or knight.',
        'En passant: a pawn that just advanced two squares can be taken as if it moved one.',
        'Your clock runs only on your turn. Run out and you lose — unless your opponent couldn\'t possibly checkmate you, which is a draw.',
        'Draws: stalemate, too little material, agreement, or claim on threefold repetition or 50 moves without a capture or pawn move. Fivefold repetition and 75 moves end the game automatically.',
      ],
    );
  }

  void _showMoves() {
    final moves = _view.moves;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('MOVES',
                  style: TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2)),
              const SizedBox(height: 12),
              if (moves.isEmpty)
                const Text('No moves yet.', style: TextStyle(color: _mute))
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: SingleChildScrollView(
                    child: Wrap(spacing: 14, runSpacing: 8, children: [
                      for (var i = 0; i < moves.length; i += 2)
                        Text(
                          '${i ~/ 2 + 1}. ${moves[i]}'
                          '${i + 1 < moves.length ? ' ${moves[i + 1]}' : ''}',
                          style: const TextStyle(
                              color: _cream,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [ui.FontFeature.tabularFigures()]),
                        ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _view.finished || _amSpectator,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_bgTop, _bg],
            ),
          ),
          child: SafeArea(
            child: !_view.hasBoard
                ? Column(children: [
                    _header(),
                    const Expanded(
                        child: Center(
                            child: CircularProgressIndicator(color: _gold))),
                  ])
                : Column(children: [
                    _header(),
                    _playerCard(_amSpectator ? 'black' : _opponentSide),
                    Expanded(
                      child: Stack(children: [
                        Positioned.fill(child: _boardArea()),
                        if (_paused && !_view.finished)
                          Positioned.fill(child: _pauseOverlay()),
                        if (_view.finished && _showResults)
                          Positioned.fill(child: _results()),
                      ]),
                    ),
                    _playerCard(_amSpectator ? 'white' : _mySide),
                    if (_banner() case final banner?) banner,
                    _actionRow(),
                    TableChatPanel(
                      lines: _feed,
                      controller: _chatController,
                      onSend: _sendChat,
                      spectatorCount: _spectatorCount,
                      amSpectator: _amSpectator,
                      height: 118,
                    ),
                  ]),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
      child: Row(children: [
        _roundButton(Icons.arrow_back_rounded, 'Back', _leave),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('CHESS',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    fontFamily: 'Georgia',
                    fontFamilyFallback: ['Times New Roman', 'serif'],
                    height: 1.05,
                  )),
              if (widget.roomCode.isNotEmpty)
                CopyableHuudCode(
                  code: widget.roomCode,
                  child: Text('HUUD ${widget.roomCode}',
                      style: const TextStyle(
                          color: _mute,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4)),
                ),
            ],
          ),
        ),
        if (!_view.finished)
          // The shared mic button takes its colour from the theme, which on
          // a light theme would be dark-on-purple here.
          Theme(
            data: Theme.of(context).copyWith(
              iconButtonTheme: IconButtonThemeData(
                  style: IconButton.styleFrom(foregroundColor: _cream)),
              iconTheme: const IconThemeData(color: _cream),
            ),
            child: GameVoiceControl(
              roomId: widget.socket.roomId,
              socket: widget.socket,
              selfId: widget.selfId,
              nicknames: widget.nicknames,
              spectating: _amSpectator,
            ),
          ),
        if (!_view.finished && !_amSpectator)
          IconButton(
            key: const ValueKey('chess-pause'),
            tooltip: _paused ? 'Resume' : 'Pause',
            color: _cream,
            visualDensity: VisualDensity.compact,
            icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                size: 24),
            onPressed: _togglePause,
          ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: _sfxOn ? 'Mute game sounds' : 'Play game sounds',
          color: _cream,
          icon: Icon(
              _sfxOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              size: 22),
          onPressed: _toggleSfx,
        ),
        PopupMenuButton<String>(
          tooltip: 'Game settings',
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.settings_rounded, size: 21, color: _cream),
          color: _panel,
          onSelected: (value) {
            switch (value) {
              case 'moves':
                _showMoves();
              case 'rules':
                _showRules();
              case 'music':
                _toggleMusic();
              case 'spectators':
                widget.socket.send('MUTE_SPECTATORS_TOGGLE');
              case 'exit':
                _leave();
            }
          },
          itemBuilder: (_) => [
            _menuItem('moves', Icons.format_list_numbered_rounded, 'Moves'),
            _menuItem('rules', Icons.help_outline_rounded, 'How to play'),
            _menuItem(
                'music',
                _musicOn ? Icons.music_note_rounded : Icons.music_off_rounded,
                _musicOn ? 'Mute music' : 'Play music'),
            if (!_amSpectator)
              _menuItem(
                  'spectators',
                  _spectatorsMuted
                      ? Icons.comments_disabled_rounded
                      : Icons.chat_bubble_outline_rounded,
                  _spectatorsMuted
                      ? 'Let spectators comment'
                      : 'Mute spectator comments'),
            _menuItem('exit', Icons.logout_rounded, 'Leave'),
          ],
        ),
      ]),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String text) =>
      PopupMenuItem(
        value: value,
        child: Row(children: [
          Icon(icon, size: 18, color: _gold),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(color: _cream)),
        ]),
      );

  Widget _roundButton(IconData icon, String tooltip, VoidCallback onTap) =>
      Tooltip(
        message: tooltip,
        child: Material(
          color: _panel,
          shape: const CircleBorder(
              side: BorderSide(color: Color(0x33ffffff), width: 1)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(icon, color: _cream, size: 20)),
          ),
        ),
      );

  /// One side of the table: who, what they've taken, and their clock.
  Widget _playerCard(String side) {
    final playerId = _view.playerFor(side);
    final isMe = !_amSpectator && side == _mySide;
    final active = !_view.finished && _view.turn == side;
    final taken =
        side == 'white' ? _view.capturedByWhite : _view.capturedByBlack;
    final lost =
        side == 'white' ? _view.capturedByBlack : _view.capturedByWhite;
    final lead = taken.fold<int>(0, (s, c) => s + pieceValue(c)) -
        lost.fold<int>(0, (s, c) => s + pieceValue(c));
    final highlight = active && (isMe || _amSpectator);
    return AnimatedContainer(
      key: ValueKey('chess-player-$side'),
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: highlight ? _gold : const Color(0x22ffffff),
            width: highlight ? 2 : 1),
        boxShadow: highlight
            ? [BoxShadow(color: _gold.withValues(alpha: .22), blurRadius: 12)]
            : null,
      ),
      child: Row(children: [
        ValueListenableBuilder<Set<String>>(
          valueListenable: widget.socket.onlinePlayers,
          builder: (_, online, __) => OnlineAvatar(
            isMe ? 'You' : _label(playerId),
            size: 40,
            voiceIdentity: playerId,
            online: online.contains(playerId),
            imageUrl: widget.socket.memberAvatars[playerId] ?? widget.avatars[playerId],
            emoji: widget.agents.contains(playerId) ? '🤖' : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Flexible(
                  child: Text(isMe ? 'YOU' : _label(playerId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _cream,
                          fontSize: 14,
                          fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: side == 'white'
                        ? _lightSquare
                        : const Color(0xff1b1b1b),
                    shape: BoxShape.circle,
                    border: Border.all(color: _mute, width: 1),
                  ),
                ),
              ]),
              const SizedBox(height: 3),
              SizedBox(
                height: 16,
                child: Row(children: [
                  Flexible(child: _capturedRow(taken)),
                  if (lead > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text('+$lead',
                          style: const TextStyle(
                              color: _mute,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                ]),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        if (side == (_amSpectator ? 'black' : _opponentSide)) _varButton(),
        const SizedBox(width: 4),
        _clockBox(side, isMe: isMe, active: active),
      ]),
    );
  }

  /// Replays the opponent's last move — never your own, you just saw it.
  bool get _varAvailable {
    final last = _lastVar;
    return last != null && (_amSpectator || last.side != _mySide);
  }

  Widget _varButton() {
    return SizedBox(
      width: 40,
      height: 38,
      child: TextButton(
        key: const ValueKey('chess-var-tv'),
        style: TextButton.styleFrom(padding: EdgeInsets.zero),
        onPressed: _varAvailable ? _openVar : null,
        child: VarTvIcon(
          enabled: _varAvailable,
          casing: _gold,
          screen: _panelDeep,
          label: _cream,
          disabled: const Color(0xff5d4a78),
        ),
      ),
    );
  }

  void _openVar() {
    final move = _lastVar;
    if (move == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ChessVarSheet(
        move: move,
        playerName: _label(_view.playerFor(move.side)),
        flipped: _flipped,
      ),
    );
  }

  Widget _capturedRow(List<String> codes) {
    final sorted = List<String>.of(codes)
      ..sort((a, b) => pieceValue(b).compareTo(pieceValue(a)));
    return ClipRect(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final code in sorted)
            Align(
              widthFactor: 0.62,
              child: ChessPieceGlyph(code: code, size: 17),
            ),
        ],
      ),
    );
  }

  Widget _clockBox(String side, {required bool isMe, required bool active}) {
    return ValueListenableBuilder<int>(
      valueListenable: _tick,
      builder: (_, __, ___) {
        final ms = _clockMs(side);
        final low = active && ms < 20000;
        final mineActive = isMe && active;
        return Container(
          key: ValueKey('chess-clock-$side'),
          constraints: const BoxConstraints(minWidth: 82),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            gradient: mineActive
                ? const LinearGradient(colors: [_gold, _goldDeep])
                : null,
            color: mineActive ? null : _panelDeep,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color:
                    low ? _danger : (active ? _gold : const Color(0x29ffffff)),
                width: active ? 1.6 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.timer_outlined,
                size: 14, color: mineActive ? const Color(0xff2a1600) : _mute),
            const SizedBox(width: 5),
            Text(formatClock(ms),
                style: TextStyle(
                    color: mineActive
                        ? const Color(0xff2a1600)
                        : (low ? _danger : _cream),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [ui.FontFeature.tabularFigures()])),
          ]),
        );
      },
    );
  }

  // --------------------------------------------------------------- board

  Widget _boardArea() {
    return LayoutBuilder(builder: (context, box) {
      final side =
          (box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight) - 12;
      if (side <= 40) return const SizedBox.shrink();
      const frame = 16.0;
      final cell = (side - 2 * frame) / 8;
      return Center(
        child: Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff8a5a2b), Color(0xff5a3416), Color(0xff7a4a20)],
            ),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black54, blurRadius: 18, offset: Offset(0, 8)),
            ],
            border: Border.all(color: const Color(0xff3a1f0b), width: 1.5),
          ),
          child: Stack(children: [
            // Rank numbers down the left, file letters along the bottom,
            // both turned with the board.
            for (var row = 0; row < 8; row++)
              Positioned(
                left: 0,
                width: frame,
                top: frame + row * cell,
                height: cell,
                child: Center(
                  child: Text('${_flipped ? row + 1 : 8 - row}',
                      style: const TextStyle(
                          color: Color(0xfff3d9a8),
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            for (var col = 0; col < 8; col++)
              Positioned(
                left: frame + col * cell,
                width: cell,
                bottom: 0,
                height: frame,
                child: Center(
                  child: Text(
                      String.fromCharCode(97 + (_flipped ? 7 - col : col)),
                      style: const TextStyle(
                          color: Color(0xfff3d9a8),
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            Positioned(
              left: frame,
              top: frame,
              width: cell * 8,
              height: cell * 8,
              child: _grid(cell),
            ),
            Positioned(
              left: frame,
              top: frame,
              width: cell * 8,
              height: cell * 8,
              child: IgnorePointer(child: _slideOverlay(cell)),
            ),
          ]),
        ),
      );
    });
  }

  Widget _grid(double cell) {
    final checkSquare = _view.inCheck ? _view.kingSquare(_view.turn) : null;
    final targets =
        _selected == null ? const <int>[] : _targetsFrom(_selected!);
    return Column(children: [
      for (var row = 0; row < 8; row++)
        Expanded(
          child: Row(children: [
            for (var col = 0; col < 8; col++)
              Expanded(
                child: _square(
                  squareAtCell(row, col, flipped: _flipped),
                  cell,
                  checkSquare: checkSquare,
                  targets: targets,
                ),
              ),
          ]),
        ),
    ]);
  }

  Widget _square(int sq, double cell,
      {required int? checkSquare, required List<int> targets}) {
    final light = (fileOf(sq) + rankOf(sq)) % 2 == 1;
    final piece = _view.board[sq];
    final isLast = sq == _view.lastFrom || sq == _view.lastTo;
    final isSelected = sq == _selected;
    final isTarget = targets.contains(sq);
    final sliding = _slide.isAnimating && sq == _slideTo;
    final draggable = _myTurn &&
        !_actionLocked &&
        colorOf(piece) == _myColor &&
        _targetsFrom(sq).isNotEmpty;

    Widget? pieceWidget;
    if (piece != null && !sliding) {
      final glyph = ChessPieceGlyph(code: piece, size: cell * 0.86);
      pieceWidget = draggable
          ? Draggable<int>(
              data: sq,
              feedback: SizedBox(
                  width: cell * 1.25,
                  height: cell * 1.25,
                  child: ChessPieceGlyph(code: piece, size: cell * 1.1)),
              childWhenDragging: const SizedBox.shrink(),
              dragAnchorStrategy: (_, __, ___) =>
                  Offset(cell * 0.62, cell * 0.95),
              onDragStarted: () {
                GameSfx.select();
                setState(() => _selected = sq);
              },
              child: glyph,
            )
          : glyph;
    }

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => _canMove(d.data, sq),
      onAcceptWithDetails: (d) => _attemptMove(d.data, sq),
      builder: (context, candidate, _) => GestureDetector(
        key: ValueKey('chess-square-${squareName(sq)}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _tapSquare(sq),
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(color: light ? _lightSquare : _darkSquare),
          if (isLast)
            ColoredBox(color: const Color(0xfff6e96b).withValues(alpha: .5)),
          if (isSelected)
            ColoredBox(color: const Color(0xffffcf66).withValues(alpha: .55)),
          if (sq == checkSquare)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [
                  Color(0xddff2a1a),
                  Color(0x66ff2a1a),
                  Color(0x00ff2a1a),
                ], stops: [
                  0.0,
                  0.55,
                  1.0
                ]),
              ),
            ),
          if (candidate.isNotEmpty)
            ColoredBox(color: Colors.white.withValues(alpha: .28)),
          if (pieceWidget != null) Center(child: pieceWidget),
          if (isTarget)
            Center(
              child: piece == null
                  ? Container(
                      width: cell * 0.3,
                      height: cell * 0.3,
                      decoration: const BoxDecoration(
                          color: Color(0x55000000), shape: BoxShape.circle),
                    )
                  : Container(
                      width: cell * 0.92,
                      height: cell * 0.92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0x66000000), width: cell * 0.08),
                      ),
                    ),
            ),
        ]),
      ),
    );
  }

  Widget _slideOverlay(double cell) {
    return AnimatedBuilder(
      animation: _slide,
      builder: (context, _) {
        final from = _slideFrom, to = _slideTo, piece = _slidePiece;
        if (!_slide.isAnimating ||
            from == null ||
            to == null ||
            piece == null) {
          return const SizedBox.shrink();
        }
        Offset cellOf(int sq) {
          final col = _flipped ? 7 - fileOf(sq) : fileOf(sq);
          final row = _flipped ? rankOf(sq) : 7 - rankOf(sq);
          return Offset(col * cell, row * cell);
        }

        final t = Curves.easeOutCubic.transform(_slide.value);
        final pos = Offset.lerp(cellOf(from), cellOf(to), t)!;
        return Stack(children: [
          Positioned(
            left: pos.dx,
            top: pos.dy,
            width: cell,
            height: cell,
            child:
                Center(child: ChessPieceGlyph(code: piece, size: cell * 0.86)),
          ),
        ]);
      },
    );
  }

  // ------------------------------------------------------- below the board

  /// A draw waiting on you, or one you're entitled to claim.
  Widget? _banner() {
    if (_amSpectator || _view.finished) return null;
    final pending = _view.pendingDrawOffer;
    if (pending != null && pending != widget.selfId) {
      return _bannerShell(
        key: const ValueKey('chess-draw-offer'),
        icon: Icons.handshake_rounded,
        text: '${_label(pending)} offers a draw',
        actions: [
          _bannerAction('Decline', () => _send('DECLINE_DRAW')),
          _bannerAction('Accept', () => _send('ACCEPT_DRAW'), primary: true),
        ],
      );
    }
    if (_myTurn && (_view.canClaimThreefold || _view.canClaimFiftyMove)) {
      return _bannerShell(
        key: const ValueKey('chess-draw-claim'),
        icon: Icons.balance_rounded,
        text: _view.canClaimThreefold
            ? 'Threefold repetition — you may claim a draw'
            : '50 moves without a capture — you may claim a draw',
        actions: [
          _bannerAction('Claim draw', () => _send('CLAIM_DRAW'), primary: true),
        ],
      );
    }
    return null;
  }

  Widget _bannerShell(
      {required Key key,
      required IconData icon,
      required String text,
      required List<Widget> actions}) {
    return Container(
      key: key,
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: _panelDeep,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gold.withValues(alpha: .6)),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: _gold),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _cream, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        ...actions,
      ]),
    );
  }

  Widget _bannerAction(String label, VoidCallback onTap,
          {bool primary = false}) =>
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: TextButton(
          style: TextButton.styleFrom(
            backgroundColor: primary ? _gold : Colors.transparent,
            foregroundColor: primary ? const Color(0xff2a1600) : _cream,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 32),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
          ),
          onPressed: onTap,
          child: Text(label),
        ),
      );

  Widget _actionRow() {
    final pending = _view.pendingDrawOffer;
    final drawLabel = pending != null && pending != widget.selfId
        ? 'Accept'
        : (pending == widget.selfId ? 'Offered' : 'Draw');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Row(children: [
        if (!_amSpectator) ...[
          Expanded(
              child: _controlButton(Icons.undo_rounded, 'Undo',
                  _view.finished ? null : _requestUndo)),
          const SizedBox(width: 6),
          Expanded(
              child: _controlButton(Icons.handshake_rounded, drawLabel,
                  _view.finished ? null : _drawButton)),
          const SizedBox(width: 6),
        ],
        Expanded(flex: 2, child: _statusPill()),
        if (!_amSpectator) ...[
          const SizedBox(width: 6),
          Expanded(
              child: _controlButton(Icons.flag_rounded, 'Resign',
                  _view.finished ? null : _confirmResign)),
        ],
      ]),
    );
  }

  Widget _statusPill() {
    final String text;
    if (_view.finished) {
      text = _view.winningSide == 'draw'
          ? 'DRAW'
          : (_amSpectator
              ? '${_view.winningSide?.toUpperCase()} WINS'
              : (_view.winningSide == _mySide ? 'YOU WIN' : 'YOU LOST'));
    } else if (_paused) {
      text = 'PAUSED';
    } else if (_myTurn) {
      text = _view.inCheck ? 'CHECK!' : 'YOUR MOVE';
    } else if (_amSpectator) {
      text = '${_view.turn.toUpperCase()} TO MOVE';
    } else {
      text = 'THEIR MOVE';
    }
    final hot = _myTurn || (_view.finished && _view.winningSide == _mySide);
    return GestureDetector(
      onTap: _view.finished ? () => setState(() => _showResults = true) : null,
      child: AnimatedContainer(
        key: const ValueKey('chess-status'),
        duration: const Duration(milliseconds: 220),
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient:
              hot ? const LinearGradient(colors: [_gold, _goldDeep]) : null,
          color: hot ? null : _panel,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
              color: _myTurn && _view.inCheck
                  ? _danger
                  : (hot ? _gold : const Color(0x33ffffff)),
              width: _myTurn && _view.inCheck ? 2 : 1),
          boxShadow: hot
              ? [BoxShadow(color: _gold.withValues(alpha: .35), blurRadius: 14)]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              _view.finished
                  ? Icons.emoji_events_rounded
                  : Icons.schedule_rounded,
              size: 16,
              color: hot ? const Color(0xff2a1600) : _mute),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: hot ? const Color(0xff2a1600) : _cream,
                    fontSize: 13,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w900)),
          ),
        ]),
      ),
    );
  }

  Widget _controlButton(IconData icon, String label, VoidCallback? onTap) {
    return Material(
      color: _panel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 19, color: onTap == null ? _mute : _gold),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: onTap == null ? _mute : _cream,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- results

  Widget _results() {
    final draw = _view.winningSide == 'draw';
    final won = !_amSpectator && _view.winningSide == _mySide;
    final title = draw
        ? 'Draw'
        : (_amSpectator
            ? '${_label(_view.playerFor(_view.winningSide ?? 'white'))} wins'
            : (won ? 'You win' : 'You lost'));
    final score =
        draw ? '½ – ½' : (_view.winningSide == 'white' ? '1 – 0' : '0 – 1');
    return Stack(children: [
      const Positioned.fill(child: ColoredBox(color: Color(0x99000000))),
      if (won) const Positioned.fill(child: IgnorePointer(child: Fireworks())),
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Container(
            key: const ValueKey('chess-results'),
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _gold, width: 1.5),
              boxShadow: [
                BoxShadow(color: _gold.withValues(alpha: .25), blurRadius: 24)
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(draw ? '🤝' : (won || _amSpectator ? '🏆' : '♚'),
                  style: const TextStyle(fontSize: 44, color: _cream)),
              const SizedBox(height: 6),
              Text(title,
                  style: const TextStyle(
                      color: _gold,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Georgia',
                      fontFamilyFallback: ['Times New Roman', 'serif'])),
              const SizedBox(height: 4),
              Text(describeResult(_view.resultReason),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _mute, fontSize: 13)),
              const SizedBox(height: 10),
              Text(score,
                  style: const TextStyle(
                      color: _cream,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFeatures: [ui.FontFeature.tabularFigures()])),
              if (_coinsAwarded != null) ...[
                const SizedBox(height: 8),
                Text('+$_coinsAwarded ${_coinsAwarded == 1 ? 'coin' : 'coins'}',
                    style: const TextStyle(
                        color: _gold, fontWeight: FontWeight.w800)),
              ],
              const SizedBox(height: 14),
              if (won)
                VictoryShareButton(
                    roomId: widget.socket.roomId, gameType: 'chess'),
              const SizedBox(height: 6),
              Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    TextButton(
                      key: const ValueKey('chess-view-board'),
                      onPressed: () => setState(() => _showResults = false),
                      child: const Text('View board',
                          style: TextStyle(color: _cream)),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: const Color(0xff2a1600)),
                      onPressed: _leave,
                      child: Text(_amSpectator ? 'Done' : 'Back to home',
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ]),
              if (!_amSpectator) const GuestSaveSessionCard(),
            ]),
          ),
        ),
      ),
    ]);
  }
}
