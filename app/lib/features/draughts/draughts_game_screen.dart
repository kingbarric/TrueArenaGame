import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/game_socket.dart';
import '../../theme/neon_theme.dart';
import '../../core/app_state.dart';
import '../../core/game_music.dart';
import '../../core/game_sfx.dart';
import '../../widgets/fireworks.dart';
import '../../widgets/how_to_play_dialog.dart';
import '../../widgets/neon.dart';
import '../../widgets/table_chat.dart';
import '../../widgets/game_voice_control.dart';
import '../shell/main_shell.dart';
import '../status/victory_status.dart';
import '../onboarding/guest_save_session_card.dart';
import 'draughts_rules.dart';
import 'draughts_theme.dart';
import 'draughts_var.dart';

/// International (10x10, 20-piece) Draughts — driven by the same
/// SNAPSHOT/PHASE/EVENT-in, PLAYER_ACTION-out contract as the other two
/// games. Nothing here is secret, so unlike `GameScreen`/`WordBluffGameScreen`
/// there's no per-viewer filtering to think about — every event the server
/// sends is exactly what's rendered.
///
/// Legal destinations come from the server's own `legalMoves` whenever a
/// snapshot carries them, and fall back to the local mirror of the rules in
/// `draughts_rules.dart` between snapshots (the server sends events, not a
/// fresh snapshot, after each move). The server re-validates every move
/// regardless — but a local rules bug is still worth avoiding: it can't
/// produce a wrong outcome, yet it can refuse a legal tap, which is how a
/// turn once froze until its timer ran out.
///
/// Tapping a piece selects it without marking every possible destination.
/// Tapping a legal square arms that one square; tapping it again commits.
/// A double tap or dragging the piece onto a legal square commits a complete
/// move in one gesture.
class DraughtsGameScreen extends StatefulWidget {
  const DraughtsGameScreen(
      {super.key,
      required this.socket,
      required this.selfId,
      required this.nicknames,
      this.championshipId,
      this.tournamentSpectator = false,
      this.spectating = false});

  final GameSocket socket;
  final String selfId;
  final Map<String, String> nicknames;
  final String? championshipId;
  final bool tournamentSpectator;
  final bool spectating;

  @override
  State<DraughtsGameScreen> createState() => _DraughtsGameScreenState();
}

/// One physical checker, tracked by a stable id (not by square) so the
/// animated overlay can slide it from its old square to its new one instead
/// of the piece just vanishing from one cell and appearing in another.
class _Piece {
  _Piece(this.id, this.square, this.type);
  final int id;
  int square;
  String type;
}

class _CapturedPiece {
  const _CapturedPiece(this.id, this.square, this.type,
      {required this.animate});
  final int id;
  final int square;
  final String type;
  final bool animate;
  String get side => type.startsWith('A') ? 'A' : 'B';
}

class _DraughtsGameScreenState extends State<DraughtsGameScreen> {
  static const _moveDuration = Duration(milliseconds: 420);
  static const _captureFadeDuration = Duration(milliseconds: 320);

  StreamSubscription? _sub;
  Timer? _ticker;
  Timer? _reconnectTicker;

  String phase = 'TurnA';
  int round = 1;
  String playerA = '';
  String playerB = '';
  List<String?> board = List<String?>.filled(boardSize, null);
  int? activeSquare;
  String? winningSide;

  /// How the board stood when it ended, and what this game paid out — both
  /// arrive with the final events and are shown on the results screen.
  int? _piecesA;
  int? _piecesB;
  int? _coinsAwarded;
  int turnSeconds = 60;
  int? _secondsLeft;
  final List<TableChatLine> feed = [];
  final TextEditingController _chatController = TextEditingController();

  int? _selected;
  int? _dragOrigin;
  Offset? _dragPosition;
  String? _dragPieceType;

  /// Landing squares chosen but not yet sent, in order — one box for an
  /// ordinary move, the whole jump sequence for a multiple capture.
  List<int> _chain = const [];
  bool _actionLocked = false;

  final List<_Piece> _pieces = [];
  final List<_CapturedPiece> _capturedPieces = [];
  int _nextPieceId = 0;
  int _nextCapturedId = 0;

  final DraughtsVarRecorder _var = DraughtsVarRecorder();

  bool _paused = false;
  String? _pendingDrawOffer;
  String? _awayPlayer;
  int? _reconnectSeconds;

  /// Seconds the current grace period will run for once resumed, from the
  /// server's TURN_GRACE event.
  int _graceSeconds = 0;
  bool _spectatorsMuted = false;
  int _spectatorCount = 0;
  bool _musicOn = GameMusic.enabled;
  bool _leaving = false;

  /// Whether this room forces captures. Off is a house rule the host can
  /// pick when making the room — see DraughtsConfig.
  bool _mandatoryCapture = false;
  bool _sfxOn = GameSfx.enabled;

  DraughtsThemeController? _theme;

  @override
  void initState() {
    super.initState();
    _sub = widget.socket.envelopes.listen(_onEnvelope);
    GameMusic.start(GameMusic.moodFor('draughts'));
    GameSfx.warmUp();
    // Always 0, not widget.socket.lastSeq: this is this screen's very first
    // listener on the socket, and by hand-off time the socket may already
    // have seen events from the lobby-transition screen's own listener —
    // forcing 0 guarantees the server's HELLO handler takes the full-
    // snapshot branch instead of a replay-only one that can reply with
    // nothing to replay and no board at all (the "board with no pieces
    // until you leave and reopen" bug).
    widget.socket.send('HELLO', {'lastSeq': 0});
    DraughtsThemeController.load().then((t) {
      if (!mounted) return;
      t.addListener(_onThemeChanged);
      setState(() => _theme = t);
    });
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.socket.close();
    _ticker?.cancel();
    _reconnectTicker?.cancel();
    _theme?.removeListener(_onThemeChanged);
    _chatController.dispose();
    GameMusic.stop();
    super.dispose();
  }

  /// The Grace phases ("GraceA1", "GraceA2", ...) are still that side's
  /// turn — the whole point of a grace period is that you can still play in
  /// it. Mirrors `DraughtsState.turnSide` on the server.
  String get turnSide =>
      (phase.startsWith('TurnA') || phase.startsWith('GraceA')) ? 'A' : 'B';
  String get mySide => widget.selfId == playerA ? 'A' : 'B';
  bool get myTurn =>
      !_amSpectator &&
      turnSide == mySide &&
      (phase.startsWith('Turn') || phase.startsWith('Grace'));

  /// True once the clock has run out at least once this turn — the room is
  /// paused and someone has to resume to start the shorter countdown.
  bool get _inGrace => phase.startsWith('Grace');

  /// The last chance: resuming starts a countdown that forfeits the game.
  bool get _lastChance => phase.endsWith('2') && _inGrace;
  bool get finished => phase == 'Results';
  String label(String id) =>
      widget.nicknames[id] ?? (id.length > 6 ? id.substring(0, 6) : id);

  /// How many pieces this turn's capture sequence must take in total, and
  /// how many of them have been taken so far.
  ///
  /// These mirror the server's `requiredCaptureCount` / `capturedSoFarThisTurn`
  /// and are deliberately *not* recomputed from the live board each time.
  /// Recomputing was a real bug: mid-chain it rescans every piece you own, so
  /// if some other piece could take more than the one you're mid-jump with,
  /// it demanded a total the active piece can no longer reach, highlighted
  /// nothing, and swallowed every tap until the turn timer ran out.
  int _turnRequired = 0;
  int _capturedSoFar = 0;

  /// The destinations the server published in the last snapshot, used
  /// verbatim while they're still current. This is what makes reconnecting
  /// mid-chain work: the counters above can't be recovered from the board
  /// alone, but the server's answer needs no recovering.
  Map<int, List<int>>? _serverLegal;

  /// What's left to capture on this turn — the figure the server validates
  /// a continuation against.
  int get _remainingRequired => (_turnRequired - _capturedSoFar).clamp(0, 99);

  /// Where a piece on [from] may legally land right now.
  List<int> _destinationsFrom(int from) {
    final server = _serverLegal;
    if (server != null) return server[from] ?? const <int>[];
    if (_remainingRequired > 0) {
      return legalDestinationsFrom(board, from, _remainingRequired);
    }
    final open = List<int>.of(simpleLandings(board, from));
    // With captures optional, a jump is simply one more move on offer.
    if (!_mandatoryCapture) {
      open.addAll(captureLandings(board, from).map((l) => l.to));
    }
    return open;
  }

  /// The board as it would stand after the jumps chosen so far, plus the
  /// square the piece would be sitting on. Derived from [board] + [_chain]
  /// rather than kept as a parallel copy, so it can't drift out of step with
  /// the real board; a chain that no longer fits (a snapshot landed while it
  /// was being built) collapses back to nothing chosen.
  (List<String?>, int)? _simulated() {
    final origin = _selected;
    if (origin == null) return null;
    var b = board;
    var head = origin;
    for (final to in _chain) {
      final landings =
          captureLandings(b, head).where((l) => l.to == to).toList();
      if (landings.isNotEmpty) {
        b = applyCaptureTo(b, head, landings.first);
      } else if (simpleLandings(b, head).contains(to)) {
        b = applySimpleMoveTo(b, head, to);
      } else {
        return (board, origin);
      }
      head = to;
    }
    return (b, head);
  }

  /// How many captures the sequence still owes. The server only accepts one
  /// that takes the maximum available, so a half-built chain isn't a move.
  int get _chainRemaining => _remainingRequired - _chain.length;

  /// Whether the first box chosen was a jump. A capture sequence has to be
  /// played out; an ordinary move is a single step.
  bool get _chainIsCapture =>
      _chain.isNotEmpty &&
      _selected != null &&
      captureLandings(board, _selected!).any((l) => l.to == _chain.first);

  bool get _chainComplete {
    if (_chain.isEmpty) return false;
    if (_remainingRequired > 0) return _chainRemaining == 0;
    // Captures optional: done once there's nothing left to take.
    return _nextSteps().isEmpty;
  }

  /// The boxes that may be tapped next: the next jump of a capture sequence,
  /// or the ordinary destinations when nothing is forced.
  List<int> _nextSteps() {
    final sim = _simulated();
    if (sim == null) return const [];
    final (b, head) = sim;
    if (_remainingRequired == 0) {
      if (_chain.isEmpty) return _destinationsFrom(head);
      // A jump you chose must be played out; an ordinary move is one step.
      if (!_chainIsCapture) return const [];
      return captureLandings(b, head).map((l) => l.to).toList();
    }
    if (_chainRemaining <= 0) return const [];
    // First jump: the server already published exactly what it will accept.
    if (_chain.isEmpty) return _destinationsFrom(head);
    return captureLandings(b, head)
        .where((l) =>
            1 + maxCaptureCount(applyCaptureTo(b, head, l), l.to) ==
            _chainRemaining)
        .map((l) => l.to)
        .toList();
  }

  void _clearSelection() {
    _selected = null;
    _chain = const [];
  }

  /// Recomputed only when the board is settled between turns, which is the
  /// one moment a board-wide scan gives the right answer.
  void _beginTurnFor(String side) {
    // Nothing is owed when the room doesn't force captures.
    _turnRequired = _mandatoryCapture ? requiredCaptureCount(board, side) : 0;
    _capturedSoFar = 0;
    _serverLegal = null;
  }

  void _onEnvelope(Map<String, dynamic> env) {
    switch (env['type']) {
      case 'CONNECTION':
        final connected = (env['payload'] as Map)['connected'] == true;
        _actionLocked = false;
        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.hideCurrentSnackBar();
          if (!connected) {
            messenger.showSnackBar(const SnackBar(
              content: Text('Connection lost. Reconnecting to the game…'),
              duration: Duration(minutes: 5),
            ));
          }
        }
      case 'SNAPSHOT':
        _applySnapshot((env['payload'] as Map).cast<String, dynamic>());
      case 'PHASE':
        _applyPhase((env['payload'] as Map).cast<String, dynamic>());
      case 'EVENT':
        _applyEvent((env['payload'] as Map).cast<String, dynamic>());
      case 'ERROR':
        final msg = (env['payload'] as Map)['message']?.toString() ??
            'something went wrong';
        _actionLocked = false;
        _selected = null;
        _chain = const [];
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
    }
  }

  void _applySnapshot(Map<String, dynamic> p) {
    setState(() {
      phase = p['phase'] as String? ?? phase;
      round = p['round'] as int? ?? round;
      playerA = p['playerA'] as String? ?? playerA;
      playerB = p['playerB'] as String? ?? playerB;
      final rawBoard = p['board'] as List?;
      if (rawBoard != null) {
        _var.reset();
        board = rawBoard.map((e) => e as String?).toList();
        _rebuildPiecesFromBoard(); // a fresh snapshot is a hard reset — nothing to animate from
        _syncCapturedFromBoard();
      }
      activeSquare = p['activeSquare'] as int?;
      // The server publishes the legal destinations it will actually accept.
      // Prefer them over anything computed here — they're the authority, and
      // they already account for a capture chain in progress.
      final rawLegal = p['legalMoves'] as Map?;
      _serverLegal = rawLegal == null
          ? null
          : {
              for (final e in rawLegal.entries)
                int.parse(e.key as String): ((e.value as List?) ?? const [])
                    .map((v) => v as int)
                    .toList(),
            };
      _turnRequired = requiredCaptureCount(board, turnSide);
      _capturedSoFar = 0;
      _paused = p['paused'] as bool? ?? _paused;
      final left = p['secondsLeft'] as int?;
      if (left != null) _secondsLeft = left;
      _spectatorsMuted = p['spectatorsMuted'] as bool? ?? _spectatorsMuted;
      _spectatorCount = p['spectatorCount'] as int? ?? _spectatorCount;
      _mandatoryCapture = p['mandatoryCapture'] as bool? ?? _mandatoryCapture;
      _pendingDrawOffer = p['pendingDrawOffer'] as String?;
    });
  }

  void _rebuildPiecesFromBoard() {
    _pieces.clear();
    for (var sq = 0; sq < board.length; sq++) {
      final type = board[sq];
      if (type != null) _pieces.add(_Piece(_nextPieceId++, sq, type));
    }
  }

  void _syncCapturedFromBoard() {
    // A reconnect supplies only the current board. Restore the missing
    // pieces to the trays without replaying capture animations.
    for (final side in ['A', 'B']) {
      final remaining =
          board.where((piece) => piece?.startsWith(side) ?? false).length;
      final missing = (20 - remaining).clamp(0, 20);
      var shown = _capturedPieces.where((piece) => piece.side == side).length;
      while (shown < missing) {
        _capturedPieces.add(_CapturedPiece(_nextCapturedId++, 0, '${side}_MAN',
            animate: false));
        shown++;
      }
      if (shown > missing) {
        for (var i = _capturedPieces.length - 1;
            i >= 0 && shown > missing;
            i--) {
          if (_capturedPieces[i].side == side) {
            _capturedPieces.removeAt(i);
            shown--;
          }
        }
      }
    }
  }

  _Piece? _pieceAt(int square) {
    for (final p in _pieces) {
      if (p.square == square) return p;
    }
    return null;
  }

  void _applyPhase(Map<String, dynamic> p) {
    setState(() {
      phase = p['phase'] as String? ?? phase;
      round = p['round'] as int? ?? round;
      _actionLocked = false;
    });
    if (phase.startsWith('Turn')) _restartCountdown();
  }

  void _restartCountdown() => _startCountdown(turnSeconds);

  /// Runs the visible clock from [seconds]. Separate from [_restartCountdown]
  /// so a resume can pick up the server's remaining time instead of starting
  /// the turn over.
  void _startCountdown(int seconds) {
    _ticker?.cancel();
    if (seconds <= 0) {
      setState(() => _secondsLeft = null);
      return;
    }
    setState(() => _secondsLeft = seconds);
    if (_paused) return; // paused: show the frozen number, don't tick
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        _secondsLeft = (_secondsLeft ?? 1) - 1;
        if (_secondsLeft! <= 0) t.cancel();
      });
    });
  }

  /// The server freezes the real clock on pause (see
  /// GameOrchestrator.freezeTimer) — this just stops the display from
  /// counting down past it, and resumes from whatever the server says is
  /// actually left.
  void _applyPause(bool paused, Map<String, dynamic> data) {
    _paused = paused;
    final left = data['secondsLeft'] as int?;
    if (paused) {
      _ticker?.cancel();
      if (left != null) _secondsLeft = left;
    } else {
      _startCountdown(left ?? _secondsLeft ?? turnSeconds);
    }
  }

  /// Everything anyone says lands in the one box: the players' table talk,
  /// the agents', and the spectators' — they're all just people talking
  /// around the same game, and splitting them across a bar and a sheet only
  /// meant most of it went unread.
  void _onChat(Map<String, dynamic> data) {
    final text = data['text']?.toString().trim() ?? '';
    if (text.isEmpty) return;
    final channel = data['channel']?.toString();
    final from = data['from']?.toString();
    setState(() => feed.insert(
        0,
        TableChatLine(
          who: from == null ? 'Cyber Agent' : label(from),
          text: text,
          isAgent: channel == 'agent',
          isSpectator: channel == 'spectate',
        )));
  }

  /// Spectators talk on the muteable `spectate` channel; players talk on
  /// `table`. Same box either way — the split only exists so muting
  /// spectators doesn't also silence the two people playing.
  bool get _amSpectator =>
      widget.spectating || (widget.selfId != playerA && widget.selfId != playerB);

  void _sendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    widget.socket.send('CHAT_SEND',
        {'channel': _amSpectator ? 'spectate' : 'table', 'text': text});
    _chatController.clear();
  }

  void _applyEvent(Map<String, dynamic> payload) {
    final type = payload['type'] as String;
    final data =
        ((payload['data'] as Map?) ?? const {}).cast<String, dynamic>();
    if (type == 'CHAT_MESSAGE') {
      _onChat(data);
      return;
    }
    setState(() {
      switch (type) {
        case 'GAME_PAUSED':
          _applyPause(true, data);
        case 'GAME_RESUMED':
          _applyPause(false, data);
        case 'SPECTATORS_MUTED':
          _spectatorsMuted = true;
        case 'SPECTATORS_UNMUTED':
          _spectatorsMuted = false;
        case 'GAME_STARTED':
          _var.reset();
          playerA = data['playerA'] as String;
          playerB = data['playerB'] as String;
          board = (data['board'] as List).map((e) => e as String?).toList();
          _capturedPieces.clear();
          turnSeconds = data['turnSeconds'] as int? ?? turnSeconds;
          _rebuildPiecesFromBoard();
          _beginTurnFor(turnSide);
          _restartCountdown();
        case 'PIECE_MOVED':
          _pendingDrawOffer = null;
          final from = data['from'] as int, to = data['to'] as int;
          _var.move(board, data['side'] as String, from, to);
          board[to] = board[from];
          board[from] = null;
          _pieceAt(from)?.square =
              to; // AnimatedPositioned interpolates to the new cell
          _serverLegal = null; // the board has moved on past that snapshot
          GameSfx.move();
          activeSquare = null;
          _selected = null;
          _chain = const [];
        case 'PIECE_CAPTURED':
          _pendingDrawOffer = null;
          final from = data['from'] as int,
              to = data['to'] as int,
              captured = data['captured'] as int;
          _var.move(board, data['side'] as String, from, to,
              captured: captured);
          final victim = _pieceAt(captured);
          final victimType = victim?.type ?? board[captured];
          board[to] = board[from];
          board[from] = null;
          board[captured] = null;
          _pieceAt(from)?.square = to;
          if (victim != null) {
            _pieces.remove(victim);
          }
          if (victimType != null) {
            _capturedPieces.add(_CapturedPiece(
                _nextCapturedId++, captured, victimType,
                animate: true));
          }
          _capturedSoFar++;
          _serverLegal = null; // the board has moved on past that snapshot
          // Taking sounds like a reward; being taken sounds like a loss.
          if ((data['side'] as String?) == mySide) {
            GameSfx.capture();
          } else {
            GameSfx.captured();
          }
          activeSquare =
              to; // may be overridden back to null by a following TURN_STARTED
          _selected = to;
          _chain = const [];
        case 'PIECE_PROMOTED':
          final sq = data['square'] as int, side = data['side'] as String;
          _var.promote(sq);
          GameSfx.king();
          board[sq] = '${side}_KING';
          final p = _pieceAt(sq);
          if (p != null) p.type = '${side}_KING';
        case 'TURN_STARTED':
          _var.complete();
          _beginTurnFor(data['side'] as String? ?? turnSide);
          activeSquare = null;
          _selected = null;
          _chain = const [];
        case 'SPECTATOR_COUNT':
          _spectatorCount = data['count'] as int? ?? _spectatorCount;
        case 'TURN_GRACE':
          _graceSeconds = data['seconds'] as int? ?? 0;
          _selected = null;
          _chain = const [];
        case 'COINS_AWARDED':
          _coinsAwarded = data['amount'] as int?;
        case 'GAME_OVER':
          _var.complete();
          winningSide = data['winningSide'] as String?;
          _piecesA = data['piecesA'] as int?;
          _piecesB = data['piecesB'] as int?;
          _ticker?.cancel();
          GameMusic.playOutcome(won: winningSide == mySide);
        case 'DRAW_OFFERED':
          _pendingDrawOffer = data['by']?.toString();
        case 'RECONNECT_WAIT':
          _applyReconnectWait(data);
      }
      final line = _describe(type, data);
      if (line != null) feed.insert(0, TableChatLine.system(line));
    });
  }

  void _applyReconnectWait(Map<String, dynamic> data) {
    _reconnectTicker?.cancel();
    final missing =
        (data['missing'] as List?)?.whereType<Map>().toList() ?? const [];
    if (missing.isEmpty) {
      _awayPlayer = null;
      _reconnectSeconds = null;
      return;
    }
    final selected = missing.firstWhere((m) => m['userId'] != widget.selfId,
        orElse: () => missing.first);
    _awayPlayer = selected['userId']?.toString();
    _reconnectSeconds = (selected['secondsLeft'] as num?)?.toInt() ?? 0;
    _reconnectTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() {
        _reconnectSeconds = (_reconnectSeconds! - 1).clamp(0, 180);
        if (_reconnectSeconds == 0) timer.cancel();
      });
    });
  }

  String? _describe(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'TURN_GRACE':
        final who = label(_actorFor(data['side'] as String));
        final secs = data['seconds'] as int? ?? 0;
        return (data['lastChance'] as bool? ?? false)
            ? '$who ran out of time — last chance, $secs seconds once resumed.'
            : '$who ran out of time — the game is paused for them.';
      case 'PIECE_CAPTURED':
        return '${label(_actorFor(data['side'] as String))} captures.';
      case 'PIECE_PROMOTED':
        return '${label(_actorFor(data['side'] as String))} crowns a king!';
      case 'GAME_OVER':
        return data['winningSide'] == 'draw'
            ? 'Game drawn. The pairing will replay.'
            : '${label(_actorFor(data['winningSide'] as String))} wins!';
      case 'GAME_PAUSED':
        return '${label(data['by']?.toString() ?? '')} paused the game.';
      case 'GAME_RESUMED':
        return 'Game resumed.';
      default:
        return null;
    }
  }

  String _actorFor(String side) => side == 'A' ? playerA : playerB;

  /// Single tap: pick a piece, then tap each box it lands on. A capture that
  /// can keep jumping keeps offering the next box, and every box chosen so
  /// far stays lit — so a double or triple take is picked out in full before
  /// any of it is sent. Tapping the final box a second time commits the
  /// whole sequence. An ordinary move is the same gesture with a one-box
  /// chain, which is why it still feels like tap-to-arm, tap-to-commit.
  ///
  /// Tapping the last chosen box while the sequence is unfinished takes that
  /// jump back — the only way to change your mind mid-sequence.
  void _tap(int square) {
    if (!myTurn || _actionLocked || _paused) return;
    final forced = activeSquare;

    if (_selected == null) {
      final piece = DraughtsPiece.parse(board[square]);
      if (piece == null || piece.side != mySide) return;
      if (forced != null && square != forced) {
        GameSfx.illegal(); // mid-chain: only that piece may move
        return;
      }
      if (_destinationsFrom(square).isEmpty) {
        GameSfx.illegal(); // a piece of yours, but it has nowhere to go
        return;
      }
      GameSfx.select();
      setState(() {
        _selected = square;
        _chain = const [];
      });
      return;
    }

    if (_nextSteps().contains(square)) {
      setState(() => _chain = [..._chain, square]);
      // The tick climbs with each jump, so a double or triple take is
      // audible as it's picked out.
      GameSfx.chain(_chain.length);
      return;
    }

    if (_chain.isNotEmpty && square == _chain.last) {
      if (_chainComplete) {
        _commitChain();
      } else {
        setState(() => _chain = _chain.sublist(0, _chain.length - 1));
      }
      return;
    }

    if (square == _selected) {
      setState(_clearSelection);
      return;
    }

    final piece = DraughtsPiece.parse(board[square]);
    if (piece != null &&
        piece.side == mySide &&
        forced == null &&
        _destinationsFrom(square).isNotEmpty) {
      GameSfx.select();
      setState(() {
        _selected = square;
        _chain = const [];
      });
      return;
    }
    // Anything else while a piece is held: the board refuses the tap, and
    // says so rather than just doing nothing.
    GameSfx.illegal();
  }

  /// Double-tap the box that finishes a sequence to commit it in one gesture.
  void _doubleTap(int square) {
    if (!myTurn || _actionLocked || _paused || _selected == null) return;
    if (_nextSteps().contains(square)) {
      setState(() => _chain = [..._chain, square]);
    }
    if (_chain.isNotEmpty && _chain.last == square && _chainComplete) {
      _commitChain();
    }
  }

  int? _squareAt(Offset position, double cellSize, bool flipped) {
    if (position.dx < 0 || position.dy < 0 || cellSize <= 0) return null;
    final col = position.dx ~/ cellSize;
    final displayRow = position.dy ~/ cellSize;
    if (col >= 10 || displayRow >= 10) return null;
    final row = flipped ? displayRow : 9 - displayRow;
    return isPlayable(row, col) ? squareOf(row, col) : null;
  }

  void _startDrag(Offset position, double cellSize, bool flipped) {
    final square = _squareAt(position, cellSize, flipped);
    if (square == null || !myTurn || _actionLocked || _paused) return;
    if (_selected != square) _tap(square);
    if (_selected != square) return;
    setState(() {
      _dragOrigin = square;
      _dragPosition = position;
      _dragPieceType = board[square];
    });
  }

  void _updateDrag(Offset position) {
    if (_dragOrigin == null) return;
    setState(() => _dragPosition = position);
  }

  void _endDrag(double cellSize, bool flipped) {
    final origin = _dragOrigin;
    final position = _dragPosition;
    if (origin == null) return;
    setState(() {
      _dragOrigin = null;
      _dragPosition = null;
      _dragPieceType = null;
    });
    if (position == null) return;
    final target = _squareAt(position, cellSize, flipped);
    if (target == null || target == origin || !_nextSteps().contains(target)) {
      return;
    }
    _tap(target);
    if (_chainComplete) _commitChain();
  }

  void _cancelDrag() {
    if (_dragOrigin == null) return;
    setState(() {
      _dragOrigin = null;
      _dragPosition = null;
      _dragPieceType = null;
    });
  }

  /// Sends the chosen sequence one jump at a time — the wire protocol takes a
  /// single from/to per action, and the server applies them in order under
  /// its room lock, re-validating each one.
  void _commitChain() {
    if (!widget.socket.isConnected) return;
    final origin = _selected;
    if (origin == null || _chain.isEmpty) return;
    final jumps = <(int, int)>[];
    var from = origin;
    for (final to in _chain) {
      jumps.add((from, to));
      from = to;
    }
    setState(() {
      _actionLocked = true;
      _clearSelection();
    });
    for (final (f, t) in jumps) {
      widget.socket.send('PLAYER_ACTION', {
        'action': 'MOVE',
        'data': {'from': f, 'to': t}
      });
    }
  }

  void _openVar() {
    final turn = _var.lastCompleted;
    if (turn == null || (!_amSpectator && turn.side == mySide)) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff241708),
      builder: (_) => _VarReplaySheet(
        turn: turn,
        boardPalette: _theme?.board ?? boardPalettes.first,
        piecePalette: _theme?.piece ?? piecePalettes.first,
        flipped: mySide == 'B',
        playerName: label(_actorFor(turn.side)),
      ),
    );
  }

  /// Pausing blurs the board for *both* players (and any spectators) — it's
  /// a room-level toggle on the server (`PAUSE_TOGGLE`, GameOrchestrator),
  /// not local UI state, so it's genuinely synced rather than one side
  /// staring at a frozen opponent who's still moving.
  void _togglePause() => widget.socket.send('PAUSE_TOGGLE');

  void _showHelp() {
    showHowToPlay(
      context,
      emoji: '🔴',
      title: 'Draughts',
      tagline: 'Classic checkers — capture your way across the board and crown '
          'a king when you reach the far row.',
      steps: [
        'Tap your piece, then tap a legal box to mark it. Tap that box again or double tap it to move. You can also drag the piece onto a legal box.',
        'Move a piece diagonally, one square forward, onto an empty square.',
        _mandatoryCapture
            ? "If you can jump over an opponent's piece, you must take the capture that wins the most pieces."
            : "You can jump over an opponent's piece into an empty square, but taking is optional.",
        'Chain multiple captures in one turn whenever another jump is available afterward.',
        'Reach the far row and your piece is crowned a king — kings move and capture diagonally in any direction.',
        'Win by capturing every opposing piece, or by leaving your opponent with no legal move.',
      ],
    );
  }

  /// Resuming out of the final grace starts a countdown that ends the game,
  /// so it asks first — accepting and then not playing loses, which is
  /// exactly what the dialog says it will do.
  Future<void> _resumeFromGrace() async {
    if (!_lastChance) {
      _togglePause();
      return;
    }
    final opponent = label(_actorFor(mySide == 'A' ? 'B' : 'A'));
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Last chance'),
        content: Text(
          myTurn
              ? 'Resume and you have $_graceSeconds seconds to play. '
                  "If you don't move in time, the game ends and $opponent wins."
              : 'Resume and ${label(_actorFor(turnSide))} has $_graceSeconds seconds to play. '
                  "If they don't move in time, the game ends.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Not yet')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Resume')),
        ],
      ),
    );
    if (go == true) _togglePause();
  }

  /// The blurred cover over the board while the game is paused. It doubles
  /// as the grace-period screen: the clock only starts when someone here
  /// presses Resume, which is what stops a grace being spent by the player
  /// who isn't there to use it.
  Widget _pauseOverlay() {
    final tournament = widget.championshipId != null;
    final (icon, title, body) = tournament
        ? (
            Icons.wifi_off_rounded,
            'RECONNECT WAIT',
            _awayPlayer == null
                ? 'Waiting for both players to connect.'
                : '${label(_awayPlayer!)} has ${_reconnectSeconds ?? 0} seconds to return.'
          )
        : switch ((_inGrace, _lastChance, myTurn)) {
            (false, _, _) => (
                Icons.pause_circle_filled_rounded,
                'PAUSED',
                null
              ),
            (true, true, true) => (
                Icons.warning_amber_rounded,
                'LAST CHANCE',
                "Resume and you'll have $_graceSeconds seconds to play, or you lose.",
              ),
            (true, true, false) => (
                Icons.warning_amber_rounded,
                'LAST CHANCE',
                '${label(_actorFor(turnSide))} gets $_graceSeconds seconds once resumed.',
              ),
            (true, false, true) => (
                Icons.timer_off_rounded,
                "TIME'S UP",
                'Resume for another $_graceSeconds seconds.',
              ),
            (true, false, false) => (
                Icons.timer_off_rounded,
                "TIME'S UP",
                'Waiting for ${label(_actorFor(turnSide))} — $_graceSeconds seconds once resumed.',
              ),
          };
    final accent =
        _lastChance ? const Color(0xffe0704a) : const Color(0xfff0d8a8);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: Colors.black.withValues(alpha: 0.45),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: accent, size: 46),
            const SizedBox(height: 10),
            Text(title,
                style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3)),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xffc9b18c), fontSize: 12, height: 1.35)),
            ],
            const SizedBox(height: 14),
            if (!tournament) NeonButton('Resume', onPressed: _resumeFromGrace),
          ]),
        ),
      ),
    );
  }

  /// Any player can silence the spectate-channel comments — spectators keep
  /// watching, they just lose the live comment stream (see
  /// `GameOrchestrator.handleMuteSpectatorsToggle`).
  void _toggleMuteSpectators() => widget.socket.send('MUTE_SPECTATORS_TOGGLE');

  /// Silences the background piano without leaving the game. It's the same
  /// switch as the one in Settings and it sticks — someone who mutes the
  /// music mid-match meant it for more than this match.
  /// Silences the board's own sounds — taps, knocks, captures — separately
  /// from the music, since wanting one without the other is common.
  Future<void> _toggleSfx() async {
    final next = !_sfxOn;
    setState(() => _sfxOn = next);
    await GameSfx.setEnabled(next);
    if (next) GameSfx.select(); // a small confirmation you can hear
  }

  Future<void> _toggleMusic() async {
    final next = !_musicOn;
    setState(() => _musicOn = next);
    await GameMusic.setEnabled(next);
  }

  void _openThemeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff241708),
      builder: (_) => _BoardThemeSheet(theme: _theme!),
    );
  }

  Future<void> _confirmExit() async {
    if (widget.spectating) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xff241708),
        title: const Text('Leave the game?',
            style: TextStyle(color: Color(0xfff0d8a8))),
        content: Text(
            widget.championshipId == null
                ? 'A game against a system Cyber Agent will end. Other games can be rejoined with the huud code.'
                : 'You can reopen this pairing from the championship bracket.',
            style: const TextStyle(color: Color(0xffc9b18c))),
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
    if (leave == true && mounted && !_leaving) {
      _leaving = true;
      final app = AppScope.of(context);
      if (widget.championshipId == null) {
        try {
          final endedBotGame = await app.api
                  .post('/rooms/${widget.socket.roomId}/leave-draughts') ==
              true;
          if (endedBotGame || finished) {
            await app.clearActiveRoom(widget.socket.roomId);
          }
        } catch (_) {
          _leaving = false;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Server error. Please try again.')),
            );
          }
          return;
        }
      }
      if (!mounted) return;
      widget.socket.close();
      if (widget.championshipId != null) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainShell()), (r) => false);
      }
    }
  }

  Future<void> _confirmForfeit() async {
    final end = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xff241708),
        title: const Text('End this game?',
            style: TextStyle(color: Color(0xfff0d8a8))),
        content: const Text(
            'Your opponent will be awarded the win. This can\'t be undone.',
            style: TextStyle(color: Color(0xffc9b18c))),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep playing')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('End game',
                  style: TextStyle(color: Color(0xffe0704a)))),
        ],
      ),
    );
    if (end == true) {
      widget.socket.send('PLAYER_ACTION', {'action': 'FORFEIT', 'data': {}});
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: finished || widget.tournamentSpectator || widget.spectating,
      child: Scaffold(
        backgroundColor: const Color(0xff1c130a),
        appBar: AppBar(
          title: Text(finished ? 'Results' : 'Round $round'),
          automaticallyImplyLeading:
              finished || widget.tournamentSpectator || widget.spectating,
          backgroundColor: const Color(0xff241708),
          foregroundColor: const Color(0xfff0d8a8),
          // Only Pause earns a permanent button — it's the one thing you
          // reach for mid-game. The rest are settings you touch once a
          // match, so they live behind the gear rather than spending top-bar
          // space on icons whose meaning isn't obvious.
          actions: finished
              ? null
              : [
                  if (widget.championshipId == null || !_amSpectator)
                    GameVoiceControl(
                      roomId: widget.socket.roomId,
                      socket: widget.socket,
                      selfId: widget.selfId,
                      nicknames: widget.nicknames,
                      spectating: _amSpectator,
                    ),
                  if (widget.championshipId == null && !_amSpectator)
                    IconButton(
                      tooltip: _paused ? 'Resume' : 'Pause',
                      icon: Icon(
                          _paused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          size: 22),
                      onPressed: _togglePause,
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Game settings',
                    icon: const Icon(Icons.settings_rounded, size: 20),
                    color: const Color(0xff241708),
                    onSelected: (value) {
                      switch (value) {
                        case 'help':
                          _showHelp();
                        case 'theme':
                          _openThemeSheet();
                        case 'music':
                          _toggleMusic();
                        case 'sfx':
                          _toggleSfx();
                        case 'spectators':
                          _toggleMuteSpectators();
                        case 'forfeit':
                          _confirmForfeit();
                        case 'offer_draw':
                          widget.socket.send('PLAYER_ACTION',
                              {'action': 'OFFER_DRAW', 'data': {}});
                        case 'accept_draw':
                          widget.socket.send('PLAYER_ACTION',
                              {'action': 'ACCEPT_DRAW', 'data': {}});
                        case 'exit':
                          _confirmExit();
                      }
                    },
                    itemBuilder: (_) => [
                      _menuItem(
                          'help', Icons.help_outline_rounded, 'How to play'),
                      if (_theme != null)
                        _menuItem('theme', Icons.palette_outlined,
                            'Board & piece colours'),
                      _menuItem(
                        'music',
                        _musicOn
                            ? Icons.music_note_rounded
                            : Icons.music_off_rounded,
                        _musicOn ? 'Mute music' : 'Play music',
                      ),
                      _menuItem(
                        'sfx',
                        _sfxOn
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        _sfxOn ? 'Mute game sounds' : 'Play game sounds',
                      ),
                      if (!_amSpectator)
                        _menuItem(
                          'spectators',
                          _spectatorsMuted
                              ? Icons.comments_disabled_rounded
                              : Icons.chat_bubble_outline_rounded,
                          _spectatorsMuted
                              ? 'Let spectators comment'
                              : 'Mute spectator comments',
                        ),
                      if (!_amSpectator)
                        _menuItem('forfeit', Icons.flag_outlined, 'End game'),
                      if (!_amSpectator && _pendingDrawOffer == null)
                        _menuItem('offer_draw', Icons.handshake_outlined,
                            'Offer a draw'),
                      if (!_amSpectator &&
                          _pendingDrawOffer != null &&
                          _pendingDrawOffer != widget.selfId)
                        _menuItem('accept_draw', Icons.handshake_rounded,
                            'Accept draw'),
                      _menuItem('exit', Icons.logout_rounded, 'Leave'),
                    ],
                  ),
                ],
        ),
        body: SafeArea(
          // The board doesn't snap away — it settles back and dissolves as
          // the result comes forward, so the end of a game reads as an
          // arrival rather than a screen swap.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 620),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final isIncoming = child.key == const ValueKey('results');
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: isIncoming ? 0.92 : 1.04, end: 1)
                      .animate(animation),
                  child: child,
                ),
              );
            },
            child: finished
                ? KeyedSubtree(
                    key: const ValueKey('results'),
                    child: _results(context.neon))
                : KeyedSubtree(
                    key: const ValueKey('board'), child: _board(context.neon)),
          ),
        ),
      ),
    );
  }

  Widget _board(NeonColors n) {
    final flipped = mySide == 'B';
    final boardPalette = _theme?.board ?? boardPalettes.first;
    final piecePalette = _theme?.piece ?? piecePalettes.first;

    return Column(children: [
      _statusBar(n),
      _turnBanner(),
      Expanded(
        child: LayoutBuilder(builder: (context, constraints) {
          final trayHeight = math.min(38.0, constraints.maxHeight * 0.09);
          final boardSide = math.max(
              1.0,
              math.min(constraints.maxWidth,
                  constraints.maxHeight - 2 * trayHeight));
          final cellSize = math.max(1.0, (boardSide - 28) / 10);
          final captureSize = cellSize * 0.78;
          return Center(
            child: SizedBox(
              width: boardSide,
              height: boardSide + 2 * trayHeight,
              child: Stack(clipBehavior: Clip.none, children: [
                // Top strip is the far tray (your opponent's) — it holds the
                // count of your own men they've taken. Bottom is yours — the
                // men you've captured from them, matching where those pieces
                // actually fly to in _captureLanding.
                Positioned(
                  top: 0,
                  width: boardSide,
                  height: trayHeight,
                  child: _captureTray(
                      mySide,
                      _capturedPieces
                          .where((piece) => piece.side == mySide)
                          .length,
                      piecePalette),
                ),
                Positioned(
                  top: trayHeight + boardSide,
                  width: boardSide,
                  height: trayHeight,
                  child: _captureTray(
                      mySide == 'A' ? 'B' : 'A',
                      _capturedPieces
                          .where((piece) => piece.side != mySide)
                          .length,
                      piecePalette),
                ),
                Positioned(
                  top: trayHeight,
                  width: boardSide,
                  height: boardSide,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _boardSurface(boardPalette, piecePalette, flipped),
                  ),
                ),
                for (final captured in _capturedPieces)
                  _CapturedPieceFlight(
                    key: ValueKey('capture-${captured.id}'),
                    captured: captured,
                    palette: piecePalette,
                    size: captureSize,
                    start: Offset(
                      14 +
                          colOf(captured.square) * cellSize +
                          (cellSize - captureSize) / 2,
                      trayHeight +
                          14 +
                          (flipped
                                  ? rowOf(captured.square)
                                  : 9 - rowOf(captured.square)) *
                              cellSize +
                          (cellSize - captureSize) / 2,
                    ),
                    end: _captureLanding(captured, boardSide, trayHeight),
                    arcHeight: boardSide * 0.18,
                  ),
              ]),
            ),
          );
        }),
      ),
      if (!_amSpectator) _actionBar(),
      if (widget.championshipId == null || !_amSpectator) _chatPanel(n),
    ]);
  }

  /// The same four-button row Macala gives its players — a request, an
  /// offer, the rules, and a way out, always in reach below the board.
  Widget _actionBar() {
    final pendingFromOpponent =
        _pendingDrawOffer != null && _pendingDrawOffer != widget.selfId;
    final offeredByMe = _pendingDrawOffer == widget.selfId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Row(children: [
        Expanded(
            child: _controlButton(
                Icons.undo_rounded, 'Request undo', _requestUndo)),
        const SizedBox(width: 5),
        Expanded(
            child: _controlButton(
                Icons.handshake_rounded,
                pendingFromOpponent ? 'Accept draw' : 'Offer draw',
                () => _offerOrAcceptDraw(pendingFromOpponent, offeredByMe))),
        const SizedBox(width: 5),
        Expanded(
            child:
                _controlButton(Icons.help_outline_rounded, 'Rules', _showHelp)),
        const SizedBox(width: 5),
        Expanded(
            child:
                _controlButton(Icons.flag_rounded, 'Resign', _confirmForfeit)),
      ]),
    );
  }

  Widget _controlButton(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: const Color(0xff241708),
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: SizedBox(
          height: 54,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 19, color: const Color(0xffe0a94a)),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: Color(0xfff0d8a8), fontSize: 8.5)),
          ]),
        ),
      ),
    );
  }

  /// Draughts has no real undo — like Macala's, this is a nudge to your
  /// opponent, not an action the server will act on.
  void _requestUndo() {
    widget.socket
        .send('CHAT_SEND', {'channel': 'table', 'text': 'requests an undo.'});
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request sent to your opponent.')));
  }

  void _offerOrAcceptDraw(bool pendingFromOpponent, bool offeredByMe) {
    if (pendingFromOpponent) {
      widget.socket
          .send('PLAYER_ACTION', {'action': 'ACCEPT_DRAW', 'data': {}});
      return;
    }
    if (offeredByMe) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Waiting for your opponent to respond.')));
      return;
    }
    widget.socket.send('PLAYER_ACTION', {'action': 'OFFER_DRAW', 'data': {}});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Draw offered.')));
  }

  Offset _captureLanding(
      _CapturedPiece captured, double boardSide, double trayHeight) {
    final index = _capturedPieces
        .takeWhile((piece) => piece.id != captured.id)
        .where((piece) => piece.side == captured.side)
        .length;
    final spread = math.max(1, (boardSide - 68).floor());
    final x = 48.0 + ((index * 61) % spread);
    // A piece you captured is a trophy — it lands on *your* side (the tray
    // nearest you), not your opponent's. Only a piece they took off you
    // flies to their side instead.
    final top = captured.side == mySide;
    final y = (top ? 4.0 : trayHeight + boardSide + 4.0) + ((index * 7) % 12);
    return Offset(x, y);
  }

  Widget _captureTray(String side, int count, PiecePalette palette) {
    final sideColor = side == 'A' ? palette.aTop : palette.bTop;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff241708),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff5c3a1c), width: 1),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 8),
      child: Text('$side · $count',
          style: TextStyle(
              color: sideColor,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4)),
    );
  }

  Widget _boardSurface(
      BoardPalette boardPalette, PiecePalette piecePalette, bool flipped) {
    return Stack(children: [
      _WoodFrame(
        palette: boardPalette,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cellSize = constraints.maxWidth / 10;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onPanStart: (details) =>
                  _startDrag(details.localPosition, cellSize, flipped),
              onPanUpdate: (details) => _updateDrag(details.localPosition),
              onPanEnd: (_) => _endDrag(cellSize, flipped),
              onPanCancel: _cancelDrag,
              child: Stack(children: [
                GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 10),
                  itemCount: 100,
                  itemBuilder: (context, i) {
                    final displayRow = i ~/ 10, displayCol = i % 10;
                    final row = flipped ? displayRow : 9 - displayRow;
                    final col = displayCol;
                    if (!isPlayable(row, col)) {
                      return _PlankCell(
                          palette: boardPalette, dark: false, inert: true);
                    }
                    final sq = squareOf(row, col);
                    return GestureDetector(
                      onTap: () => _tap(sq),
                      onDoubleTap: () => _doubleTap(sq),
                      child: _PlankCell(
                        palette: boardPalette,
                        // Every playable square is the board's dark colour and
                        // every other one its light colour — a plain checkerboard.
                        // (It used to mix dark and light among the playable
                        // squares and paint the rest near-black, so the grid
                        // never read clearly on any colour scheme.)
                        dark: true,
                        seed: sq,
                        selected: sq == _selected,
                        armed: _chain.contains(sq),
                      ),
                    );
                  },
                ),
                for (final piece in _pieces)
                  _AnimatedPieceView(
                    key: ValueKey(piece.id),
                    piece: piece,
                    palette: piecePalette,
                    cellSize: cellSize,
                    flipped: flipped,
                    selected: piece.square == _selected,
                    dragging: piece.square == _dragOrigin,
                    moveDuration: _moveDuration,
                    fadeDuration: _captureFadeDuration,
                  ),
                if (_dragOrigin != null &&
                    _dragPosition != null &&
                    _dragPieceType != null)
                  Positioned(
                    left: _dragPosition!.dx - cellSize / 2,
                    top: _dragPosition!.dy - cellSize / 2,
                    width: cellSize,
                    height: cellSize,
                    child: IgnorePointer(
                      child: Center(
                        child: _CheckerPiece(
                          side: _dragPieceType!.startsWith('A') ? 'A' : 'B',
                          isKing: _dragPieceType!.endsWith('KING'),
                          glowing: true,
                          size: cellSize * 0.78,
                          palette: piecePalette,
                        ),
                      ),
                    ),
                  ),
              ]),
            );
          },
        ),
      ),
      if (_paused) Positioned.fill(child: _pauseOverlay()),
    ]);
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        height: 42,
        child: Row(children: [
          Icon(icon, size: 18, color: const Color(0xffc9b18c)),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(color: Color(0xfff0d8a8), fontSize: 13)),
        ]),
      );

  Widget _timerDial() {
    final danger = (_secondsLeft ?? 99) <= 10;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xff241708),
          border: Border.all(
              color: danger ? const Color(0xffe0704a) : const Color(0xff5c3a1c),
              width: 2.4),
          boxShadow: [
            if (danger)
              BoxShadow(
                  color: const Color(0xffe0704a).withValues(alpha: 0.4),
                  blurRadius: 10),
          ],
        ),
        child: Text(
          _secondsLeft != null ? '$_secondsLeft' : '—',
          style: TextStyle(
              color: danger ? const Color(0xffe0704a) : const Color(0xfff0d8a8),
              fontWeight: FontWeight.w800,
              fontSize: 16,
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ),
    ]);
  }

  Widget _statusBar(NeonColors n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: Color(0xff241708),
        border: Border(bottom: BorderSide(color: Color(0xff3a2410))),
      ),
      child: Row(children: [
        _sideChip('A', playerA),
        const Spacer(),
        // Clock and replay sit here rather than on a rail of their own below
        // the board. Voice is the single real control in the app bar.
        Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            _timerDial(),
            const SizedBox(width: 12),
            SizedBox(
              width: 44,
              height: 40,
              child: TextButton(
                key: const Key('draughts-var-tv'),
                onPressed: _var.lastCompleted == null ||
                        (!_amSpectator && _var.lastCompleted!.side == mySide)
                    ? null
                    : _openVar,
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: _VarTvIcon(
                  enabled: _var.lastCompleted != null &&
                      (_amSpectator || _var.lastCompleted!.side != mySide),
                ),
              ),
            ),
          ]),
        ]),
        const Spacer(),
        _sideChip('B', playerB),
      ]),
    );
  }

  /// Whose move it is, in letters you can read from across the table. It was
  /// a 9-point label squeezed between the two player chips; now it's a
  /// full-width banner: bright and solid on your turn, a quiet "thinking"
  /// strip while the other side moves.
  Widget _turnBanner() {
    final mustCapture = myTurn && _remainingRequired > 0;
    final String text;
    final Color fill;
    final Color ink;
    final IconData icon;
    final bool waiting;
    if (_amSpectator) {
      // Watching: say whose turn it is, by name.
      final who = label(_actorFor(turnSide));
      text = "${who.toUpperCase()}'S TURN";
      fill = const Color(0xff3a2410);
      ink = const Color(0xfff0d8a8);
      icon = Icons.visibility_rounded;
      waiting = false;
    } else if (mustCapture) {
      text = 'YOU MUST CAPTURE';
      fill = const Color(0xffe0584a);
      ink = Colors.white;
      icon = Icons.priority_high_rounded;
      waiting = false;
    } else if (myTurn) {
      text = 'YOUR TURN';
      fill = const Color(0xffffc233);
      ink = const Color(0xff241708);
      icon = Icons.touch_app_rounded;
      waiting = false;
    } else {
      text = 'OPPONENT IS THINKING';
      fill = const Color(0xff3a2410);
      ink = const Color(0xfff0d8a8);
      icon = Icons.hourglass_top_rounded;
      waiting = true;
    }
    return AnimatedContainer(
      key: const ValueKey('draughts-turn-banner'),
      duration: const Duration(milliseconds: 220),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: fill,
        boxShadow: myTurn && !_amSpectator
            ? [BoxShadow(color: fill.withValues(alpha: 0.55), blurRadius: 14)]
            : null,
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (waiting)
          SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: ink))
        else
          Icon(icon, color: ink, size: 24),
        const SizedBox(width: 10),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(text,
                key: const ValueKey('draughts-turn-text'),
                maxLines: 1,
                style: TextStyle(
                    color: ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2)),
          ),
        ),
        if (waiting) ...[
          const SizedBox(width: 2),
          Text('…',
              style: TextStyle(
                  color: ink, fontSize: 22, fontWeight: FontWeight.w900)),
        ],
      ]),
    );
  }

  /// Whose side it is, shown as their actual face rather than a blank
  /// counter — your own picture for you, initials for everyone else,
  /// including agents. The ring lights up on whoever is on the clock.
  Widget _sideChip(String side, String playerId) {
    final active = turnSide == side;
    final isMe = playerId.isNotEmpty && playerId == widget.selfId;
    final app = AppScope.of(context);
    return Column(children: [
      Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: active
              ? const Border.fromBorderSide(
                  BorderSide(color: Color(0xffe0a94a), width: 2))
              : Border.all(color: const Color(0xff1c130a), width: 1.4),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: const Color(0xffe0a94a).withValues(alpha: 0.45),
                      blurRadius: 10)
                ]
              : null,
        ),
        child: playerId.isEmpty
            ? const SizedBox(width: 34, height: 34)
            : ValueListenableBuilder<Set<String>>(
                valueListenable: widget.socket.onlinePlayers,
                builder: (_, online, __) => OnlineAvatar(
                  label(playerId),
                  size: 34,
                  voiceIdentity: playerId,
                  online: online.contains(playerId),
                  emoji: isMe ? app.avatarEmoji : null,
                  imagePath: isMe ? app.avatarImagePath : null,
                  imageUrl: widget.socket.memberAvatars[playerId] ?? (isMe ? app.user?.avatarUrl : null),
                ),
              ),
      ),
      const SizedBox(height: 4),
      Text(playerId.isEmpty ? '…' : label(playerId),
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color:
                  active ? const Color(0xfff0d8a8) : const Color(0xff9a8163))),
    ]);
  }

  /// Draughts and Goosi share one chat panel — see [TableChatPanel].
  Widget _chatPanel(NeonColors n) => TableChatPanel(
        lines: feed,
        controller: _chatController,
        onSend: _sendChat,
        spectatorCount: _spectatorCount,
        amSpectator: _amSpectator,
      );

  /// How the game finished, in the terms a player would describe it in:
  /// what they had left on the board, and what it paid.
  Widget _resultStats(bool won) {
    final mine = mySide == 'A' ? _piecesA : _piecesB;
    final theirs = mySide == 'A' ? _piecesB : _piecesA;
    final chips = <Widget>[];

    if (mine != null && theirs != null) {
      final margin = (mine - theirs).abs();
      chips.add(_statChip(
        Icons.circle_outlined,
        won
            ? '$mine ${mine == 1 ? 'piece' : 'pieces'} left'
            : '$theirs to $mine',
      ));
      if (margin > 0) {
        chips.add(_statChip(Icons.trending_up_rounded, 'by $margin'));
      }
    }
    if (_coinsAwarded != null) {
      chips.add(_statChip(Icons.monetization_on_rounded,
          '+$_coinsAwarded ${_coinsAwarded == 1 ? 'coin' : 'coins'}'));
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: chips);
  }

  Widget _statChip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: const Color(0xffe0a94a)),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Color(0xffe8d2ac),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _results(NeonColors n) {
    final won = winningSide == mySide;
    final accent =
        winningSide == 'A' ? const Color(0xffc9822f) : const Color(0xffe0a94a);
    return Stack(children: [
      // Only a win gets fireworks. Losing to a celebration would be a
      // strange thing to do to somebody.
      if (won) const Positioned.fill(child: Fireworks()),
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // The trophy lands a beat after the screen arrives, so the two
            // movements read as one sequence rather than competing.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 760),
              curve: Curves.elasticOut,
              builder: (_, t, child) =>
                  Transform.scale(scale: 0.5 + 0.5 * t, child: child),
              child: const Text('🏆', style: TextStyle(fontSize: 64)),
            ),
            const SizedBox(height: 10),
            Text(
                winningSide == 'draw'
                    ? 'Game drawn'
                    : '${label(_actorFor(winningSide ?? 'A'))} wins',
                style: Theme.of(context)
                    .textTheme
                    .displayLarge
                    ?.copyWith(fontSize: 26, color: accent)),
            const SizedBox(height: 6),
            Text(
                winningSide == 'draw'
                    ? 'This pairing will replay.'
                    : (won ? 'You won! 🎉' : 'Better luck next game.'),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: const Color(0xffc9b18c))),
            const SizedBox(height: 16),
            _resultStats(won),
            const SizedBox(height: 24),
            if (won)
              VictoryShareButton(
                  roomId: widget.socket.roomId, gameType: 'draughts'),
            NeonButton(
                widget.championshipId == null
                    ? 'Back to home'
                    : 'Back to championship', onPressed: () {
              if (widget.championshipId != null) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const MainShell()),
                    (r) => false);
              }
            }),
            const GuestSaveSessionCard(),
          ]),
        ),
      ),
    ]);
  }
}

/// The thick carved-wood surround the board sits in.
class _WoodFrame extends StatelessWidget {
  const _WoodFrame({required this.palette, required this.child});
  final BoardPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.frameTop, palette.frameBottom]),
        boxShadow: const [
          BoxShadow(
              color: Colors.black54, blurRadius: 20, offset: Offset(0, 10))
        ],
        border: Border.all(color: const Color(0xff1c1108), width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CustomPaint(
            painter: _WoodPainter(
                base: palette.frameTop, grain: Colors.black, seed: 7),
            child: child),
      ),
    );
  }
}

/// A single board square: solid worn-plank color with procedural grain, no
/// image asset needed. Only the selected piece and the square the player
/// actually tapped are highlighted; legal destinations remain unmarked.
class _PlankCell extends StatelessWidget {
  const _PlankCell(
      {required this.palette,
      required this.dark,
      this.seed = 0,
      this.selected = false,
      this.armed = false,
      this.inert = false});
  final BoardPalette palette;
  final bool dark;
  final int seed;
  final bool selected;
  final bool armed;
  final bool inert;

  @override
  Widget build(BuildContext context) {
    // Squares nobody can land on are the light squares: just the colour,
    // nothing to tap or highlight.
    if (inert) return ColoredBox(color: palette.lightSquare);
    final n = context.neon;
    // Clean tiles: each board's grain colour sits close to its square colour,
    // so the pattern stays faint and the two square colours stay easy to tell apart.
    final base = dark ? palette.darkSquare : palette.lightSquare;
    final grain = dark ? palette.darkGrain : palette.lightGrain;
    return CustomPaint(
      painter:
          _WoodPainter(base: base, grain: grain, seed: seed + 1, calm: true),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: selected ? n.gold.withValues(alpha: 0.36) : null,
          border: armed
              ? Border.all(color: n.gold, width: 3.2)
              : selected
                  ? Border.all(color: n.gold, width: 3.2)
                  : null,
          boxShadow: armed || selected
              ? [
                  BoxShadow(
                    color: n.gold.withValues(alpha: 0.7),
                    blurRadius: 11,
                    spreadRadius: -1,
                  )
                ]
              : null,
        ),
      ),
    );
  }
}

class _VarReplaySheet extends StatefulWidget {
  const _VarReplaySheet({
    required this.turn,
    required this.boardPalette,
    required this.piecePalette,
    required this.flipped,
    required this.playerName,
  });

  final DraughtsVarTurn turn;
  final BoardPalette boardPalette;
  final PiecePalette piecePalette;
  final bool flipped;
  final String playerName;

  @override
  State<_VarReplaySheet> createState() => _VarReplaySheetState();
}

class _VarReplaySheetState extends State<_VarReplaySheet> {
  static const _openingHold = Duration(milliseconds: 450);
  static const _restartHold = Duration(milliseconds: 240);

  final List<_Piece> _pieces = [];
  int _step = 0;
  int _playToken = 0;
  int _boardGeneration = 0;
  bool _playing = false;
  bool _paused = false;
  double _speed = 1;

  @override
  void initState() {
    super.initState();
    _reset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _play(leadIn: _openingHold);
    });
  }

  @override
  void dispose() {
    _playToken++;
    super.dispose();
  }

  void _reset() {
    _playToken++;
    _boardGeneration++;
    _pieces.clear();
    for (var square = 0; square < widget.turn.before.length; square++) {
      final type = widget.turn.before[square];
      if (type != null) _pieces.add(_Piece(square, square, type));
    }
    _step = 0;
    _playing = false;
    _paused = false;
  }

  Future<void> _play({
    bool restart = false,
    Duration leadIn = Duration.zero,
  }) async {
    if (_playing || restart || _step == widget.turn.steps.length) {
      setState(_reset);
    }
    final token = ++_playToken;
    setState(() {
      _playing = true;
      _paused = false;
    });

    // Let Flutter paint the recorded starting board before changing the
    // first piece. Without this frame, reset + move can collapse into one
    // build and AnimatedPositioned has no old position to animate from.
    await WidgetsBinding.instance.endOfFrame;
    if (leadIn > Duration.zero) {
      await Future<void>.delayed(leadIn);
    }
    if (!mounted || token != _playToken) return;

    while (mounted && token == _playToken && _step < widget.turn.steps.length) {
      if (_paused) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        continue;
      }
      final move = widget.turn.steps[_step];
      final piece = _pieces.where((p) => p.square == move.from).firstOrNull;
      if (piece == null) break;
      setState(() => piece.square = move.to);
      await Future<void>.delayed(
          Duration(milliseconds: (560 / _speed).round()));
      if (!mounted || token != _playToken) return;
      setState(() {
        if (move.captured != null) {
          _pieces.removeWhere((p) => p.square == move.captured);
        }
        if (move.promoted) piece.type = '${widget.turn.side}_KING';
        _step++;
      });
      await Future<void>.delayed(
          Duration(milliseconds: (180 / _speed).round()));
    }
    if (mounted && token == _playToken) setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        key: const Key('draughts-var-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.76,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: Column(children: [
            Row(children: [
              const Text('VAR REPLAY',
                  style: TextStyle(
                      color: Color(0xffe0a94a),
                      fontSize: 15,
                      fontWeight: FontWeight.w900)),
              const Spacer(),
              IconButton(
                tooltip: 'Close replay',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  '${widget.playerName} · step $_step of ${widget.turn.steps.length}',
                  style:
                      const TextStyle(color: Color(0xffc9b18c), fontSize: 12)),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: LayoutBuilder(builder: (context, limits) {
                final side = math.min(limits.maxWidth, limits.maxHeight);
                return Center(
                  child: SizedBox.square(
                    dimension: side,
                    child: _WoodFrame(
                      palette: widget.boardPalette,
                      child: LayoutBuilder(builder: (context, boardLimits) {
                        final cellSize = boardLimits.maxWidth / 10;
                        return Stack(children: [
                          GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 10),
                            itemCount: 100,
                            itemBuilder: (context, i) {
                              final displayRow = i ~/ 10, col = i % 10;
                              final row =
                                  widget.flipped ? displayRow : 9 - displayRow;
                              if (!isPlayable(row, col)) {
                                return _PlankCell(
                                    palette: widget.boardPalette,
                                    dark: false,
                                    inert: true);
                              }
                              final square = squareOf(row, col);
                              return _PlankCell(
                                palette: widget.boardPalette,
                                dark: true, // same checkerboard as the live board
                                seed: square,
                              );
                            },
                          ),
                          for (final piece in _pieces)
                            KeyedSubtree(
                              key: ValueKey(
                                  'var-run-$_boardGeneration-${piece.id}'),
                              child: _AnimatedPieceView(
                                key: ValueKey('var-${piece.id}'),
                                piece: piece,
                                palette: widget.piecePalette,
                                cellSize: cellSize,
                                flipped: widget.flipped,
                                selected: false,
                                dragging: false,
                                moveDuration: Duration(
                                    milliseconds: (420 / _speed).round()),
                                fadeDuration: const Duration(milliseconds: 200),
                              ),
                            ),
                        ]);
                      }),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                tooltip: 'Replay from start',
                onPressed: () => _play(
                  restart: true,
                  leadIn: _restartHold,
                ),
                icon: const Icon(Icons.replay_rounded),
              ),
              IconButton(
                tooltip: _paused ? 'Resume replay' : 'Pause replay',
                onPressed: !_playing
                    ? _play
                    : () => setState(() => _paused = !_paused),
                icon: Icon(!_playing || _paused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded),
              ),
              const SizedBox(width: 12),
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 0.5, label: Text('0.5x')),
                  ButtonSegment(value: 1, label: Text('1x')),
                  ButtonSegment(value: 2, label: Text('2x')),
                ],
                selected: {_speed},
                onSelectionChanged: (speed) =>
                    setState(() => _speed = speed.first),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _VarTvIcon extends StatelessWidget {
  const _VarTvIcon({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final casing = enabled ? const Color(0xffe0a94a) : const Color(0xff6f604e);
    return SizedBox(
      width: 36,
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.tv_rounded, size: 34, color: casing),
          Positioned(
            top: 9,
            left: 7,
            right: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xff241708),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                'VAR',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: enabled
                      ? const Color(0xffffe6ae)
                      : const Color(0xff9a8163),
                  fontSize: 7,
                  height: 1.25,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Positions one `_Piece` over the board and implicitly animates it to a new
/// square whenever `piece.square` changes — this is what makes a move read
/// as a slide rather than a jump-cut. Keyed by the piece's stable id so
/// Flutter's Stack reconciliation matches old→new position across rebuilds.
class _AnimatedPieceView extends StatelessWidget {
  const _AnimatedPieceView({
    super.key,
    required this.piece,
    required this.palette,
    required this.cellSize,
    required this.flipped,
    required this.selected,
    required this.dragging,
    required this.moveDuration,
    required this.fadeDuration,
  });

  final _Piece piece;
  final PiecePalette palette;
  final double cellSize;
  final bool flipped;
  final bool selected;
  final bool dragging;
  final Duration moveDuration;
  final Duration fadeDuration;

  @override
  Widget build(BuildContext context) {
    final row = rowOf(piece.square), col = colOf(piece.square);
    final displayRow = flipped ? row : 9 - row;
    final displayCol = col;
    final side = piece.type.startsWith('A') ? 'A' : 'B';
    final isKing = piece.type.endsWith('KING');

    return AnimatedPositioned(
      duration: moveDuration,
      curve: Curves.easeInOutCubic,
      left: displayCol * cellSize,
      top: displayRow * cellSize,
      width: cellSize,
      height: cellSize,
      child: IgnorePointer(
        // taps always go through to the plank cell underneath
        child: Center(
          child: AnimatedScale(
            duration: fadeDuration,
            scale: selected ? 1.15 : 1.0,
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              duration: dragging ? Duration.zero : fadeDuration,
              opacity: dragging ? 0 : 1,
              child: _CheckerPiece(
                  side: side,
                  isKing: isKing,
                  glowing: selected,
                  size: cellSize * 0.78,
                  palette: palette),
            ),
          ),
        ),
      ),
    );
  }
}

/// A captured checker flies over the wood frame, then stays scattered in
/// the tray. Reconnected games use the same widget at its resting position.
class _CapturedPieceFlight extends StatelessWidget {
  const _CapturedPieceFlight({
    super.key,
    required this.captured,
    required this.palette,
    required this.size,
    required this.start,
    required this.end,
    required this.arcHeight,
  });

  final _CapturedPiece captured;
  final PiecePalette palette;
  final double size;
  final Offset start;
  final Offset end;
  final double arcHeight;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: captured.animate ? 0 : 1, end: 1),
            duration: captured.animate
                ? const Duration(milliseconds: 720)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            builder: (context, progress, child) {
              final position = Offset.lerp(start, end, progress)!;
              final lift = math.sin(math.pi * progress) * arcHeight;
              return Transform.translate(
                offset: Offset(position.dx, position.dy - lift),
                child: Transform.rotate(
                  angle: (captured.id.isEven ? 1 : -1) * progress * 0.85,
                  child: Transform.scale(
                    scale: 1 - progress * 0.38,
                    child: child,
                  ),
                ),
              );
            },
            child: _CheckerPiece(
              side: captured.side,
              isKing: captured.type.endsWith('KING'),
              glowing: false,
              size: size,
              palette: palette,
            ),
          ),
        ),
      ),
    );
  }
}

/// A solid, chunky checker — a domed disc with a carved rim, not a flat-color
/// circle. Always gets a thin pale outer halo regardless of which
/// `PiecePalette` is active, specifically so a dark piece color can never
/// blend into a dark board square again (the original bug report).
class _CheckerPiece extends StatelessWidget {
  const _CheckerPiece(
      {required this.side,
      required this.isKing,
      required this.glowing,
      required this.size,
      required this.palette});
  final String side;
  final bool isKing;
  final bool glowing;
  final double size;
  final PiecePalette palette;

  @override
  Widget build(BuildContext context) {
    final isA = side == 'A';
    final top = isA ? palette.aTop : palette.bTop;
    final mid = isA ? palette.aMid : palette.bMid;
    final rim = isA ? palette.aRim : palette.bRim;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: size * 0.2,
              offset: Offset(0, size * 0.09)),
          if (glowing)
            BoxShadow(
                color: const Color(0xffe0a94a).withValues(alpha: 0.9),
                blurRadius: size * 0.42,
                spreadRadius: size * 0.08),
        ],
        // A near-white halo on every piece, independent of its own palette —
        // this is what keeps a piece separated from the board underneath no
        // matter how dark either one is.
        border: Border.all(
            color: glowing
                ? const Color(0xffffd879)
                : Colors.white.withValues(alpha: 0.85),
            width: size * (glowing ? 0.075 : 0.045)),
      ),
      padding: EdgeInsets.all(size * 0.045),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: rim, width: size * 0.07),
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.4),
            radius: 0.95,
            colors: [top, mid],
            stops: const [0.0, 1.0],
          ),
        ),
        alignment: Alignment.center,
        child: Container(
          width: size * 0.6,
          height: size * 0.6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: rim.withValues(alpha: 0.65), width: size * 0.035),
          ),
          alignment: Alignment.center,
          child: isKing
              ? Icon(Icons.star_rounded,
                  size: size * 0.4,
                  color: rim,
                  shadows: [
                      Shadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 2)
                    ])
              : null,
        ),
      ),
    );
  }
}

/// Procedural wood-grain fill — layered streaky lines over a base color,
/// deterministic per `seed` so it doesn't shimmer on rebuild. Cheap stand-in
/// for a real wood texture with no image asset needed.
class _WoodPainter extends CustomPainter {
  const _WoodPainter(
      {required this.base,
      required this.grain,
      required this.seed,
      this.calm = false});
  final Color base;
  final Color grain;
  final int seed;

  /// A calmer, sparser pass for the board squares themselves — a handful of
  /// faint, mostly-straight streaks so the surface reads as one solid slab
  /// rather than a busy pattern; the frame around it keeps the fuller grain.
  final bool calm;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    final rnd = math.Random(seed);
    final lines = calm ? 5 : 14;
    for (var i = 0; i < lines; i++) {
      final y = rnd.nextDouble() * size.height;
      final thickness = 0.6 + rnd.nextDouble() * (calm ? 1.2 : 2.0);
      final alpha =
          (calm ? 0.03 : 0.05) + rnd.nextDouble() * (calm ? 0.05 : 0.12);
      final path = Path()..moveTo(0, y);
      const segments = 5;
      for (var s = 1; s <= segments; s++) {
        final x = size.width * s / segments;
        final wobble =
            (rnd.nextDouble() - 0.5) * size.height * (calm ? 0.03 : 0.08);
        path.lineTo(x, (y + wobble).clamp(0, size.height));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = grain.withValues(alpha: alpha)
          ..strokeWidth = thickness
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: calm ? 0.14 : 0.22)
        ], radius: 0.95)
            .createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _WoodPainter oldDelegate) =>
      oldDelegate.base != base ||
      oldDelegate.grain != grain ||
      oldDelegate.seed != seed ||
      oldDelegate.calm != calm;
}

/// Board wood tone + piece color pickers — a per-device cosmetic preference
/// (`DraughtsThemeController`, backed by SharedPreferences), not something
/// the server or the other player needs to know about.
class _BoardThemeSheet extends StatelessWidget {
  const _BoardThemeSheet({required this.theme});
  final DraughtsThemeController theme;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('BOARD WOOD',
                  style: TextStyle(
                      color: Color(0xffe0a94a),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      fontSize: 12)),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final p in boardPalettes) _boardSwatch(context, p),
              ]),
              const SizedBox(height: 24),
              const Text('PIECE COLORS',
                  style: TextStyle(
                      color: Color(0xffe0a94a),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      fontSize: 12)),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final p in piecePalettes) _pieceSwatch(context, p),
              ]),
            ]),
      ),
    );
  }

  Widget _boardSwatch(BuildContext context, BoardPalette p) {
    final selected = theme.board.id == p.id;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => theme.setBoard(p),
      child: Container(
        width: 84,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? const Color(0xffe0a94a) : Colors.white24,
              width: selected ? 2 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 40,
              child: Row(children: [
                Expanded(child: ColoredBox(color: p.darkSquare)),
                Expanded(child: ColoredBox(color: p.lightSquare)),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(p.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _pieceSwatch(BuildContext context, PiecePalette p) {
    final selected = theme.piece.id == p.id;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => theme.setPiece(p),
      child: Container(
        width: 84,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? const Color(0xffe0a94a) : Colors.white24,
              width: selected ? 2 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 40,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _dot(p.aTop, p.aMid),
              const SizedBox(width: 6),
              _dot(p.bTop, p.bMid),
            ]),
          ),
          const SizedBox(height: 6),
          Text(p.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _dot(Color top, Color mid) => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 1.6),
          gradient: RadialGradient(colors: [top, mid]),
        ),
      );
}
