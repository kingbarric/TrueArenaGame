import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';
import '../../core/app_state.dart';
import '../../core/api_client.dart';
import '../../core/game_music.dart';
import '../../core/game_sfx.dart';
import '../../core/game_socket.dart';
import '../../widgets/how_to_play_dialog.dart';
import '../../widgets/neon.dart';
import '../../widgets/table_chat.dart';
import '../shell/main_shell.dart';
import '../status/victory_status.dart';
import 'whot_lobby_screen.dart';
import 'whot_card.dart';

class WhotGameScreen extends StatefulWidget {
  const WhotGameScreen(
      {super.key,
      required this.socket,
      required this.selfId,
      required this.nicknames,
      required this.roomId,
      this.roomCode,
      this.avatars = const {},
      this.spectating = false});
  final bool spectating;
  final GameSocket socket;
  final String selfId, roomId;
  final String? roomCode;
  final Map<String, String> nicknames;
  final Map<String, String> avatars;
  @override
  State<WhotGameScreen> createState() => _WhotGameScreenState();
}

class _WhotGameScreenState extends State<WhotGameScreen> {
  late GameSocket _socket;
  StreamSubscription? _sub;
  Timer? _ticker,
      _ackTimer,
      _flightTimer,
      _reshuffleTimer,
      _signalTimer,
      _copyTimer,
      _warningTimer,
      _resultTimer;
  Map<String, dynamic> _state = {};
  List<_CardFlightSpec> _cardFlights = const [];
  List<_CardFlightSpec> _reshuffleFlights = const [];
  Map<String, dynamic>? _visibleSignal;
  final _dealSoundTimers = <Timer>[];
  int _flightSerial = 0;
  int _reshuffleSerial = 0;
  int? _selected;
  int _seconds = 0, _actionSequence = 0;
  bool _pending = false, _disconnected = false;
  bool _leaving = false;
  bool _roomCopied = false;
  bool _resultStarted = false, _finalSplash = false, _showSummary = false;
  String? _lastCardWarning, _lastPlayedCard;
  bool _musicOn = GameMusic.enabled;
  bool _sfxOn = GameSfx.enabled;
  lk.Room? _voiceRoom;
  bool _voiceJoining = false, _micMuted = false;
  int _voiceParticipants = 0;
  String? _error;
  final _chatController = TextEditingController();
  final _chat = <TableChatLine>[];
  bool get _chatMuted => widget.spectating && _state['spectatorsMuted'] == true;
  String _activity = 'Welcome to the table';
  static const _cream = Color(0xffffebc6), _gold = Color(0xffe9b963);
  static const _tellSymbols = [
    '🪐',
    '🌌',
    '☄️',
    '🌠',
    '🌑',
    '🌒',
    '🌓',
    '🌔',
    '🌕',
    '🌘',
    '🌙',
    '🌚',
    '🌝',
    '✨',
    '🔮',
    '🧿',
    '🗝️',
    '🪬',
    '🕯️',
    '🪞',
    '🪄',
    '🕳️',
    '🛸',
    '👁️',
    '🗿',
    '🧬',
    '🌀',
    '⚗️',
    '💠',
    '🧩',
  ];
  List<String> get _hand => widget.spectating
      ? const []
      : (_state['yourHand'] as List? ?? []).cast<String>();
  List<String> get _players =>
      (_state['players'] as List? ?? []).cast<String>();
  Map get _sizes => _state['handSizes'] as Map? ?? {};
  bool get _deal => _state['phase'] == 'Deal';
  bool get _tell => _state['mode'] == 'tell';
  bool get _choosingSignals => _tell && _state['phase'] == 'Signals';
  bool get _activeTellPlayer =>
      !_tell ||
      !((_state['qualifiedTeams'] as List? ?? const [])
              .contains(_state['yourTeam']) ||
          (_state['eliminatedTeams'] as List? ?? const [])
              .contains(_state['yourTeam']));
  bool get _finished => _state['phase'] == 'Results';
  bool get _won =>
      !widget.spectating &&
      (_tell
          ? _state['winnerTeam'] == _state['yourTeam']
          : _state['winner'] == widget.selfId);
  String get _winnerLabel => _tell && _state['winnerTeam'] != null
      ? 'Team ${(_state['winnerTeam'] as num).toInt() + 1}'
      : _name(_state['winner']);
  bool get _winnerClearedHand {
    final winner = _state['winner'];
    return winner != null && (_sizes[winner] as num?)?.toInt() == 0;
  }

  bool get _paused => _state['paused'] == true;
  bool get _myTurn =>
      !widget.spectating &&
      _activeTellPlayer &&
      _state['turnPlayer'] == widget.selfId &&
      (_state['phase'] == 'Turn' || _state['phase'] == 'Waiting');
  bool get _canAct =>
      !widget.spectating && !_pending && !_disconnected && !_paused;
  String _name(String? id) => !widget.spectating && id == widget.selfId
      ? 'You'
      : widget.nicknames[id] ??
          (_players.contains(id)
              ? 'Player ${_players.indexOf(id!) + 1}'
              : 'Spectator');

  @override
  void initState() {
    super.initState();
    _socket = widget.socket;
    _listen();
    GameMusic.start(GameMusic.moodFor('whot'));
    GameSfx.warmUp();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_paused && !_finished && _seconds > 0) {
        setState(() => _seconds--);
      }
    });
  }

  void _listen() {
    _sub = _socket.envelopes.listen(_receive, onDone: () {
      if (mounted) {
        setState(() {
          _disconnected = true;
          _pending = false;
        });
      }
    });
    _socket.send('HELLO', {'lastSeq': _socket.lastSeq});
  }

  void _receive(Map<String, dynamic> env) {
    if (!mounted) return;
    final p = (env['payload'] as Map? ?? {}).cast<String, dynamic>();
    if (env['type'] == 'CONNECTION') {
      setState(() {
        _disconnected = p['connected'] != true;
        if (_disconnected) _pending = false;
      });
      return;
    }
    if (env['type'] == 'SNAPSHOT' && p['lobby'] == true && widget.spectating) {
      setState(() => _state = {'phase': 'Lobby', ...p});
    } else if (env['type'] == 'SNAPSHOT' && p['lobby'] != true) {
      _ackTimer?.cancel();
      final previousPhase = _state['phase'];
      final previousTurn = _state['turnPlayer']?.toString();
      final previousTop = _state['topCard']?.toString() ?? '';
      final nextTop = p['topCard']?.toString() ?? '';
      final previousHand = (_state['yourHand'] as List? ?? const [])
          .map((card) => card.toString())
          .toList();
      final nextHand = (p['yourHand'] as List? ?? const [])
          .map((card) => card.toString())
          .toList();
      final previousSizes = (_state['handSizes'] as Map? ?? const {});
      final nextSizes = (p['handSizes'] as Map? ?? const {});
      final wasPlaying = previousPhase == 'Turn' || previousPhase == 'Waiting';
      final isDealing = previousPhase == 'Deal';
      final drawDeltas = <String, int>{};
      if (wasPlaying || isDealing) {
        for (final entry in nextSizes.entries) {
          final before = previousSizes[entry.key] as int? ?? 0;
          final after = entry.value as int? ?? before;
          if (after > before) drawDeltas[entry.key.toString()] = after - before;
        }
      }
      final animateHand = !widget.spectating &&
          (drawDeltas[widget.selfId] ?? 0) > 0 &&
          nextHand.length > previousHand.length;
      final animateOpponentPlay = wasPlaying &&
          (p['phase'] == 'Turn' || p['phase'] == 'Waiting') &&
          previousTop.isNotEmpty &&
          nextTop.isNotEmpty &&
          previousTop != nextTop &&
          previousTurn != null &&
          previousTurn != widget.selfId;
      final nextState = Map<String, dynamic>.from(p);
      final flights = <_CardFlightSpec>[];
      var stagger = 0;
      final maxRounds = drawDeltas.values.fold<int>(0, math.max);
      // Deal in table order, one card per seat each round. Limit very large
      // tables to a few visible rounds so the animation stays under 7 seconds.
      for (var round = 0; round < maxRounds && flights.length < 40; round++) {
        for (final draw in drawDeltas.entries) {
          if (draw.value <= round || flights.length >= 40) continue;
          final destination = draw.key == widget.selfId && !widget.spectating
              ? const Offset(.5, .82)
              : _seatOffsetFor(draw.key);
          flights.add(_CardFlightSpec(
              id: ++_flightSerial,
              code: null,
              from: const Offset(.34, .5),
              to: destination,
              delayMs: stagger * (isDealing ? 155 : 170)));
          stagger++;
        }
      }
      if (animateHand) nextState['yourHand'] = previousHand;
      if (animateOpponentPlay) {
        nextState['topCard'] = previousTop;
        flights.add(_CardFlightSpec(
            id: ++_flightSerial,
            code: nextTop,
            from: _seatOffsetFor(previousTurn),
            to: const Offset(.66, .5)));
      }
      if (drawDeltas.isNotEmpty && isDealing) {
        _activity = 'Dealing cards around the table';
      } else if (drawDeltas.isNotEmpty) {
        _activity = drawDeltas.entries
            .map((draw) =>
                '${_name(draw.key)} went to market · drew ${draw.value} ${draw.value == 1 ? 'card' : 'cards'}')
            .join('  ·  ');
      }
      if (flights.isNotEmpty) _flightTimer?.cancel();
      setState(() {
        _state = nextState;
        _seconds = p['secondsLeft'] as int? ?? 0;
        _pending = false;
        _disconnected = false;
        _selected = null;
        if (flights.isNotEmpty) _cardFlights = flights;
      });
      final snapshotSignal = p['signal'];
      if (snapshotSignal is Map) {
        _showSignal(snapshotSignal.cast<String, dynamic>());
      } else if (_visibleSignal != null) {
        _signalTimer?.cancel();
        setState(() => _visibleSignal = null);
      }
      if (p['phase'] != 'Results') {
        for (final entry in nextSizes.entries) {
          final before = previousSizes[entry.key] as int?;
          if (before != null && before > 1 && entry.value == 1) {
            _warnLastCard(entry.key.toString());
            break;
          }
        }
      } else {
        _beginResult();
      }
      if (flights.isNotEmpty) {
        if (isDealing) {
          for (final timer in _dealSoundTimers) {
            timer.cancel();
          }
          _dealSoundTimers.clear();
          for (var i = 0; i < flights.length; i++) {
            final flight = flights[i];
            _dealSoundTimers
                .add(Timer(Duration(milliseconds: flight.delayMs + 420), () {
              if (mounted) GameSfx.seed(i);
            }));
          }
        }
        final revealToken = _flightSerial;
        final flightTime = flights.fold<int>(
            850, (longest, flight) => math.max(longest, 850 + flight.delayMs));
        _flightTimer = Timer(Duration(milliseconds: flightTime), () {
          if (!mounted || revealToken != _flightSerial) return;
          setState(() {
            if (animateHand) _state['yourHand'] = nextHand;
            if (animateOpponentPlay) _state['topCard'] = nextTop;
            _cardFlights = const [];
          });
        });
      }
    } else if (env['type'] == 'ERROR') {
      _ackTimer?.cancel();
      _flightTimer?.cancel();
      setState(() {
        _pending = false;
        _cardFlights = const [];
        _error = p['message']?.toString() ?? 'Action refused';
        if (p['code'] == 'SPECTATORS_MUTED') _state['spectatorsMuted'] = true;
      });
    } else if (env['type'] == 'EVENT') {
      final d = (p['data'] as Map? ?? {}).cast<String, dynamic>();
      setState(() {
        switch (p['type']) {
          case 'CARD_PLAYED':
            GameSfx.cardPlay();
            _lastPlayedCard = d['card']?.toString();
            _activity =
                '${_name(d['by'])} played ${d['card'].toString().replaceAll('-', ' ')}';
          case 'CARD_DRAWN':
            GameSfx.cardDraw();
            final count = d['count'] as int? ?? 1;
            _activity =
                '${_name(d['by'])} went to market · drew $count ${count == 1 ? 'card' : 'cards'}';
          case 'GENERAL_MARKET':
            GameSfx.cardDraw();
            _activity = 'General market · everyone else draws one';
          case 'TURN_TIMED_OUT':
            _activity =
                '${_name(d['player'])} ran out of time and drew ${d['drew']}';
          case 'TURN_PAUSED':
            _activity = '${_name(d['player'])} ran out of time · table paused';
          case 'DECK_SHUFFLED':
            GameSfx.scoop();
            _activity = 'The dealer shuffled the deck';
          case 'MARKET_RESHUFFLED':
            GameSfx.scoop();
            _activity = 'Discard reshuffled into the market';
            _reshuffleFlights = [
              for (var i = 0; i < 3; i++)
                _CardFlightSpec(
                    id: ++_flightSerial,
                    code: null,
                    from: const Offset(.66, .5),
                    to: const Offset(.34, .5),
                    delayMs: i * 110),
            ];
          case 'SIGNAL_DISPLAYED':
            _activity = '${_name(d['by'])} sent a signal';
          case 'SIGNAL_CONFIRMED':
            _activity =
                'Team ${((d['team'] as num?)?.toInt() ?? 0) + 1} is choosing a signal';
          case 'SIGNALS_READY':
            _activity = 'Signals locked · deal the cards';
          case 'BUZZ_RESOLVED':
            _activity = d['correct'] == true
                ? '${_name(d['by'])} buzzed correctly!'
                : '${_name(d['by'])} buzzed incorrectly';
            _visibleSignal = null;
            _signalTimer?.cancel();
          case 'TEAM_QUALIFIED':
            _activity =
                'Team ${((d['team'] as num?)?.toInt() ?? 0) + 1} qualified';
          case 'TEAM_ELIMINATED':
            _activity =
                'Team ${((d['team'] as num?)?.toInt() ?? 0) + 1} eliminated';
          case 'FINAL_STARTED':
            _activity = 'Final round · choose a new secret signal';
            _visibleSignal = null;
            _signalTimer?.cancel();
          case 'CARDS_DEALT':
            _activity = 'Cards dealt around the table';
          case 'PLAY_BEGAN':
            GameSfx.move();
          case 'GAME_PAUSED':
            _state['paused'] = true;
          case 'GAME_RESUMED':
            _state['paused'] = false;
            _seconds = d['secondsLeft'] as int? ?? _seconds;
          case 'SPECTATOR_COUNT':
            _state['spectatorCount'] = d['count'];
          case 'SPECTATORS_MUTED':
            _state['spectatorsMuted'] = true;
          case 'SPECTATORS_UNMUTED':
            _state['spectatorsMuted'] = false;
          case 'CHAT_MESSAGE':
            _chat.insert(
                0,
                TableChatLine(
                    who: _name(d['from']),
                    text: d['text']?.toString() ?? '',
                    isSpectator: d['channel'] == 'spectate',
                    isAgent: d['channel'] == 'agent'));
            if (_chat.length > 100) _chat.removeLast();
          case 'GAME_OVER':
            _state['winner'] = d['winner'];
            if (d['winnerTeam'] != null) _state['winnerTeam'] = d['winnerTeam'];
            _state['phase'] = 'Results';
            if (d['handSizes'] is Map) _state['handSizes'] = d['handSizes'];
        }
      });
      if (p['type'] == 'SIGNAL_DISPLAYED') _showSignal(d);
      if (p['type'] == 'MARKET_RESHUFFLED') {
        _reshuffleTimer?.cancel();
        final serial = ++_reshuffleSerial;
        _reshuffleTimer = Timer(const Duration(milliseconds: 1200), () {
          if (mounted && serial == _reshuffleSerial) {
            setState(() => _reshuffleFlights = const []);
          }
        });
      }
      if (p['type'] == 'GAME_OVER') _beginResult();
    }
  }

  void _warnLastCard(String player) {
    _warningTimer?.cancel();
    setState(() => _lastCardWarning = player);
    _warningTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _lastCardWarning = null);
    });
  }

  void _showSignal(Map<String, dynamic> signal) {
    final id = (signal['id'] as num?)?.toInt();
    final sentAt = (signal['sentAtMs'] as num?)?.toInt();
    if (id == null || sentAt == null || _visibleSignal?['id'] == id) return;
    final remaining = 3000 - DateTime.now().millisecondsSinceEpoch + sentAt;
    if (remaining <= 0) return;
    _signalTimer?.cancel();
    setState(() => _visibleSignal = signal);
    _signalTimer = Timer(Duration(milliseconds: remaining), () {
      if (mounted && _visibleSignal?['id'] == id) {
        setState(() => _visibleSignal = null);
      }
    });
  }

  void _beginResult() {
    if (_resultStarted || !mounted) return;
    _resultStarted = true;
    _warningTimer?.cancel();
    _flightTimer?.cancel();
    _reshuffleTimer?.cancel();
    _signalTimer?.cancel();
    _cardFlights = const [];
    _reshuffleFlights = const [];
    if (_winnerClearedHand) GameSfx.capture();
    if (!widget.spectating) {
      if (_winnerClearedHand) unawaited(HapticFeedback.heavyImpact());
      GameMusic.playOutcome(won: _won);
    }
    setState(() {
      _lastCardWarning = null;
      _finalSplash = _winnerClearedHand;
    });
    _resultTimer = Timer(
        Duration(milliseconds: _winnerClearedHand ? 1250 : 250), () async {
      if (!mounted) return;
      setState(() => _finalSplash = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('whot-game-over-dialog'),
          backgroundColor: const Color(0xff21112a),
          title: const Text('GAME OVER',
              style: TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
          content: Text(
            widget.spectating
                ? '$_winnerLabel wins the game.'
                : _won
                    ? _winnerClearedHand
                        ? 'Victory! You played your last card.'
                        : 'Victory! You won the game.'
                    : '$_winnerLabel wins. You have ${_sizes[widget.selfId] ?? _hand.length} cards left.',
            style: const TextStyle(color: _cream),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('View summary'),
            ),
          ],
        ),
      );
      if (mounted) setState(() => _showSummary = true);
    });
  }

  void _sendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty || _disconnected || _chatMuted) return;
    _socket.send('CHAT_SEND',
        {'channel': widget.spectating ? 'spectate' : 'table', 'text': text});
    _chatController.clear();
  }

  void _action(String action, [Map<String, dynamic> data = const {}]) {
    if (!_canAct) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    _socket.send('PLAYER_ACTION', {
      'action': action,
      'actionId':
          '${widget.selfId}-${DateTime.now().microsecondsSinceEpoch}-${_actionSequence++}',
      'data': data
    });
    _ackTimer?.cancel();
    _ackTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() {
          _disconnected = true;
          _pending = false;
          _error = 'The table did not respond. Reconnect to sync your hand.';
        });
      }
    });
  }

  void _drawFromMarket() {
    if (!_myTurn || !_canAct) return;
    _flightTimer?.cancel();
    final count = math.max(1, _state['pendingPick'] as int? ?? 0);
    final flights = [
      for (var i = 0; i < count; i++)
        _CardFlightSpec(
            id: ++_flightSerial,
            code: null,
            from: const Offset(.34, .5),
            to: const Offset(.5, .82),
            delayMs: i * 170)
    ];
    final token = _flightSerial;
    setState(() => _cardFlights = flights);
    _flightTimer = Timer(Duration(milliseconds: 850 + (count - 1) * 170), () {
      if (mounted && token == _flightSerial) {
        setState(() => _cardFlights = const []);
      }
    });
    _action('DRAW');
  }

  Future<void> _play() async {
    if (_selected == null || !_myTurn || !_canAct) return;
    final card = _hand[_selected!];
    String? shape;
    if (card.startsWith('whot-')) {
      shape = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: .78),
          builder: (context) => SafeArea(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
                  decoration: BoxDecoration(
                    color: const Color(0xff21112a),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(26)),
                    border:
                        Border.all(color: const Color(0xffffc45b), width: 2),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0xaa000000),
                          blurRadius: 26,
                          offset: Offset(0, -6))
                    ],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('NAME YOUR SHAPE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .8)),
                    const SizedBox(height: 4),
                    const Text('Choose the shape the next player must match',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Color(0xffffd98a), fontSize: 12)),
                    const SizedBox(height: 16),
                    Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final s
                              in whotShapes.keys.where((s) => s != 'whot'))
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xfffff1d4),
                                foregroundColor: const Color(0xff7d2339),
                                minimumSize: const Size(132, 48),
                                side: const BorderSide(
                                    color: Color(0xffffc45b), width: 2),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(13)),
                              ),
                              onPressed: () => Navigator.pop(context, s),
                              child: Text('${whotShapes[s]}  $s',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900)),
                            )
                        ]),
                  ]),
                ),
              ));
      if (!mounted || shape == null) return;
    }
    if (!_myTurn ||
        !_canAct ||
        !_hand.contains(card) ||
        !whotCanPlay(card, _state)) {
      return;
    }
    _action('PLAY', {'card': card, if (shape != null) 'shape': shape});
  }

  void _reconnect() {
    _sub?.cancel();
    _socket.close();
    _ackTimer?.cancel();
    setState(() {
      _pending = false;
      _error = null;
    });
    _socket = GameSocket.connect(AppScope.of(context).api, widget.roomId,
        spectate: widget.spectating);
    _listen();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _sub?.cancel();
    _ticker?.cancel();
    _ackTimer?.cancel();
    _flightTimer?.cancel();
    _reshuffleTimer?.cancel();
    _signalTimer?.cancel();
    _copyTimer?.cancel();
    _warningTimer?.cancel();
    _resultTimer?.cancel();
    for (final timer in _dealSoundTimers) {
      timer.cancel();
    }
    GameMusic.stop();
    final voiceRoom = _voiceRoom;
    if (voiceRoom != null) {
      voiceRoom.removeListener(_onVoiceChanged);
      voiceRoom.disconnect();
      voiceRoom.dispose();
    }
    _socket.close();
    super.dispose();
  }

  String get _displayRoomCode {
    final code = widget.roomCode?.trim();
    return (code == null || code.isEmpty ? widget.roomId : code).toUpperCase();
  }

  void _copyRoomCode() {
    unawaited(Clipboard.setData(ClipboardData(text: _displayRoomCode))
        .catchError((_) {}));
    if (!mounted) return;
    _copyTimer?.cancel();
    setState(() => _roomCopied = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 1500), content: Text('Copied')));
    _copyTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _roomCopied = false);
    });
  }

  Future<void> _toggleMusic() async {
    final next = !_musicOn;
    setState(() => _musicOn = next);
    await GameMusic.setEnabled(next);
  }

  Future<void> _toggleSfx() async {
    final next = !_sfxOn;
    setState(() => _sfxOn = next);
    await GameSfx.setEnabled(next);
    if (next) GameSfx.select();
  }

  Future<void> _toggleAudio() async {
    final next = !(_musicOn || _sfxOn);
    setState(() {
      _musicOn = next;
      _sfxOn = next;
    });
    await Future.wait([
      GameMusic.setEnabled(next),
      GameSfx.setEnabled(next),
    ]);
  }

  void _onVoiceChanged() {
    if (!mounted) return;
    setState(() {
      _voiceParticipants = (_voiceRoom?.remoteParticipants.length ?? 0) + 1;
      _micMuted =
          !(_voiceRoom?.localParticipant?.isMicrophoneEnabled() ?? false);
    });
  }

  Future<void> _toggleVoice() async {
    final room = _voiceRoom;
    if (room != null) {
      try {
        await room.localParticipant?.setMicrophoneEnabled(_micMuted);
        _onVoiceChanged();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Could not change microphone state')));
        }
      }
      return;
    }

    setState(() => _voiceJoining = true);
    final app = AppScope.of(context);
    lk.Room? joiningRoom;
    try {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        throw StateError('Microphone access is needed for Whot voice');
      }
      Map<String, dynamic> raw;
      try {
        raw = await app.api.post('/calls/games/${widget.roomId}/token')
            as Map<String, dynamic>;
      } on ApiException catch (error) {
        // Older backend deployments still expose the Whot-specific path.
        if (error.status != 404) rethrow;
        raw = await app.api.post('/calls/whot/${widget.roomId}/token')
            as Map<String, dynamic>;
      }
      joiningRoom = lk.Room();
      await joiningRoom.connect(
          raw['livekitUrl'] as String, raw['token'] as String);
      await joiningRoom.localParticipant?.setMicrophoneEnabled(true);
      if (!mounted) {
        await joiningRoom.disconnect();
        joiningRoom.dispose();
        return;
      }
      _voiceRoom = joiningRoom;
      joiningRoom.addListener(_onVoiceChanged);
      setState(() => _voiceJoining = false);
      _onVoiceChanged();
    } catch (e) {
      if (joiningRoom != null) {
        await joiningRoom.disconnect();
        joiningRoom.dispose();
      }
      if (!mounted) return;
      setState(() => _voiceJoining = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is StateError
            ? e.message
            : e is ApiException
                ? 'Whot voice: ${e.message}'
                : 'Could not connect to the voice server. Please try again.'),
      ));
    }
  }

  Future<void> _leaveVoice() async {
    final room = _voiceRoom;
    if (room == null) return;
    room.removeListener(_onVoiceChanged);
    _voiceRoom = null;
    if (mounted) setState(() => _voiceParticipants = 0);
    await room.disconnect();
    room.dispose();
  }

  void _togglePause() => _socket.send('PAUSE_TOGGLE');

  void _showHelp() {
    showHowToPlay(
      context,
      emoji: '🃏',
      title: 'Whot',
      tagline: 'Match the shape or number on top of the pile — first to empty '
          'their hand wins.',
      steps: const [
        "On your turn, play a card that matches the top card's shape or number, or play a WHOT card any time.",
        'Playing a WHOT lets you call a new shape — the next player must match it.',
        'Watch for specials: 2 makes the next player pick two, 14 sends everyone else to the market, '
            '1 lets you go again, 8 skips the next player (if this table plays them).',
        'No playable card? Draw from the market and your turn passes.',
        'First player to play their last card wins the round.',
      ],
    );
  }

  void _toggleMuteSpectators() => _socket.send('MUTE_SPECTATORS_TOGGLE');

  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xff21112a),
        title: Text(widget.spectating ? 'Stop watching?' : 'Leave the game?',
            style: const TextStyle(color: _cream)),
        content: Text(
            widget.spectating
                ? 'You will leave this table and return to the games screen.'
                : 'A table with only your Cyber Agents will end and free them. Other tables can be rejoined with the huud code.',
            style: const TextStyle(color: Color(0xffd7bddf))),
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
      if (!widget.spectating) {
        final app = AppScope.of(context);
        try {
          final endedBotTable =
              await app.api.post('/rooms/${widget.roomId}/leave-whot') == true;
          if (endedBotTable || _finished) {
            await app.clearActiveRoom(widget.roomId);
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
      _socket.close();
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell()), (_) => false);
    }
  }

  Future<void> _confirmForfeit() async {
    final end = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xff21112a),
        title: const Text('End this game?', style: TextStyle(color: _cream)),
        content: const Text(
            'The next player will be awarded the win. This cannot be undone.',
            style: TextStyle(color: Color(0xffd7bddf))),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep playing')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('End game',
                  style: TextStyle(color: Color(0xffff826f)))),
        ],
      ),
    );
    if (end == true && !_disconnected) {
      _socket.send('PLAYER_ACTION', {
        'action': 'FORFEIT',
        'actionId':
            '${widget.selfId}-${DateTime.now().microsecondsSinceEpoch}-${_actionSequence++}',
        'data': const <String, dynamic>{},
      });
    }
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        height: 42,
        child: Row(children: [
          Icon(icon, size: 18, color: _gold),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: _cream, fontSize: 13)),
        ]),
      );

  Future<void> _playCard(String card) async {
    final index = _hand.indexOf(card);
    if (index < 0 || !_myTurn || !_canAct || !whotCanPlay(card, _state)) return;
    setState(() => _selected = index);
    await _play();
  }

  List<Offset> _seatOffsets(int count) {
    if (count == 1) return const [Offset(.5, .05)];
    if (count == 2) return const [Offset(.22, .1), Offset(.78, .1)];
    if (count == 3) {
      return const [Offset(.12, .34), Offset(.5, .05), Offset(.88, .34)];
    }
    return [
      for (var i = 0; i < count; i++)
        Offset(
          .5 + .45 * math.cos(math.pi + math.pi * (i + .35) / (count - .3)),
          .49 + .42 * math.sin(math.pi + math.pi * (i + .35) / (count - .3)),
        )
    ];
  }

  Offset _seatOffsetFor(String player) {
    final players = widget.spectating
        ? _players
        : _players.where((id) => id != widget.selfId).toList();
    final index = players.indexOf(player);
    if (index < 0) return const Offset(.5, .08);
    return _seatOffsets(players.length)[index];
  }

  Widget _opponentCardStack(String player, double scale) {
    final remaining = (_sizes[player] as num?)?.toInt() ?? 0;
    if (remaining <= 0) {
      return const Text('NO CARDS',
          key: ValueKey('whot-empty-hand'),
          style: TextStyle(
              color: _gold, fontSize: 8, fontWeight: FontWeight.w900));
    }
    return SizedBox(
      width: 42 * scale,
      height: 23 * scale,
      child: Stack(children: [
        for (var i = 0; i < math.min(3, remaining); i++)
          Positioned(
              left: i * 7 * scale,
              child:
                  WhotCardView(code: null, compact: true, scale: .26 * scale)),
      ]),
    );
  }

  Widget _playerSeat(String player, double diameter, bool showName,
      {bool showCards = true}) {
    final active = _state['turnPlayer'] == player && !_deal && !_finished;
    final color = active ? const Color(0xff35e47d) : const Color(0xffffb43d);
    final avatar = widget.avatars[player];
    final isRemoteImage = avatar != null &&
        (avatar.startsWith('https://') ||
            avatar.startsWith('http://') ||
            avatar.startsWith('data:image/'));
    return Tooltip(
      message: _name(player),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xff160c1c),
              border: Border.all(color: color, width: active ? 3 : 2),
              boxShadow: [
                BoxShadow(
                    color: color.withValues(alpha: active ? .75 : .35),
                    blurRadius: active ? 14 : 5)
              ]),
          child: ValueListenableBuilder<Set<String>>(
            valueListenable: _socket.onlinePlayers,
            builder: (_, online, __) => OnlineAvatar(_name(player),
                size: diameter,
                online: online.contains(player),
                emoji: isRemoteImage ? null : avatar,
                imageUrl: isRemoteImage ? avatar : null),
          ),
        ),
        if (showName)
          Container(
            constraints: BoxConstraints(maxWidth: diameter + 28),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
                color: const Color(0xcc07190f),
                borderRadius: BorderRadius.circular(7)),
            child: Text(_name(player),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: math.max(8, diameter * .25),
                    fontWeight: FontWeight.w700)),
          ),
        if (showCards) ...[
          const SizedBox(height: 2),
          _opponentCardStack(player, (diameter / 38).clamp(.7, 1.05)),
        ],
      ]),
    );
  }

  Widget _playerSeats(double width, double height) {
    final players = widget.spectating
        ? _players
        : _players.where((p) => p != widget.selfId).toList();
    final offsets = _seatOffsets(players.length);
    final diameter = players.length <= 3
        ? math.min(42.0, width * .115)
        : players.length <= 7
            ? math.min(34.0, width * .09)
            : players.length <= 12
                ? math.min(28.0, width * .072)
                : math.min(23.0, width * .058);
    final seatWidth = diameter + 38;
    final seatHeight = diameter + (players.length <= 10 ? 39 : 27);
    return Stack(children: [
      for (var i = 0; i < players.length; i++)
        Positioned(
          left: (offsets[i].dx * width - seatWidth / 2)
              .clamp(0.0, math.max(0.0, width - seatWidth)),
          top: (offsets[i].dy * height - diameter / 2)
              .clamp(0.0, math.max(0.0, height - seatHeight)),
          width: seatWidth,
          child: _playerSeat(players[i], diameter, players.length <= 10),
        ),
    ]);
  }

  Widget _discardPile(
          String top, int count, List<String> visible, double scale) =>
      Stack(
        key: const ValueKey('whot-discard-pile'),
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (count >= 3)
            Transform.translate(
                offset: Offset(-9 * scale, 6 * scale),
                child: Transform.rotate(
                    angle: -.06,
                    child: WhotCardView(
                        code: visible.length >= 3
                            ? visible[visible.length - 3]
                            : null,
                        scale: scale))),
          if (count >= 2)
            Transform.translate(
                offset: Offset(7 * scale, 3 * scale),
                child: WhotCardView(
                    code: visible.length >= 2
                        ? visible[visible.length - 2]
                        : null,
                    scale: scale)),
          if (top.isNotEmpty)
            AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, animation) => ScaleTransition(
                    scale: CurvedAnimation(
                        parent: animation, curve: Curves.easeOutBack),
                    child: child),
                child:
                    WhotCardView(key: ValueKey(top), code: top, scale: scale)),
          if (count == 0)
            Container(
              width: 88 * scale,
              height: 124 * scale,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14 * scale),
                border:
                    Border.all(color: _gold.withValues(alpha: .7), width: 2),
              ),
            ),
        ],
      );

  Widget _marketPile(int count, double scale) => Stack(
        key: const ValueKey('whot-market-pile'),
        alignment: Alignment.center,
        children: [
          if (count >= 3)
            Transform.translate(
                offset: Offset(-5 * scale, 8 * scale),
                child: WhotCardView(code: null, scale: scale)),
          if (count >= 2)
            Transform.translate(
                offset: Offset(4 * scale, 4 * scale),
                child: WhotCardView(code: null, scale: scale)),
          if (count > 0) WhotCardView(code: null, scale: scale),
          if (count == 0)
            Container(
              width: 88 * scale,
              height: 124 * scale,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14 * scale),
                border:
                    Border.all(color: _gold.withValues(alpha: .7), width: 2),
              ),
            ),
        ],
      );

  Widget _handFan(double width) {
    if (_hand.isEmpty) {
      return const Center(
          child: Text('Waiting for your cards',
              style: TextStyle(color: _cream, fontSize: 11)));
    }
    final count = _hand.length;
    final scale = count <= 6
        ? (width < 350 ? .68 : .78)
        : count <= 10
            ? .66
            : .56;
    final cardWidth = 88 * scale;
    final usable = math.max(1.0, width - cardWidth - 20);
    final step =
        count == 1 ? 0.0 : math.min(cardWidth * .72, usable / (count - 1));
    final spread = cardWidth + step * (count - 1);
    final start = (width - spread) / 2;
    final selected = _selected;
    final order = [
      for (var i = 0; i < count; i++)
        if (i != selected) i,
      if (selected != null && selected < count) selected,
    ];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final i in order)
          AnimatedPositioned(
            key: ValueKey('hand-$i-${_hand[i]}'),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            left: start + i * step,
            bottom: i == selected ? 13 : 2 + (i - (count - 1) / 2).abs() * 1.8,
            child: Transform.rotate(
              angle: count == 1
                  ? 0
                  : (i - (count - 1) / 2) *
                      math.min(.075, .32 / math.max(1, count - 1)),
              child: _draggableHandCard(i, scale),
            ),
          ),
      ],
    );
  }

  Widget _draggableHandCard(int index, double scale) {
    final card = _hand[index];
    final legal = _myTurn && _canAct && whotCanPlay(card, _state);
    final face = WhotCardView(
        code: card,
        scale: scale,
        selected: _selected == index,
        onTap: () => setState(() => _selected = index));
    if (!legal) return face;
    return Draggable<String>(
      data: card,
      rootOverlay: true,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => setState(() => _selected = index),
      feedback: Material(
          color: Colors.transparent,
          child: Transform.scale(
              scale: 1.08,
              child: WhotCardView(code: card, scale: scale, selected: true))),
      childWhenDragging: Opacity(opacity: .18, child: face),
      child: face,
    );
  }

  Widget _cardFlightLayer(Size size) => IgnorePointer(
        child: Stack(children: [
          if (_reshuffleFlights.isNotEmpty)
            Positioned(
              left: size.width * .35,
              right: size.width * .35,
              top: size.height * .36,
              child: const Text('RESHUFFLING MARKET',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _gold, fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          for (final flight in [..._reshuffleFlights, ..._cardFlights])
            TweenAnimationBuilder<double>(
              key: ValueKey(flight.id),
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 850 + flight.delayMs),
              curve: Curves.easeInOutCubic,
              builder: (context, rawProgress, child) {
                final elapsed =
                    rawProgress * (850 + flight.delayMs) - flight.delayMs;
                final progress = (elapsed / 850).clamp(0.0, 1.0);
                final x =
                    flight.from.dx + (flight.to.dx - flight.from.dx) * progress;
                final y =
                    flight.from.dy + (flight.to.dy - flight.from.dy) * progress;
                return Positioned(
                  left: x * size.width - 23,
                  top: y * size.height - 31,
                  child: Opacity(
                    opacity: elapsed < 0 ? 0 : 1,
                    child: Transform.rotate(
                      angle: (1 - progress) * -.12,
                      child: Transform.scale(
                          scale: .9 + math.sin(progress * math.pi) * .14,
                          child: child),
                    ),
                  ),
                );
              },
              child: WhotCardView(code: flight.code, compact: true, scale: .72),
            ),
        ]),
      );

  String _statusText() {
    if (_finished) return '$_winnerLabel won!';
    if (_choosingSignals) return 'THE TELL · CHOOSE YOUR TEAM SIGNAL';
    if (_tell && !_activeTellPlayer) {
      return (_state['qualifiedTeams'] as List? ?? const [])
              .contains(_state['yourTeam'])
          ? 'YOUR TEAM QUALIFIED · WAIT FOR THE FINAL'
          : 'YOUR TEAM IS OUT · WATCH THE TABLE';
    }
    if (_deal) return 'SHUFFLING · PLAY BEGINS IN $_seconds';
    if (_paused) return 'TABLE PAUSED';
    if (_myTurn) return 'YOUR TURN · DRAG A CARD TO DISCARD';
    return '${_name(_state['turnPlayer'])} IS PLAYING · $_seconds';
  }

  Widget _tableBoard(String top, int debt) => LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxHeight < 370;
          final cardScale = compact ? .72 : .82;
          final marketCount = (_state['marketLeft'] as num?)?.toInt() ?? 0;
          final discardCount = (_state['discardCount'] as num?)?.toInt() ??
              (top.isEmpty ? 0 : 1);
          final discardCards = (_state['discardCards'] as List? ?? const [])
              .map((card) => card.toString())
              .toList();
          final handHeight = widget.spectating ? 0.0 : (compact ? 92.0 : 112.0);
          final handBottom = compact ? 37.0 : 43.0;
          return Container(
            margin: const EdgeInsets.fromLTRB(5, 3, 5, 3),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(42),
                gradient: const LinearGradient(colors: [
                  Color(0xff9b592d),
                  Color(0xff4a2418),
                  Color(0xffa36836),
                  Color(0xff3d1d15),
                ]),
                border: Border.all(color: const Color(0xffd18a45), width: 2),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0xaa000000),
                      blurRadius: 14,
                      offset: Offset(0, 6))
                ]),
            padding: const EdgeInsets.all(7),
            child: Container(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(35),
                  gradient: const RadialGradient(
                      center: Alignment(-.2, -.25),
                      radius: 1.15,
                      colors: [Color(0xff08733d), Color(0xff004526)]),
                  border: Border.all(color: const Color(0xff1d2c1f), width: 3)),
              child: Stack(children: [
                Positioned.fill(
                    child: Opacity(
                        opacity: .045,
                        child: CustomPaint(painter: _FeltPatternPainter()))),
                Positioned.fill(
                    child: _playerSeats(
                        box.maxWidth - 14, box.maxHeight - handHeight - 14)),
                Align(
                  alignment: Alignment(0, compact ? -.10 : -.04),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    GestureDetector(
                      onTap: _myTurn && _canAct ? _drawFromMarket : null,
                      child: SizedBox(
                        width: compact ? 104 : 122,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          _marketPile(marketCount, cardScale),
                          const SizedBox(height: 5),
                          Text(
                              debt > 0
                                  ? 'MARKET · PICK $debt'
                                  : 'MARKET · $marketCount',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                    SizedBox(width: compact ? 24 : 34),
                    DragTarget<String>(
                      key: const ValueKey('whot-discard-target'),
                      onWillAcceptWithDetails: (details) =>
                          _myTurn &&
                          _canAct &&
                          whotCanPlay(details.data, _state),
                      onAcceptWithDetails: (details) => _playCard(details.data),
                      builder: (context, candidates, rejected) => SizedBox(
                        width: compact ? 104 : 122,
                        child: AnimatedScale(
                          scale: candidates.isEmpty ? 1 : 1.12,
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOutBack,
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            _discardPile(
                                top, discardCount, discardCards, cardScale),
                            const SizedBox(height: 5),
                            Text(
                                top.isEmpty
                                    ? 'DISCARD'
                                    : 'DISCARD · ${top.replaceAll('-', ' ').toUpperCase()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: candidates.isEmpty
                                        ? Colors.white
                                        : const Color(0xff52f597),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                ),
                if (!widget.spectating)
                  Positioned(
                      left: 0,
                      right: 0,
                      bottom: handBottom,
                      height: handHeight,
                      child: _handFan(box.maxWidth - 14)),
                if (!widget.spectating)
                  Positioned(
                    bottom: 1,
                    left: box.maxWidth / 2 - 31,
                    child: _playerSeat(widget.selfId, compact ? 21 : 25, true,
                        showCards: false),
                  ),
                Positioned.fill(
                    child: _cardFlightLayer(
                        Size(box.maxWidth - 14, box.maxHeight - 14))),
              ]),
            ),
          );
        },
      );

  Widget _signalSetupView() {
    if (widget.spectating || !_activeTellPlayer) {
      return const Center(
        child: Text('Teams are choosing private signals',
            style: TextStyle(color: _cream, fontSize: 18)),
      );
    }
    final team = (_state['yourTeam'] as num?)?.toInt();
    final teams = _state['teams'] as List? ?? const [];
    final members = team != null && team >= 0 && team < teams.length
        ? (teams[team] as List).map((id) => id.toString()).toList()
        : <String>[];
    final partner = members.where((id) => id != widget.selfId).firstOrNull;
    final selected = _state['yourSignal']?.toString() ?? '';
    final confirmed = _state['yourSignalConfirmed'] == true;
    return Container(
      key: const ValueKey('whot-tell-signal-setup'),
      padding: const EdgeInsets.all(18),
      color: const Color(0xff100916),
      child: ListView(children: [
        Text('TEAM ${(team ?? 0) + 1} · ${_name(partner)} & YOU',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _gold, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(
            selected.isEmpty
                ? 'Choose a secret symbol. Your teammate will see it privately and tap to confirm.'
                : confirmed
                    ? 'You chose $selected. Waiting for your teammate to confirm.'
                    : 'Your teammate chose $selected. Tap it to confirm, or choose another.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _cream, fontSize: 12)),
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final symbol in _tellSymbols)
              SizedBox(
                width: 50,
                height: 50,
                child: OutlinedButton(
                  key: ValueKey('whot-choose-$symbol'),
                  onPressed: _canAct && _activeTellPlayer
                      ? () => _action('CHOOSE_SIGNAL', {'symbol': symbol})
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: symbol == selected
                        ? _gold.withValues(alpha: .24)
                        : const Color(0xff21112a),
                    side:
                        BorderSide(color: symbol == selected ? _gold : _cream),
                  ),
                  child: Text(symbol, style: const TextStyle(fontSize: 25)),
                ),
              ),
          ],
        ),
      ]),
    );
  }

  Widget _signalTray() => SizedBox(
        key: const ValueKey('whot-tell-signal-tray'),
        height: 69,
        child: Column(children: [
          const Text('SEND A SIGNAL OR DECOY',
              style: TextStyle(
                  color: _gold, fontSize: 10, fontWeight: FontWeight.w900)),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _tellSymbols.length,
              separatorBuilder: (context, index) => const SizedBox(width: 5),
              itemBuilder: (context, index) {
                final symbol = _tellSymbols[index];
                return IconButton.filledTonal(
                  key: ValueKey('whot-send-$symbol'),
                  tooltip: 'Send $symbol',
                  onPressed: _canAct
                      ? () => _action('SIGNAL', {'symbol': symbol})
                      : null,
                  icon: Text(symbol, style: const TextStyle(fontSize: 23)),
                );
              },
            ),
          ),
        ]),
      );

  Widget _signalCard() {
    final signal = _visibleSignal!;
    final sender = signal['by']?.toString();
    final myTeam = (_state['yourTeam'] as num?)?.toInt();
    final teams = _state['teams'] as List? ?? const [];
    final partner = myTeam != null &&
        myTeam >= 0 &&
        myTeam < teams.length &&
        (teams[myTeam] as List).contains(sender);
    final canBuzz = !widget.spectating &&
        sender != widget.selfId &&
        _activeTellPlayer &&
        _canAct;
    final id = (signal['id'] as num).toInt();
    return Center(
      child: Material(
        key: const ValueKey('whot-tell-signal-card'),
        color: const Color(0xf321122a),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: _gold, width: 2),
        ),
        elevation: 16,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: canBuzz ? () => _action('BUZZ', {'signalId': id}) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${_name(sender)} → ${signal['symbol']}',
                  style: const TextStyle(
                      color: _cream,
                      fontSize: 30,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(
                canBuzz
                    ? partner
                        ? 'TAP TO BUZZ'
                        : 'TAP TO INTERCEPT'
                    : 'SIGNAL SENT',
                style: const TextStyle(
                    color: _gold, fontSize: 12, fontWeight: FontWeight.w900),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _friendlyBuild(BuildContext context) {
    final top = _state['topCard'] as String? ?? '';
    final debt = _state['pendingPick'] as int? ?? 0;
    final dealer = _state['dealer'] == widget.selfId;
    return Scaffold(
      backgroundColor: const Color(0xff100916),
      appBar: AppBar(
        toolbarHeight: 54,
        backgroundColor: const Color(0xff140a1b),
        foregroundColor: _cream,
        automaticallyImplyLeading: false,
        titleSpacing: 12,
        title: InkWell(
          key: const ValueKey('whot-room-code-copy'),
          borderRadius: BorderRadius.circular(12),
          onTap: _copyRoomCode,
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
                color: const Color(0xff21112a),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xff50345d))),
            child: Row(children: [
              const Text('HUUD',
                  style: TextStyle(
                      color: _gold,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(_displayRoomCode,
                      maxLines: 1,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .7)),
                ),
              ),
              const SizedBox(width: 7),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _roomCopied
                    ? const Text('COPIED',
                        key: ValueKey('copied'),
                        style: TextStyle(
                            color: Color(0xff52f597),
                            fontSize: 9,
                            fontWeight: FontWeight.w900))
                    : const Icon(Icons.copy_rounded,
                        key: ValueKey('copy'), size: 16, color: _cream),
              ),
            ]),
          ),
        ),
        actions: [
          IconButton(
            key: const ValueKey('whot-audio-toggle'),
            tooltip: _musicOn || _sfxOn
                ? 'Mute music and effects'
                : 'Unmute music and effects',
            icon: Icon(_musicOn || _sfxOn
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded),
            onPressed: _toggleAudio,
          ),
          if (!widget.spectating)
            IconButton(
              key: const ValueKey('whot-voice-toggle'),
              tooltip: _voiceJoining
                  ? 'Connecting to voice'
                  : _voiceRoom == null
                      ? 'Join Whot voice'
                      : _micMuted
                          ? 'Unmute microphone'
                          : 'Mute microphone · $_voiceParticipants in voice',
              icon: Icon(
                _voiceRoom == null
                    ? Icons.mic_none_rounded
                    : _micMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                color: _voiceRoom == null ? _cream : const Color(0xff52f597),
              ),
              onPressed: _voiceJoining ? null : _toggleVoice,
            ),
          PopupMenuButton<String>(
            tooltip: 'Game settings',
            icon: const Icon(Icons.settings_rounded, size: 21),
            color: const Color(0xff21112a),
            onSelected: (value) {
              switch (value) {
                case 'help':
                  _showHelp();
                case 'pause':
                  _togglePause();
                case 'music':
                  _toggleMusic();
                case 'sfx':
                  _toggleSfx();
                case 'leaveVoice':
                  _leaveVoice();
                case 'spectators':
                  _toggleMuteSpectators();
                case 'forfeit':
                  _confirmForfeit();
                case 'exit':
                  _confirmExit();
              }
            },
            itemBuilder: (_) => [
              _menuItem('help', Icons.help_outline_rounded, 'How to play'),
              if (!widget.spectating && !_finished)
                _menuItem(
                    'pause',
                    _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    _paused ? 'Resume' : 'Pause'),
              _menuItem(
                  'music',
                  _musicOn ? Icons.music_note_rounded : Icons.music_off_rounded,
                  _musicOn ? 'Mute music' : 'Play music'),
              _menuItem(
                  'sfx',
                  _sfxOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  _sfxOn ? 'Mute game sounds' : 'Play game sounds'),
              if (_voiceRoom != null)
                _menuItem('leaveVoice', Icons.call_end_rounded, 'Leave voice'),
              if (!widget.spectating)
                _menuItem(
                    'spectators',
                    _state['spectatorsMuted'] == true
                        ? Icons.comments_disabled_rounded
                        : Icons.chat_bubble_outline_rounded,
                    _state['spectatorsMuted'] == true
                        ? 'Let spectators comment'
                        : 'Mute spectator comments'),
              if (!widget.spectating && !_finished)
                _menuItem('forfeit', Icons.flag_outlined, 'End game'),
              _menuItem('exit', Icons.logout_rounded,
                  widget.spectating ? 'Stop watching' : 'Leave'),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _state.isEmpty && !_disconnected
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                if (_error != null)
                  Container(
                      width: double.infinity,
                      color: const Color(0xff6f2030),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      child: Text(_error!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10))),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 3),
                  color: const Color(0xff100916),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_statusText(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: _cream,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .7)),
                    if (_activity != 'Welcome to the table')
                      Text(_activity,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _gold, fontSize: 9)),
                  ]),
                ),
                Expanded(
                  child: _choosingSignals
                      ? _signalSetupView()
                      : Stack(children: [
                          Positioned.fill(
                            child: _paused
                                ? ClipRect(
                                    child: ImageFiltered(
                                      key: const ValueKey(
                                          'whot-paused-table-blur'),
                                      imageFilter: ui.ImageFilter.blur(
                                          sigmaX: 7, sigmaY: 7),
                                      child: _tableBoard(top, debt),
                                    ),
                                  )
                                : _tableBoard(top, debt),
                          ),
                          if (_paused)
                            Positioned.fill(
                              child: Container(
                                key:
                                    const ValueKey('whot-paused-table-overlay'),
                                margin: const EdgeInsets.fromLTRB(5, 3, 5, 3),
                                decoration: BoxDecoration(
                                  color: const Color(0x74100916),
                                  borderRadius: BorderRadius.circular(42),
                                ),
                                alignment: Alignment.center,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xdd21112a),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: _gold),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Color(0x99000000),
                                          blurRadius: 18,
                                          offset: Offset(0, 6)),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.pause_rounded,
                                              color: _gold, size: 24),
                                          SizedBox(width: 8),
                                          Text('GAME PAUSED',
                                              style: TextStyle(
                                                  color: _cream,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 1)),
                                        ],
                                      ),
                                      if (!widget.spectating) ...[
                                        const SizedBox(height: 12),
                                        FilledButton.icon(
                                          key: const ValueKey(
                                              'whot-resume-button'),
                                          onPressed: _disconnected
                                              ? null
                                              : _togglePause,
                                          icon: const Icon(
                                              Icons.play_arrow_rounded),
                                          label: const Text('Resume game'),
                                        ),
                                      ] else ...[
                                        const SizedBox(height: 8),
                                        const Text(
                                            'Waiting for a player to resume',
                                            style: TextStyle(
                                                color: _cream, fontSize: 11)),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            top: 70,
                            left: 12,
                            right: 12,
                            child: IgnorePointer(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 350),
                                child: _lastCardWarning == null || _finalSplash
                                    ? const SizedBox.shrink(
                                        key: ValueKey('no-warning'))
                                    : Center(
                                        key: ValueKey(_lastCardWarning),
                                        child: Container(
                                          key: const ValueKey(
                                              'whot-last-card-warning'),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 18, vertical: 11),
                                          decoration: BoxDecoration(
                                            color: const Color(0xe82b1227),
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            border: Border.all(
                                                color: _gold, width: 2),
                                          ),
                                          child: Text(
                                            '${_name(_lastCardWarning)} · LAST CARD!',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: _cream,
                                                fontSize: 19,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: .5),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          if (_visibleSignal != null && !_paused)
                            Positioned(
                                left: 18,
                                right: 18,
                                top: 82,
                                child: _signalCard()),
                          if (_finalSplash)
                            Positioned.fill(child: _finishSplash()),
                        ]),
                ),
                if (_tell &&
                    !widget.spectating &&
                    _activeTellPlayer &&
                    (_state['phase'] == 'Turn' || _state['phase'] == 'Waiting'))
                  _signalTray(),
                if (!widget.spectating && (_deal || _finished || _disconnected))
                  SizedBox(
                      height: 42,
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_disconnected)
                              _smallAction('RECONNECT', _reconnect)
                            else if (_finished)
                              _smallAction(
                                  'BACK TO GAMES',
                                  () => Navigator.of(context)
                                      .popUntil((route) => route.isFirst))
                            else if (_deal && dealer) ...[
                              _smallAction('SHUFFLE', () => _action('SHUFFLE')),
                              _smallAction('DEAL', () => _action('DEAL')),
                              _smallAction(
                                  'DEAL HAND',
                                  _canAct && _hand.isEmpty
                                      ? () => _action('DEAL', {
                                            'rounds':
                                                _state['suggestedHand'] ?? 5
                                          })
                                      : null),
                              _smallAction(
                                  'START',
                                  _canAct &&
                                          _sizes.isNotEmpty &&
                                          _sizes.values.every(
                                              (count) => (count as int) >= 3)
                                      ? () => _action('START')
                                      : null),
                            ],
                          ])),
                const SizedBox(height: 7),
                TableChatPanel(
                    lines: _chat,
                    controller: _chatController,
                    onSend: _sendChat,
                    spectatorCount: _state['spectatorCount'] as int? ?? 0,
                    amSpectator: widget.spectating,
                    height: 58,
                    canSend: !_disconnected && !_chatMuted,
                    disabledHint: _chatMuted
                        ? 'Spectator chat is muted'
                        : 'Reconnect to comment'),
              ]),
      ),
    );
  }

  Widget _smallAction(String label, VoidCallback? onPressed) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: Text(label,
              style:
                  const TextStyle(fontSize: 10, fontWeight: FontWeight.w800))));

  @override
  Widget build(BuildContext context) =>
      _showSummary ? _resultSummary() : _friendlyBuild(context);

  Widget _finishSplash() => Container(
        key: const ValueKey('whot-final-splash'),
        decoration: const BoxDecoration(
          gradient: RadialGradient(
              colors: [Color(0xf0a83c53), Color(0xf019102c), Color(0xff100916)],
              radius: 1.2),
        ),
        alignment: Alignment.center,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: .48, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.elasticOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.auto_awesome_rounded, color: _gold, size: 56),
            const SizedBox(height: 14),
            const Text('FINAL CARD!',
                style: TextStyle(
                    color: _cream,
                    fontSize: 35,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2)),
            const SizedBox(height: 18),
            if (_lastPlayedCard != null)
              WhotCardView(code: _lastPlayedCard, scale: .9),
            const SizedBox(height: 18),
            Text('${_name(_state['winner'])} clears their hand',
                style: const TextStyle(
                    color: _gold, fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
        ),
      );

  Widget _resultSummary() {
    final won = _won;
    final others = _players.where((player) => player != widget.selfId);
    return Scaffold(
      key: const ValueKey('whot-result-summary'),
      backgroundColor: const Color(0xff100916),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 12),
                children: [
                  Icon(won ? Icons.emoji_events_rounded : Icons.flag_rounded,
                      color: _gold, size: 56),
                  const SizedBox(height: 12),
                  Text(
                      widget.spectating
                          ? 'GAME OVER'
                          : won
                              ? 'VICTORY!'
                              : 'DEFEAT',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: _cream,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 6),
                  Text('$_winnerLabel won Whot',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: _gold,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        color: const Color(0xff21112a),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _gold)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('GAME SUMMARY',
                              style: TextStyle(
                                  color: _gold,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2)),
                          const SizedBox(height: 12),
                          _summaryLine('Winner', _winnerLabel),
                          if (!widget.spectating)
                            _summaryLine('Your cards left',
                                '${_sizes[widget.selfId] ?? _hand.length}'),
                          for (final player in others)
                            _summaryLine('${_name(player)} cards left',
                                '${_sizes[player] ?? 0}'),
                          _summaryLine(
                              'Final card',
                              _winnerClearedHand
                                  ? (_lastPlayedCard ??
                                          _state['topCard'] ??
                                          '—')
                                      .toString()
                                      .replaceAll('-', ' ')
                                  : 'None · game ended early'),
                          _summaryLine(
                              'Rounds played', '${_state['round'] ?? 0}'),
                        ]),
                  ),
                ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
            child: Column(children: [
              if (won)
                VictoryShareButton(
                    roomId: widget.roomId,
                    gameType: 'whot',
                    detail: '$_winnerLabel won Whot'),
              if (!widget.spectating) ...[
                NeonButton('Play again',
                    onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => const WhotLobbyScreen()))),
                const SizedBox(height: 8),
              ],
              NeonButton('Play another game',
                  style: NeonStyle.ghost,
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const MainShell()),
                      (_) => false)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _summaryLine(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: _cream))),
          Text(value,
              style:
                  const TextStyle(color: _gold, fontWeight: FontWeight.w900)),
        ]),
      );

  // Kept temporarily as a reference while the compact layout is exercised.
  // ignore: unused_element
  Widget _legacyBuild(BuildContext context) {
    final top = _state['topCard'] as String? ?? '';
    final debt = _state['pendingPick'] as int? ?? 0;
    final dealer = _state['dealer'] == widget.selfId;
    final selectedCode = _selected != null && _selected! < _hand.length
        ? _hand[_selected!]
        : null;
    final winner = _state['winner'] as String?;
    return Scaffold(
      backgroundColor: const Color(0xff201315),
      appBar: AppBar(
          title: Text(widget.spectating ? 'Watching Whot' : 'Whot'),
          actions: [
            if (!widget.spectating && _state.isNotEmpty)
              IconButton(
                  tooltip: _state['spectatorsMuted'] == true
                      ? 'Unmute spectators'
                      : 'Mute spectators',
                  icon: Icon(_state['spectatorsMuted'] == true
                      ? Icons.comments_disabled
                      : Icons.comment_outlined),
                  onPressed: _disconnected
                      ? null
                      : () => _socket.send('MUTE_SPECTATORS_TOGGLE')),
            if (!widget.spectating && _state.isNotEmpty && !_finished)
              IconButton(
                  tooltip: _paused ? 'Resume table' : 'Pause table',
                  icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                  onPressed: _disconnected
                      ? null
                      : () => _socket.send('PAUSE_TOGGLE')),
            IconButton(
                tooltip: 'House rules',
                icon: const Icon(Icons.help_outline),
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                            title: const Text('At this table'),
                            content: SingleChildScrollView(
                                child: Text(
                                    'Match a shape or number. Drawing ends your turn. First empty hand wins.\n\n'
                                    'The table deals automatically and begins play within 5 seconds. The dealer can start sooner.\n\n'
                                    '${(_state['rules'] as Map? ?? {}).entries.map((e) => '${_ruleName(e.key.toString())}: ${e.value == true ? 'on' : 'off'}').join('\n')}')),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Got it'))
                            ]))),
          ]),
      body: SafeArea(
          child: _state.isEmpty && !_disconnected
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                                '${_state['spectatorCount'] ?? 0} watching${widget.spectating ? ' · Hands stay private' : ''}',
                                style: const TextStyle(color: _gold))),
                        if (_disconnected) ...[
                          const Text('Connection lost',
                              style: TextStyle(color: _cream)),
                          NeonButton('Reconnect', onPressed: _reconnect)
                        ],
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: Color(0xffff927c)))),
                        SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              for (final p in _players)
                                Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    width: 106,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                        color: const Color(0xff362126),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: p == _state['turnPlayer'] &&
                                                    !_deal &&
                                                    !_finished
                                                ? _gold
                                                : const Color(0xff57363c),
                                            width: 2)),
                                    child: Column(children: [
                                      Text(_name(p),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: _cream,
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 6),
                                      Text('${_sizes[p] ?? 0} cards',
                                          style: const TextStyle(color: _gold)),
                                      if (p == _state['dealer'] && _deal)
                                        const Text('DEALER',
                                            style: TextStyle(
                                                color: _cream, fontSize: 10)),
                                    ]),
                                  ),
                                )
                            ])),
                        const SizedBox(height: 22),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 24),
                            decoration: BoxDecoration(
                                gradient: const RadialGradient(colors: [
                                  Color(0xff28554a),
                                  Color(0xff132f2a)
                                ], radius: 1),
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(
                                    color: const Color(0xff916a3b), width: 5)),
                            child: Column(children: [
                              Text(
                                  _state['phase'] == 'Lobby'
                                      ? 'Waiting for the host'
                                      : _finished
                                          ? (winner == null
                                              ? 'Game complete'
                                              : '${_name(winner)} won!')
                                          : _paused
                                              ? 'Table paused'
                                              : _deal
                                                  ? '${_name(_state['dealer'])} dealing'
                                                  : _myTurn
                                                      ? 'YOUR TURN'
                                                      : '${_name(_state['turnPlayer'])} to play',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: _cream,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 8),
                              if (!_finished)
                                Text('$_seconds seconds',
                                    style: const TextStyle(color: _gold)),
                              const SizedBox(height: 24),
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Expanded(
                                        child: Column(children: [
                                      const WhotCardView(),
                                      const SizedBox(height: 10),
                                      Text(
                                          'Market · ${_state['marketLeft'] ?? 0}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              color: _cream, fontSize: 12))
                                    ])),
                                    const SizedBox(width: 28),
                                    Expanded(
                                        child: Column(children: [
                                      if (top.isNotEmpty)
                                        WhotCardView(
                                            key: ValueKey(top), code: top)
                                      else
                                        Container(
                                            width: 88,
                                            height: 124,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                                border: Border.all(
                                                    color: const Color(
                                                        0xff688176)),
                                                borderRadius:
                                                    BorderRadius.circular(14)),
                                            child: const Text('First card',
                                                style:
                                                    TextStyle(color: _cream))),
                                      const SizedBox(height: 10),
                                      const Text('In play',
                                          style: TextStyle(
                                              color: _cream, fontSize: 12))
                                    ])),
                                  ]),
                              const SizedBox(height: 18),
                              if (top.startsWith('whot'))
                                Text('Called: ${_state['activeShape']}',
                                    style: const TextStyle(
                                        color: _gold,
                                        fontWeight: FontWeight.bold)),
                              if (debt > 0)
                                Text(
                                    'Pick $debt${(_state['rules'] as Map?)?['pickTwoStacking'] == true ? ' or answer with a 2' : ''}',
                                    style: const TextStyle(color: _gold)),
                              const SizedBox(height: 6),
                              Text(_activity,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: _cream, fontSize: 12)),
                            ])),
                        if (!widget.spectating) ...[
                          const SizedBox(height: 22),
                          Text('YOUR HAND · ${_hand.length}',
                              style: const TextStyle(
                                  color: _cream,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5)),
                          const SizedBox(height: 12),
                          if (_hand.isEmpty)
                            const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('No cards in your hand',
                                    style: TextStyle(color: _cream))),
                          if (_hand.isNotEmpty)
                            SizedBox(
                                height: 136,
                                child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _hand.length,
                                    separatorBuilder: (_, index) =>
                                        const SizedBox(width: 10),
                                    itemBuilder: (context, i) => Align(
                                        alignment: Alignment.topCenter,
                                        child: WhotCardView(
                                            code: _hand[i],
                                            selected: _selected == i,
                                            enabled: !_myTurn ||
                                                whotCanPlay(_hand[i], _state),
                                            onTap: _myTurn &&
                                                    _canAct &&
                                                    whotCanPlay(
                                                        _hand[i], _state)
                                                ? () => setState(
                                                    () => _selected = i)
                                                : null)))),
                          const SizedBox(height: 12),
                          if (_deal && dealer) ...[
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              OutlinedButton(
                                  onPressed:
                                      _canAct ? () => _action('SHUFFLE') : null,
                                  child: const Text('Shuffle')),
                              OutlinedButton(
                                  onPressed:
                                      _canAct ? () => _action('DEAL') : null,
                                  child: const Text('Deal one each')),
                              OutlinedButton(
                                  onPressed: _canAct && _hand.isEmpty
                                      ? () => _action('DEAL', {
                                            'rounds':
                                                _state['suggestedHand'] ?? 5
                                          })
                                      : null,
                                  child: const Text('Deal suggested hand')),
                            ]),
                            const SizedBox(height: 12),
                            NeonButton('Begin play',
                                onPressed: _canAct &&
                                        _sizes.isNotEmpty &&
                                        _sizes.values
                                            .every((n) => (n as int) >= 3)
                                    ? () => _action('START')
                                    : null),
                          ] else if (_deal)
                            const Text('The dealer is preparing your hand.',
                                style: TextStyle(color: _cream)),
                          if (!_deal && !_finished) ...[
                            NeonButton(
                                selectedCode == null
                                    ? 'Select a card'
                                    : 'Play ${selectedCode.replaceAll('-', ' ')}',
                                onPressed:
                                    _myTurn && _canAct && selectedCode != null
                                        ? _play
                                        : null),
                            const SizedBox(height: 10),
                            NeonButton(
                                debt > 0
                                    ? 'Pick $debt cards'
                                    : 'Draw from market',
                                style: NeonStyle.ghost,
                                onPressed: _myTurn && _canAct
                                    ? () => _action('DRAW')
                                    : null),
                          ],
                        ],
                        const SizedBox(height: 18),
                        TableChatPanel(
                            lines: _chat,
                            controller: _chatController,
                            onSend: _sendChat,
                            spectatorCount:
                                _state['spectatorCount'] as int? ?? 0,
                            amSpectator: widget.spectating,
                            canSend: !_disconnected && !_chatMuted,
                            disabledHint: _disconnected
                                ? 'Reconnect to comment'
                                : 'The players have muted spectator chat'),
                        if (_finished)
                          NeonButton('Back to games',
                              onPressed: () => Navigator.of(context)
                                  .popUntil((r) => r.isFirst)),
                      ]),
                )),
    );
  }

  String _ruleName(String rule) =>
      const {
        'includeWhot': '20 · Wild shape',
        'pickTwo': '2 · Pick two',
        'pickTwoStacking': 'Stack twos',
        'generalMarket': '14 · General market',
        'holdOn': '1 · Play again',
        'suspension': '8 · Skip next player'
      }[rule] ??
      rule;
}

class _FeltPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    const gap = 34.0;
    for (var y = -gap; y < size.height + gap; y += gap) {
      for (var x = -gap; x < size.width + gap; x += gap) {
        canvas.drawCircle(
            Offset(x + ((y ~/ gap).isEven ? 0 : gap / 2), y), 7, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CardFlightSpec {
  const _CardFlightSpec(
      {required this.id,
      required this.code,
      required this.from,
      required this.to,
      this.delayMs = 0});

  final int id;
  final String? code;
  final Offset from;
  final Offset to;
  final int delayMs;
}
