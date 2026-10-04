import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/game_socket.dart';
import '../../theme/neon_theme.dart';
import '../../core/game_music.dart';
import '../../core/game_sfx.dart';
import '../../widgets/fireworks.dart';
import '../../widgets/neon.dart';
import '../../widgets/table_chat.dart';
import '../../widgets/game_voice_control.dart';
import '../shell/main_shell.dart';
import '../status/victory_status.dart';
import '../onboarding/guest_save_session_card.dart';
import 'goosi_theme.dart';

/// Goosi — PlayHuud's Oware Abapa game: twelve houses, two players and the
/// standard feeding, grand-slam and 2-or-3 capture rules. See `GoosiModule`
/// (ta-game-goosi) for the full rules; this screen is a thin renderer over
/// the same SNAPSHOT/PHASE/EVENT-in, PLAYER_ACTION-out contract every other
/// game uses. Nothing here is secret, so every event is exactly what's
/// rendered, no per-viewer filtering.
///
/// Unlike Draughts, sowing a pit is a single unambiguous action (there's no
/// destination to choose) — so a tap on one of your own non-empty pits sows
/// it immediately, no arm/confirm step needed.
class GoosiGameScreen extends StatefulWidget {
  const GoosiGameScreen({
    super.key,
    required this.socket,
    required this.selfId,
    required this.nicknames,
    this.roomCode = '',
    this.avatars = const {},
    this.agents = const {},
  });

  final GameSocket socket;
  final String selfId;
  final Map<String, String> nicknames;
  final String roomCode;
  final Map<String, String> avatars;
  final Set<String> agents;

  @override
  State<GoosiGameScreen> createState() => _GoosiGameScreenState();
}

class _GoosiGameScreenState extends State<GoosiGameScreen> {
  static const _bg = Color(0xff180d20);
  static const _panel = Color(0xff26142d);
  static const _gold = Color(0xffffcf66);
  static const _cream = Color(0xffffeee1);
  StreamSubscription? _sub;
  Timer? _ticker;

  String phase = 'TurnP0';
  int round = 1;
  List<String> players = [];
  List<String?> owner = List<String?>.filled(12, null);
  List<int> pits = List<int>.filled(12, 0);
  List<int> legalPits = [];
  Map<String, int> scores = {};
  int pitsPerPlayer = 6;
  String? winningSide;
  int? _coinsAwarded;
  List<String> winners = [];
  int turnSeconds = 45;
  int? _secondsLeft;
  final List<TableChatLine> feed = [];
  final TextEditingController _chatController = TextEditingController();
  bool _actionLocked = false;
  bool _leaving = false;
  bool _paused = false;
  bool _spectatorsMuted = false;
  bool _musicOn = GameMusic.enabled;
  bool _sfxOn = GameSfx.enabled;
  int _spectatorCount = 0;

  GoosiThemeController? _theme;

  /// The sowing currently being played out, and a token that lets a newer
  /// sowing cut an older one short rather than the two interleaving.
  Future<void>? _sowAnimation;
  int _sowToken = 0;

  /// Render keys keep the hand and capture flights anchored to the board the
  /// player can actually see. The tray is vertically centred, so calculating
  /// pit positions from the available screen height made the top hand float.
  final GlobalKey _boardStackKey = GlobalKey();
  final List<GlobalKey> _pitKeys = List.generate(12, (_) => GlobalKey());

  /// The pit the sowing hand is over right now, if a sowing is playing.
  int? _handPit;
  Color _handInk = const Color(0xffffd89a);
  bool _handPressed = false;

  /// Seconds the current grace period runs once resumed.
  int _graceSeconds = 0;

  /// How long the hand takes to reach the next pit — the seed lands when
  /// it gets there, so the overlay and the drop share this.
  Duration _handTravel = const Duration(milliseconds: 420);

  /// Captures in flight from a pit to their owner's store.
  final List<_CaptureFlight> _flights = [];
  int _nextFlightId = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.socket.envelopes.listen(_onEnvelope);
    GameMusic.start(GameMusic.moodFor('goosi'));
    GameSfx.warmUp();
    widget.socket.send('HELLO', {'lastSeq': widget.socket.lastSeq});
    GoosiThemeController.load().then((t) {
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
    _ticker?.cancel();
    GameMusic.stop();
    _theme?.removeListener(_onThemeChanged);
    super.dispose();
  }

  int get myIndex => players.indexOf(widget.selfId);

  /// Spectators talk on the muteable `spectate` channel; players talk on
  /// `table`. Same box either way — the split only exists so muting
  /// spectators doesn't also silence the people playing.
  bool get _amSpectator => !players.contains(widget.selfId);

  void _sendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    widget.socket.send('CHAT_SEND',
        {'channel': _amSpectator ? 'spectate' : 'table', 'text': text});
    _chatController.clear();
  }

  /// Everything anyone says lands in the one box: players, Cyber Agents and
  /// spectators alike.
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

  /// Whose turn it is, read off the phase name — "TurnP2", or "GraceP2a"
  /// once that player's clock has run out. A grace phase is still their
  /// turn: the whole point is that they can still play in it.
  int get turnIndex {
    if (phase.startsWith('TurnP')) {
      return int.tryParse(phase.substring(5)) ?? -1;
    }
    if (phase.startsWith('GraceP') && phase.length >= 8) {
      return int.tryParse(phase.substring(6, phase.length - 1)) ?? -1;
    }
    return -1;
  }

  bool get myTurn =>
      myIndex >= 0 &&
      myIndex == turnIndex &&
      (phase.startsWith('Turn') || phase.startsWith('Grace'));

  /// The clock has run out at least once this turn: the room is paused and
  /// somebody has to resume to start the shorter countdown.
  bool get _inGrace => phase.startsWith('Grace');

  /// The last chance — resuming starts a countdown that settles the game.
  bool get _lastChance => _inGrace && phase.endsWith('b');
  bool get finished => phase == 'Results';
  String label(String id) =>
      widget.nicknames[id] ?? (id.length > 6 ? id.substring(0, 6) : id);

  void _onEnvelope(Map<String, dynamic> env) {
    switch (env['type']) {
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
      final rawPlayers = p['players'] as List?;
      if (rawPlayers != null) {
        players = rawPlayers.map((e) => e.toString()).toList();
      }
      final rawOwner = p['owner'] as List?;
      if (rawOwner != null) owner = rawOwner.map((e) => e?.toString()).toList();
      final rawPits = p['pits'] as List?;
      if (rawPits != null) pits = rawPits.map((e) => e as int).toList();
      final rawLegal = p['legalPits'] as List?;
      if (rawLegal != null) {
        legalPits = rawLegal.map((e) => (e as num).toInt()).toList();
      }
      pitsPerPlayer = p['pitsPerPlayer'] as int? ?? pitsPerPlayer;
      final rawScores = p['scores'] as Map?;
      if (rawScores != null) {
        scores = rawScores.map((k, v) => MapEntry(k.toString(), v as int));
      }
      _paused = p['paused'] as bool? ?? _paused;
      final left = p['secondsLeft'] as int?;
      if (left != null) _secondsLeft = left;
      _spectatorsMuted = p['spectatorsMuted'] as bool? ?? _spectatorsMuted;
      _spectatorCount = p['spectatorCount'] as int? ?? _spectatorCount;
    });
  }

  void _applyPhase(Map<String, dynamic> p) {
    setState(() {
      phase = p['phase'] as String? ?? phase;
      round = p['round'] as int? ?? round;
      _actionLocked = false;
    });
    if (phase.startsWith('Turn')) _restartCountdown();
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        height: 42,
        child: Row(children: [
          Icon(icon, size: 18, color: const Color(0xffc9b18c)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xfff0d8a8), fontSize: 13),
            ),
          ),
        ]),
      );

  /// Same two switches as Draughts, and the same reasoning: wanting the
  /// board's own sounds without the music (or the reverse) is common, and
  /// both stick beyond this match.
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

  void _applyEvent(Map<String, dynamic> payload) {
    final type = payload['type'] as String;
    final data =
        ((payload['data'] as Map?) ?? const {}).cast<String, dynamic>();
    if (type == 'CHAT_MESSAGE') {
      _onChat(data);
      return;
    }
    switch (type) {
      case 'TURN_GRACE':
        setState(() => _graceSeconds = data['seconds'] as int? ?? 0);
        feed.insert(
            0,
            TableChatLine.system((data['lastChance'] as bool? ?? false)
                ? '${label(data['player']?.toString() ?? '')} ran out of time — last chance.'
                : '${label(data['player']?.toString() ?? '')} ran out of time — paused for them.'));
      case 'TURN_SKIPPED':
        feed.insert(
            0,
            TableChatLine.system(
                '${label(data['player']?.toString() ?? '')} ran out of chances and lost the turn.'));
      case 'COINS_AWARDED':
        setState(() => _coinsAwarded = data['amount'] as int?);
      case 'SPECTATOR_COUNT':
        setState(
            () => _spectatorCount = data['count'] as int? ?? _spectatorCount);
      case 'GAME_PAUSED':
        setState(() => _applyPause(true, data));
        feed.insert(
            0,
            TableChatLine.system(
                '${label(data['by']?.toString() ?? '')} paused the game.'));
      case 'GAME_RESUMED':
        setState(() => _applyPause(false, data));
        feed.insert(0, const TableChatLine.system('Game resumed.'));
      case 'SPECTATORS_MUTED':
        setState(() => _spectatorsMuted = true);
      case 'SPECTATORS_UNMUTED':
        setState(() => _spectatorsMuted = false);
      case 'GAME_STARTED':
        setState(() {
          players = (data['players'] as List).map((e) => e.toString()).toList();
          owner = (data['owner'] as List).map((e) => e?.toString()).toList();
          pits = (data['pits'] as List).map((e) => e as int).toList();
          pitsPerPlayer = 6;
          legalPits = ((data['legalPits'] as List?) ?? const [])
              .map((e) => (e as num).toInt())
              .toList();
          turnSeconds = data['turnSeconds'] as int? ?? turnSeconds;
          scores = {for (final pid in players) pid: 0};
        });
        _restartCountdown();
      case 'SOWN':
        final from = data['from'] as int;
        final touched = (data['touched'] as List).map((e) => e as int).toList();
        // `laps` splits the sowing at each point the hand scooped a pit up
        // and carried on. Older servers only sent the flat list, which is
        // one lap as far as the animation is concerned.
        final rawLaps = data['laps'] as List?;
        final laps = rawLaps == null
            ? [touched]
            : rawLaps
                .map((l) => (l as List).map((e) => e as int).toList())
                .toList();
        _sowAnimation =
            _animateSow(from, laps, const {}, data['by']?.toString() ?? '');
      case 'CAPTURED':
        final captured = ((data['pits'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList();
        final newScores = (data['scores'] as Map)
            .map((k, v) => MapEntry(k.toString(), v as int));
        () async {
          await _sowAnimation;
          if (!mounted) return;
          setState(() {
            for (final pit in captured) {
              final capturedCount = pits[pit];
              pits[pit] = 0;
              _flights.add(_CaptureFlight(
                  id: _nextFlightId++,
                  pit: pit,
                  owner: data['by']?.toString() ?? '',
                  count: capturedCount));
            }
            scores = newScores;
          });
          GameSfx.capture();
        }();
        feed.insert(
            0,
            TableChatLine.system(
                '${label(data['by']?.toString() ?? '')} captures ${data['count']} seeds'));
      case 'TURN_STARTED':
        setState(() {
          legalPits = ((data['legalPits'] as List?) ?? const [])
              .map((e) => (e as num).toInt())
              .toList();
          _actionLocked = false;
        });
      case 'GAME_OVER':
        setState(() {
          winningSide = data['winningSide'] as String?;
          winners = ((data['winners'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList();
          GameMusic.playOutcome(won: winners.contains(widget.selfId));
          final newScores = (data['scores'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v as int));
          if (newScores != null) scores = newScores;
        });
        _ticker?.cancel();
        feed.insert(
            0,
            TableChatLine.system(winners.length > 1
                ? "It's a tie!"
                : '${label(winners.isEmpty ? '' : winners.first)} wins!'));
    }
  }

  /// Replays the sowing the server just reported, one seed at a time.
  ///
  /// The hand lifts the chosen pit, moves along dropping a seed into each
  /// one. Captures are reported separately once the final seed lands, so the
  /// sow remains readable before captured seeds leave the opponent's row.
  ///
  /// Paced to be watchable rather than quick: about a second a seed, easing
  /// to half that once a relay runs long, since a twenty-five seed sowing at
  /// full pace would outstay its welcome.
  Future<void> _animateSow(int from, List<List<int>> laps,
      Map<String, int> captures, String sower) async {
    final token = ++_sowToken;
    if (!mounted) return;

    final drops = laps.fold<int>(0, (n, lap) => n + lap.length);
    final interval = drops > 8 ? 420 : 560;
    // The hand sets off first and the seed lands as it arrives, so the two
    // read as one movement. Animating them in parallel had the seed appear
    // while the hand was still travelling.
    _handTravel = Duration(milliseconds: (interval * 0.78).round());
    final dwell = Duration(milliseconds: interval - _handTravel.inMilliseconds);

    setState(() {
      pits[from] = 0; // the hand lifts the pit
      _handPit = from;
      _handInk = _inkFor(sower);
      _handPressed = true;
    });
    GameSfx.scoop();
    await Future.delayed(const Duration(milliseconds: 160));
    if (!mounted || token != _sowToken) return;

    for (var lapIndex = 0; lapIndex < laps.length; lapIndex++) {
      final lap = laps[lapIndex];
      final lastLap = lapIndex == laps.length - 1;

      for (var i = 0; i < lap.length; i++) {
        final pit = lap[i];
        // 1. the hand sets off for the next pit
        setState(() {
          _handPressed = false;
          _handPit = pit;
        });
        await Future.delayed(_handTravel);
        if (!mounted || token != _sowToken) return;
        // 2. it arrives, and the seed drops
        setState(() {
          pits[pit] = pits[pit] + 1;
          _pulsing.add(pit);
          _handPressed = true;
        });

        final capturedPit = captures['$lapIndex:$i'];
        if (capturedPit != null) {
          // That seed brought the pit to four — it goes to whoever sowed it.
          await Future.delayed(const Duration(milliseconds: 380));
          if (!mounted || token != _sowToken) return;
          setState(() {
            pits[capturedPit] = 0;
            _flights.add(_CaptureFlight(
                id: _nextFlightId++, pit: capturedPit, owner: sower, count: 4));
          });
          GameSfx.capture();
        } else if (lastLap && i == lap.length - 1) {
          GameSfx.settle(); // the seed that ends the turn
        } else {
          GameSfx.seed(i);
        }

        Future.delayed(const Duration(milliseconds: 260), () {
          if (mounted) setState(() => _pulsing.remove(pit));
        });

        // 3. a beat with the hand resting over the pit before it moves on
        await Future.delayed(dwell);
        if (!mounted || token != _sowToken) return;
      }

      if (!lastLap) {
        // The last seed landed on a pit that still had seeds, so the hand
        // takes the whole pit and keeps going.
        await Future.delayed(const Duration(milliseconds: 220));
        if (!mounted || token != _sowToken) return;
        setState(() => pits[lap.last] = 0);
        GameSfx.scoop();
      }
    }

    await Future.delayed(const Duration(milliseconds: 180));
    if (mounted && token == _sowToken) setState(() => _handPit = null);
  }

  /// Where a pit sits, in the coordinates of the whole board area — the
  /// strips included, since captured stones fly out to them.
  Offset _pitSpot(int pit, BoxConstraints box, List<int> order, bool strips) {
    final stackBox = _boardStackKey.currentContext?.findRenderObject();
    final pitBox = _pitKeys[pit].currentContext?.findRenderObject();
    if (stackBox is RenderBox &&
        pitBox is RenderBox &&
        stackBox.attached &&
        pitBox.attached) {
      final globalCenter =
          pitBox.localToGlobal(pitBox.size.center(Offset.zero));
      return stackBox.globalToLocal(globalCenter);
    }

    final top = strips ? _stripHeight : 0.0;
    final trayHeight = box.maxHeight - (strips ? _stripHeight * 2 : 0);
    for (var row = 0; row < order.length; row++) {
      final rowPlayer = players[order[row]];
      final rowPits = [
        for (var i = 0; i < 12; i++)
          if (owner[i] == rowPlayer) i
      ];
      if (rowPlayer != widget.selfId) {
        rowPits.setAll(0, rowPits.reversed.toList());
      }
      final at = rowPits.indexOf(pit);
      if (at < 0) continue;
      final rowHeight = trayHeight / order.length;
      return Offset(
        (at + 0.5) / rowPits.length * box.maxWidth,
        top + row * rowHeight + rowHeight * (strips ? 0.5 : 0.62),
      );
    }
    return Offset(box.maxWidth / 2, box.maxHeight / 2);
  }

  /// The strip a captured stone is heading for — yours below, theirs above.
  Offset _storeSpot(
      String playerId, BoxConstraints box, List<int> order, bool strips) {
    if (strips) {
      final mine = myIndex >= 0 && players[myIndex] == playerId;
      return Offset(box.maxWidth * 0.62,
          mine ? box.maxHeight - _stripHeight * 0.5 : _stripHeight * 0.5);
    }
    final row = order.indexWhere((idx) => players[idx] == playerId);
    final rowHeight = box.maxHeight / order.length;
    return Offset(
        box.maxWidth - 26, (row < 0 ? 0 : row) * rowHeight + rowHeight * 0.18);
  }

  /// The hand doing the sowing, sliding between pits so the eye can follow
  /// it, and tinted to whoever's turn it is.
  Widget _handOverlay(
      int pit, BoxConstraints box, List<int> order, bool strips) {
    final spot = _pitSpot(pit, box, order, strips);
    final rowPlayer = pit < owner.length ? owner[pit] : null;
    final row =
        order.indexWhere((playerIndex) => players[playerIndex] == rowPlayer);
    final reachesFromTop = row >= 0 && row < order.length / 2;
    return AnimatedPositioned(
      duration: _handTravel,
      curve: Curves.easeInOutCubic,
      left: spot.dx - 18,
      // Both hands now overlap the bowl. The far player's hand comes down
      // from above; the near player's reaches up from below.
      top: spot.dy + (reachesFromTop ? -28 : -8),
      child: IgnorePointer(
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          scale: _handPressed ? 0.88 : 1,
          child: Transform.rotate(
            angle: reachesFromTop ? math.pi : 0,
            child: Icon(Icons.back_hand_rounded,
                size: 36,
                color: _handInk,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 8)]),
          ),
        ),
      ),
    );
  }

  Widget _flightOverlay(
      _CaptureFlight flight, BoxConstraints box, List<int> order, bool strips) {
    final from = _pitSpot(flight.pit, box, order, strips);
    final to = _storeSpot(flight.owner, box, order, strips);
    final stone = _theme?.stone ?? goosiStonePalettes.first;

    return TweenAnimationBuilder<double>(
      key: ValueKey(flight.id),
      tween: Tween(begin: 0, end: 1),
      // Slow enough to watch the stones leave the board and arrive.
      duration: const Duration(milliseconds: 1250),
      curve: Curves.easeInOutCubic,
      onEnd: () {
        if (mounted) {
          setState(() => _flights.removeWhere((f) => f.id == flight.id));
        }
      },
      builder: (context, t, _) {
        return Stack(children: [
          // The captured stones leave together but land in sequence, so you
          // can count the same two or three stones the rule just awarded.
          for (var i = 0; i < flight.count; i++)
            _flyingStone(
                from, to, ((t - i * 0.10) / 0.70).clamp(0.0, 1.0), stone, i),
        ]);
      },
    );
  }

  Widget _flyingStone(
      Offset from, Offset to, double t, GoosiStonePalette stone, int index) {
    if (t <= 0) return const SizedBox.shrink();
    final x = from.dx + (to.dx - from.dx) * t;
    // A shallow arc reads as a throw rather than a slide.
    final y = from.dy + (to.dy - from.dy) * t - math.sin(t * math.pi) * 22;
    final colors = _seedColors(stone, index);
    return Positioned(
      left: x - 6,
      top: y - 6,
      child: Opacity(
        opacity: t >= 1 ? 0 : 1,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
                colors: [colors.top, colors.mid],
                center: const Alignment(-0.35, -0.45)),
            border: Border.all(color: colors.rim, width: 1),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black54, blurRadius: 3, offset: Offset(0, 1))
            ],
          ),
        ),
      ),
    );
  }

  /// Resuming out of the final grace starts a countdown that settles the
  /// game, so it asks first — accepting and then not playing is exactly
  /// what the dialog says it will do.
  Future<void> _resumeFromGrace() async {
    if (!_lastChance) {
      _togglePause();
      return;
    }
    final whose =
        turnIndex >= 0 && turnIndex < players.length ? players[turnIndex] : '';
    final mine = myIndex >= 0 && myIndex == turnIndex;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Last chance'),
        content: Text(mine
            ? 'Resume and you have $_graceSeconds seconds to sow. '
                "If you don't, the game is over."
            : 'Resume and ${label(whose)} has $_graceSeconds seconds to sow.'),
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

  /// The blurred cover over the board while the game is paused, doubling as
  /// the grace screen — the clock only starts when somebody presses Resume,
  /// which is what stops a grace being spent by a player who isn't there.
  Widget _pauseOverlay() {
    final mine = myIndex >= 0 && myIndex == turnIndex;
    final whose = turnIndex >= 0 && turnIndex < players.length
        ? label(players[turnIndex])
        : 'them';
    final (icon, title, body) = switch ((_inGrace, _lastChance, mine)) {
      (false, _, _) => (Icons.pause_circle_filled_rounded, 'PAUSED', null),
      (true, true, true) => (
          Icons.warning_amber_rounded,
          'LAST CHANCE',
          "Resume and you'll have $_graceSeconds seconds to sow, or the game is over.",
        ),
      (true, true, false) => (
          Icons.warning_amber_rounded,
          'LAST CHANCE',
          '$whose gets $_graceSeconds seconds once resumed.',
        ),
      (true, false, true) => (
          Icons.timer_off_rounded,
          "TIME'S UP",
          'Resume for another $_graceSeconds seconds.',
        ),
      (true, false, false) => (
          Icons.timer_off_rounded,
          "TIME'S UP",
          'Waiting for $whose — $_graceSeconds seconds once resumed.',
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
            NeonButton('Resume', onPressed: _resumeFromGrace),
          ]),
        ),
      ),
    );
  }

  void _tapPit(int pit) {
    if (!myTurn || _actionLocked || _paused) return;
    if (owner[pit] != widget.selfId || !legalPits.contains(pit)) {
      // Somebody else's pit, or an empty one — the board refuses the tap
      // and says so rather than just doing nothing.
      GameSfx.illegal();
      return;
    }
    GameSfx.select();
    setState(() => _actionLocked = true);
    widget.socket.send('PLAYER_ACTION', {
      'action': 'SOW',
      'data': {'pit': pit}
    });
  }

  void _togglePause() => widget.socket.send('PAUSE_TOGGLE');

  void _toggleMuteSpectators() => widget.socket.send('MUTE_SPECTATORS_TOGGLE');

  final Set<int> _pulsing = {};

  Future<void> _confirmExit() async {
    final hasAgent = widget.agents.isNotEmpty;
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xff241708),
        title: const Text('Leave the game?',
            style: TextStyle(color: Color(0xfff0d8a8))),
        content: Text(
            hasAgent
                ? 'A table with only a system Cyber Agent will end. Other tables can be rejoined with the huud code.'
                : 'You can rejoin with the huud code, but you\'ll stop receiving live updates until you do.',
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
      try {
        final endedBotTable =
            await app.api.post('/rooms/${widget.socket.roomId}/leave-goosi') ==
                true;
        if (endedBotTable || finished) {
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
      if (!mounted) return;
      widget.socket.close();
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell()), (r) => false);
    }
  }

  void _openThemeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff241708),
      builder: (_) => _GoosiThemeSheet(theme: _theme!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: finished,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: Row(children: [
            Text(finished ? 'RESULTS' : 'MACALA',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            if (!finished && widget.roomCode.isNotEmpty) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text('HUUD ${widget.roomCode}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: _gold)),
              ),
            ],
          ]),
          automaticallyImplyLeading: finished,
          backgroundColor: _bg,
          foregroundColor: _cream,
          // Only Pause earns a permanent button — it's the one thing you
          // reach for mid-game. Everything else is a once-a-match setting
          // and lives behind the gear.
          actions: finished
              ? null
              : [
                  GameVoiceControl(roomId: widget.socket.roomId),
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
                    color: _panel,
                    onSelected: (value) {
                      switch (value) {
                        case 'theme':
                          _openThemeSheet();
                        case 'music':
                          _toggleMusic();
                        case 'sfx':
                          _toggleSfx();
                        case 'spectators':
                          _toggleMuteSpectators();
                        case 'exit':
                          _confirmExit();
                      }
                    },
                    itemBuilder: (_) => [
                      if (_theme != null)
                        _menuItem(
                            'theme', Icons.palette_outlined, 'Board & stones'),
                      _menuItem(
                          'music',
                          _musicOn
                              ? Icons.music_note_rounded
                              : Icons.music_off_rounded,
                          _musicOn ? 'Mute music' : 'Play music'),
                      _menuItem(
                          'sfx',
                          _sfxOn
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          _sfxOn ? 'Mute game sounds' : 'Play game sounds'),
                      _menuItem(
                        'spectators',
                        _spectatorsMuted
                            ? Icons.comments_disabled_rounded
                            : Icons.chat_bubble_outline_rounded,
                        _spectatorsMuted
                            ? 'Let spectators comment'
                            : 'Mute spectator comments',
                      ),
                      _menuItem('exit', Icons.logout_rounded, 'Leave'),
                    ],
                  ),
                ],
        ),
        body: SafeArea(child: finished ? _results(context.neon) : _board()),
      ),
    );
  }

  /// Height of the captured-stone strip that sits above and below the
  /// board. The stones land on their owner's own side of the table, and
  /// keeping them out of the middle leaves the full width for the pits —
  /// which is what lets the holes be as large as they are.
  static const double _stripHeight = 76;

  /// One ink per seat, so the hand that's sowing is identifiably a player's.
  static const List<Color> _seatInks = [
    Color(0xffffd89a), // warm gold
    Color(0xffff9db3), // rose
    Color(0xff9ad0ff), // cool blue
    Color(0xffb9e4c0), // pale green
  ];

  Color _inkFor(String playerId) {
    final i = players.indexOf(playerId);
    return _seatInks[(i < 0 ? 0 : i) % _seatInks.length];
  }

  Widget _board() {
    final board = _theme?.board ?? goosiBoardPalettes.first;
    final n = players.length;
    if (n == 0) return const Center(child: CircularProgressIndicator());

    final order = <int>[];
    for (var i = 1; i < n; i++) {
      order.add((myIndex + i) % n);
    }
    if (myIndex >= 0) order.add(myIndex);

    // Two players get a strip each, above and below. More than two and
    // there's nowhere to put four of them, so those keep a store in each
    // row's header.
    final strips = n == 2 && myIndex >= 0;

    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
          child: LayoutBuilder(
            builder: (context, box) => Stack(key: _boardStackKey, children: [
              Column(children: [
                if (strips)
                  SizedBox(
                      height: _stripHeight, child: _storeStrip(order.first)),
                Expanded(
                  child: Center(
                    child: _WoodTray(
                      palette: board,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final idx in order)
                            _playerRow(idx, idx == myIndex,
                                showHeader: !strips),
                        ],
                      ),
                    ),
                  ),
                ),
                if (strips)
                  SizedBox(height: _stripHeight, child: _storeStrip(myIndex)),
              ]),

              // The sowing hand, sliding from pit to pit rather than
              // jumping, tinted to whoever is sowing.
              if (_handPit != null) _handOverlay(_handPit!, box, order, strips),

              // Captured stones fly out of the pit to their owner's strip,
              // so a capture is something you watch happen rather than a
              // number quietly changing.
              if (_flights.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Stack(
                      children: [
                        for (final f in _flights)
                          _flightOverlay(f, box, order, strips)
                      ],
                    ),
                  ),
                ),

              if (_paused) Positioned.fill(child: _pauseOverlay()),
            ]),
          ),
        ),
      ),
      _chromeBar(),
      TableChatPanel(
        lines: feed,
        controller: _chatController,
        onSend: _sendChat,
        spectatorCount: _spectatorCount,
        amSpectator: _amSpectator,
      ),
    ]);
  }

  /// A player's side of the table: who they are, whether the board is
  /// waiting on them, and the stones they've taken.
  Widget _storeStrip(int playerIndex) {
    final playerId = players[playerIndex];
    final active = playerIndex == turnIndex;
    final isMe = playerIndex == myIndex;
    final seconds = active ? (_secondsLeft ?? turnSeconds) : turnSeconds;
    return AnimatedContainer(
      key: ValueKey('goosi-player-$playerId'),
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
            color: active ? _gold : Colors.white.withValues(alpha: .12),
            width: active ? 2 : 1),
        boxShadow: active
            ? [BoxShadow(color: _gold.withValues(alpha: .24), blurRadius: 10)]
            : null,
      ),
      child: Row(children: [
        ValueListenableBuilder<Set<String>>(
          valueListenable: widget.socket.onlinePlayers,
          builder: (_, online, __) => OnlineAvatar(
            isMe ? 'You' : label(playerId),
            size: 45,
            online: online.contains(playerId),
            imageUrl: widget.avatars[playerId],
            emoji: widget.agents.contains(playerId) ? '🤖' : null,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isMe ? 'YOU' : label(playerId).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _cream,
                      fontSize: 15,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text('${scores[playerId] ?? 0} CAPTURED',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _gold, fontSize: 10, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _CapturedSeedsPile(
          key: ValueKey('macala-captured-$playerId'),
          count: scores[playerId] ?? 0,
          stone: _theme?.stone ?? goosiStonePalettes.first,
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xff160b1c),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
                color: active ? _gold : Colors.white.withValues(alpha: .16)),
          ),
          child: Text(_clock(seconds),
              style: const TextStyle(
                  color: _cream,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ),
      ]),
    );
  }

  String _clock(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  Widget _playerRow(int playerIndex, bool isMe, {bool showHeader = true}) {
    final playerId = players[playerIndex];
    final stone = _theme?.stone ?? goosiStonePalettes.first;
    final active = playerIndex == turnIndex;
    final myPits = <int>[];
    for (var i = 0; i < 12; i++) {
      if (owner[i] == playerId) myPits.add(i);
    }
    if (!isMe) {
      myPits.setAll(0, myPits.reversed.toList());
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // With a store at each end of the board the row carries no header —
        // who's who, and whose turn it is, live out at the stores.
        if (showHeader) ...[
          Row(children: [
            Text(isMe ? 'You' : label(playerId),
                style: TextStyle(
                    color: active
                        ? const Color(0xffe0a94a)
                        : const Color(0xffc9b18c),
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
            if (active) ...[
              const SizedBox(width: 6),
              Icon(Icons.circle,
                  size: 6,
                  color: const Color(0xffe0a94a).withValues(alpha: 0.9)),
            ],
            const Spacer(),
            _StoreTray(count: scores[playerId] ?? 0, stone: stone),
          ]),
          const SizedBox(height: 3),
        ],
        Row(
          children: [
            for (final pit in myPits)
              Expanded(
                child: GestureDetector(
                  key: ValueKey('goosi-pit-$pit'),
                  onTap: isMe ? () => _tapPit(pit) : null,
                  child: SizedBox(
                    key: _pitKeys[pit],
                    child: _PitBowl(
                      palette: (_theme?.board ?? goosiBoardPalettes.first),
                      stone: stone,
                      seeds: pits[pit],
                      tappable:
                          isMe && myTurn && !_paused && legalPits.contains(pit),
                      pulsing: _pulsing.contains(pit),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ]),
    );
  }

  Widget _chromeBar() {
    final activeName = turnIndex >= 0 && turnIndex < players.length
        ? label(players[turnIndex])
        : 'Waiting';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
              child: _controlButton(Icons.undo_rounded, 'Request undo',
                  () => _sendRequest('requests an undo.'))),
          const SizedBox(width: 5),
          Expanded(
              child: _controlButton(Icons.handshake_rounded, 'Offer draw',
                  () => _sendRequest('offers a draw.'))),
          const SizedBox(width: 5),
          Expanded(
              child: _controlButton(
                  Icons.help_outline_rounded, 'Rules', _showRules)),
          const SizedBox(width: 5),
          Expanded(
              child:
                  _controlButton(Icons.flag_rounded, 'Resign', _confirmResign)),
        ]),
        const SizedBox(height: 6),
        Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: myTurn ? _gold : const Color(0xff5b3158)),
          ),
          child: Text(
              myTurn ? 'YOUR TURN' : '$activeName TO PLAY'.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: myTurn ? _gold : _cream,
                  fontSize: 11,
                  fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }

  Widget _controlButton(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: _panel,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: SizedBox(
          height: 54,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 19, color: _gold),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _cream, fontSize: 8.5)),
          ]),
        ),
      ),
    );
  }

  void _sendRequest(String message) {
    widget.socket.send('CHAT_SEND', {'channel': 'table', 'text': message});
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request sent to your opponent.')));
  }

  void _showRules() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Macala rules'),
        content: const Text(
            'Choose one of your six houses and sow every seed counter-clockwise. '
            'If the final seed leaves 2 or 3 seeds in an opponent house, capture '
            'that house and consecutive 2-or-3 houses behind it. Feed an empty '
            'opponent row whenever possible. The first player past 24 wins.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it')),
        ],
      ),
    );
  }

  Future<void> _confirmResign() async {
    final resign = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resign this game?'),
        content: const Text('Your opponent will win this HUUD.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep playing')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Resign')),
        ],
      ),
    );
    if (resign == true) {
      widget.socket.send('PLAYER_ACTION', {'action': 'RESIGN', 'data': {}});
    }
  }

  /// Seeds taken, and by what margin — how a player would describe the
  /// result rather than just who took it.
  Widget _resultStats() {
    final mine = scores[widget.selfId];
    if (mine == null) return const SizedBox.shrink();
    final best = scores.entries
        .where((e) => e.key != widget.selfId)
        .map((e) => e.value)
        .fold<int>(0, (a, b) => b > a ? b : a);
    final margin = (mine - best).abs();
    return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          _statChip(
              Icons.circle_outlined, '$mine ${mine == 1 ? 'seed' : 'seeds'}'),
          if (margin > 0) _statChip(Icons.trending_up_rounded, 'by $margin'),
          if (_coinsAwarded != null)
            _statChip(Icons.monetization_on_rounded,
                '+$_coinsAwarded ${_coinsAwarded == 1 ? 'coin' : 'coins'}'),
        ]);
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
    final won = winners.contains(widget.selfId);
    final tie = winners.length > 1;
    return Stack(children: [
      // Only a win gets fireworks. Losing to a celebration would be a
      // strange thing to do to somebody.
      if (won && !tie) const Positioned.fill(child: Fireworks()),
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
              child:
                  Text(tie ? '🤝' : '🏆', style: const TextStyle(fontSize: 64)),
            ),
            const SizedBox(height: 10),
            Text(
                tie
                    ? "It's a tie"
                    : '${label(winners.isEmpty ? '' : winners.first)} wins',
                style: Theme.of(context)
                    .textTheme
                    .displayLarge
                    ?.copyWith(fontSize: 26, color: const Color(0xffe0a94a))),
            const SizedBox(height: 10),
            for (final pid in players)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                    '${pid == widget.selfId ? 'You' : label(pid)}: ${scores[pid] ?? 0} pts',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: n.mid)),
              ),
            const SizedBox(height: 6),
            Text(
                won
                    ? 'You won! 🎉'
                    : (tie ? 'Close one.' : 'Better luck next game.'),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: n.mid)),
            const SizedBox(height: 16),
            _resultStats(),
            const SizedBox(height: 24),
            if (won && !tie)
              VictoryShareButton(
                  roomId: widget.socket.roomId,
                  gameType: 'goosi',
                  detail: '${scores[widget.selfId] ?? 0} points'),
            NeonButton('Back to home', onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MainShell()),
                  (r) => false);
            }),
            const GuestSaveSessionCard(),
          ]),
        ),
      ),
    ]);
  }
}

/// Four stones on their way from a captured pit to a player's store.
class _CaptureFlight {
  const _CaptureFlight(
      {required this.id,
      required this.pit,
      required this.owner,
      required this.count});
  final int id;
  final int pit;
  final String owner;
  final int count;
}

/// A shallow well outside the board that keeps captured seeds visible. The
/// exact score remains beside the player's name; this pile makes captures
/// feel physical and gives the flight animation somewhere real to land.
class _CapturedSeedsPile extends StatelessWidget {
  const _CapturedSeedsPile(
      {super.key, required this.count, required this.stone});

  final int count;
  final GoosiStonePalette stone;

  @override
  Widget build(BuildContext context) {
    final drawn = math.min(count, 15);
    return Container(
      width: 72,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xff120916),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(children: [
          for (var i = 0; i < drawn; i++)
            Positioned(
              left: 7 + (i % 6) * 9.5 + (i ~/ 6) * 2,
              top: 7 + (i ~/ 6) * 9.5 + (i.isOdd ? 2 : 0),
              child: _CapturedSeed(stone: stone, index: i),
            ),
          if (count == 0)
            const Center(
              child: Text('EMPTY',
                  style: TextStyle(
                      color: Colors.white24,
                      fontSize: 8,
                      fontWeight: FontWeight.w800)),
            ),
          if (count > drawn)
            Positioned(
              right: 4,
              bottom: 3,
              child: Text('+${count - drawn}',
                  style: const TextStyle(
                      color: Color(0xffffcf66),
                      fontSize: 9,
                      fontWeight: FontWeight.w900)),
            ),
        ]),
      ),
    );
  }
}

class _CapturedSeed extends StatelessWidget {
  const _CapturedSeed({required this.stone, required this.index});

  final GoosiStonePalette stone;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = _seedColors(stone, index);
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
            colors: [colors.top, colors.mid],
            center: const Alignment(-0.35, -0.45)),
        border: Border.all(color: colors.rim, width: 0.8),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}

/// A player's captured stones, shown as stones rather than a bare number —
/// the pile is the score, and watching it grow is the point of taking them.
class _StoreTray extends StatelessWidget {
  const _StoreTray({required this.count, required this.stone});

  final int count;
  final GoosiStonePalette stone;

  /// Past this many the pile stops being countable at a glance, so the rest
  /// are summarised instead of drawn.
  static const _maxDrawn = 20;

  @override
  Widget build(BuildContext context) {
    final drawn = math.min(count, _maxDrawn);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(children: [
        if (count == 0)
          Text('no stones yet',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 11))
        else ...[
          Expanded(
            child: Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                for (var i = 0; i < drawn; i++)
                  Builder(builder: (context) {
                    final colors = _seedColors(stone, i);
                    return Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                            colors: [colors.top, colors.mid],
                            center: const Alignment(-0.35, -0.45)),
                        border: Border.all(color: colors.rim, width: 0.9),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black45,
                              blurRadius: 2,
                              offset: Offset(0, 1)),
                        ],
                      ),
                    );
                  }),
                if (count > _maxDrawn)
                  Text('+${count - _maxDrawn}',
                      style: const TextStyle(
                          color: Color(0xffe0a94a),
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('$count',
              style: const TextStyle(
                  color: Color(0xffe8d2ac),
                  fontSize: 15,
                  fontWeight: FontWeight.w900)),
        ],
      ]),
    );
  }
}

/// The carved wood tray the whole board sits in — one continuous slab
/// (unlike Draughts' alternating squares, Goosi's bowls are all the same
/// wood, just carved into it).
class _WoodTray extends StatelessWidget {
  const _WoodTray({required this.palette, required this.child});
  final GoosiBoardPalette palette;
  final Widget child;

  /// A live-edged plank isn't square, so its corners don't match.
  BorderRadius get _shape => palette.organicEdge
      ? BorderRadius.only(
          topLeft: Radius.circular(palette.radius + 16),
          topRight: Radius.circular(palette.radius - 4),
          bottomRight: Radius.circular(palette.radius + 22),
          bottomLeft: Radius.circular(palette.radius - 8),
        )
      : BorderRadius.circular(palette.radius);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: _shape,
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.frameTop, palette.frameBottom]),
        boxShadow: const [
          BoxShadow(
              color: Colors.black54, blurRadius: 20, offset: Offset(0, 10))
        ],
        // The worn plank has no frame around it at all; the others do.
        border: palette.organicEdge
            ? null
            : Border.all(color: palette.frameBottom, width: 3),
      ),
      child: ClipRRect(
        borderRadius: _shape,
        child: Stack(children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _WoodGrainPainter(
                base: palette.tray,
                grain:
                    Color.lerp(palette.tray, palette.trayGrain, palette.grain)!,
                seed: 11,
              ),
            ),
          ),
          // A lacquered surface catches the light in one diagonal band.
          if (palette.gloss)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.13),
                      Colors.transparent,
                    ],
                    stops: const [0.38, 0.47, 0.58],
                  ),
                ),
              ),
            ),
          // The hinge and its two pins, down the middle of a folding set.
          if (palette.hinge)
            const Positioned.fill(child: Center(child: _HingeLine())),
          // The rows are the only unpositioned child on purpose: a Stack
          // with nothing but Positioned.fill children expands to its
          // constraints, which stretched the tray down the screen and left
          // the holes pinned to the top of it. Sizing to the rows lets the
          // Center above actually centre them.
          child,
        ]),
      ),
    );
  }
}

/// The brass hinge of a travel set: a thin plate across the fold with a pin
/// at each end. Purely decorative — the board doesn't actually fold.
class _HingeLine extends StatelessWidget {
  const _HingeLine();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SizedBox(
        width: c.maxWidth,
        height: 8,
        child: Stack(children: [
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xffa37c46), Color(0xff7c5a30)],
                ),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black38,
                      blurRadius: 2,
                      offset: Offset(0, 1))
                ],
              ),
            ),
          ),
          for (final side in const [0.06, 0.94])
            Align(
              alignment: Alignment(side * 2 - 1, 0),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Color(0xfff0d9a8)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// One carved pit — a dark bowl set into the tray, holding a cluster of
/// round stones plus the live count. Tappable pits (your turn, your pit,
/// non-empty) get a soft glow; nothing shows what a tap *would* do beyond
/// that — sowing a pit is a single unambiguous action.
class _PitBowl extends StatelessWidget {
  const _PitBowl({
    required this.palette,
    required this.stone,
    required this.seeds,
    required this.tappable,
    required this.pulsing,
  });
  final GoosiBoardPalette palette;
  final GoosiStonePalette stone;
  final int seeds;
  final bool tappable;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          scale: pulsing ? 1.14 : 1.0,
          curve: Curves.easeOut,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.bowl,
              // A ringed board wears its collar at full weight; a plain
              // wooden one just has a lit lip on the near edge.
              border: Border.all(
                color: tappable
                    ? const Color(0xffe0a94a)
                    : (palette.ring ?? palette.bowlRim),
                width: tappable ? 2.4 : (palette.ring != null ? 2.4 : 1.6),
              ),
              boxShadow: [
                const BoxShadow(
                    color: Colors.black45, blurRadius: 6, offset: Offset(0, 3)),
                if (palette.ring != null && !tappable)
                  BoxShadow(
                      color: palette.ring!.withValues(alpha: 0.30),
                      blurRadius: 6,
                      spreadRadius: -1),
                if (tappable)
                  BoxShadow(
                      color: const Color(0xffe0a94a).withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: -1),
              ],
              gradient: RadialGradient(
                  colors: [palette.bowl, Colors.black.withValues(alpha: 0.5)],
                  radius: 0.9),
            ),
            alignment: Alignment.center,
            child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (seeds > 0)
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 2,
                      runSpacing: 2,
                      children: [
                        for (var i = 0; i < math.min(seeds, 8); i++)
                          Builder(builder: (context) {
                            final colors = _seedColors(stone, i);
                            return Container(
                              width: 13,
                              height: 13,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                    colors: [colors.top, colors.mid],
                                    center: const Alignment(-0.35, -0.45)),
                                border: Border.all(color: colors.rim, width: 1),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black54,
                                      blurRadius: 2,
                                      offset: Offset(0, 1)),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  // A small pill hanging off the top rim, clear of the bowl so
                  // the seeds inside stay visible, and short enough not to reach
                  // the pit above it. Gold at three — one more and the pit goes.
                  Align(
                    alignment: const Alignment(0, -1.14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 0.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                            width: 0.8),
                      ),
                      child: Text('$seeds',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                              height: 1.2)),
                    ),
                  ),
                ]),
          ),
        ),
      ),
    );
  }
}

typedef _SeedColors = ({Color top, Color mid, Color rim});

_SeedColors _seedColors(GoosiStonePalette stone, int index) {
  if (stone.id != 'river_stone') {
    return (top: stone.top, mid: stone.mid, rim: stone.rim);
  }
  return const [
    (top: Color(0xfffffff7), mid: Color(0xffddd5c3), rim: Color(0xff70685a)),
    (top: Color(0xff4a4d54), mid: Color(0xff111318), rim: Color(0xff050608)),
    (top: Color(0xff74d09a), mid: Color(0xff20875a), rim: Color(0xff0b422a)),
    (top: Color(0xff66cce0), mid: Color(0xff177e9b), rim: Color(0xff08465b)),
  ][index % 4];
}

class _WoodGrainPainter extends CustomPainter {
  const _WoodGrainPainter(
      {required this.base, required this.grain, required this.seed});
  final Color base;
  final Color grain;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    final rnd = math.Random(seed);
    const lines = 16;
    for (var i = 0; i < lines; i++) {
      final y = rnd.nextDouble() * size.height;
      final thickness = 0.6 + rnd.nextDouble() * 2.0;
      final alpha = 0.05 + rnd.nextDouble() * 0.1;
      final path = Path()..moveTo(0, y);
      const segments = 6;
      for (var s = 1; s <= segments; s++) {
        final x = size.width * s / segments;
        final wobble = (rnd.nextDouble() - 0.5) * size.height * 0.06;
        path.lineTo(x, (y + wobble).clamp(0, size.height));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = grain.withValues(alpha: alpha)
            ..strokeWidth = thickness
            ..style = PaintingStyle.stroke);
    }
    canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.2)
          ], radius: 0.95)
              .createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _WoodGrainPainter oldDelegate) =>
      oldDelegate.base != base ||
      oldDelegate.grain != grain ||
      oldDelegate.seed != seed;
}

/// Board wood tone + stone color pickers — per-device cosmetic preference,
/// same pattern (and same widget shape) as Draughts' `_BoardThemeSheet`.
class _GoosiThemeSheet extends StatelessWidget {
  const _GoosiThemeSheet({required this.theme});
  final GoosiThemeController theme;

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
                for (final p in goosiBoardPalettes) _boardSwatch(p)
              ]),
              const SizedBox(height: 24),
              const Text('STONE COLOR',
                  style: TextStyle(
                      color: Color(0xffe0a94a),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      fontSize: 12)),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final p in goosiStonePalettes) _stoneSwatch(p)
              ]),
            ]),
      ),
    );
  }

  Widget _boardSwatch(GoosiBoardPalette p) {
    final selected = theme.board.id == p.id;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => theme.setBoard(p),
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? const Color(0xffe0a94a) : Colors.white24,
              width: selected ? 2 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(p.organicEdge ? 10 : 6),
            child: Container(
              height: 40,
              color: p.tray,
              alignment: Alignment.center,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.bowl,
                  // The metal collar is the thing that tells the lacquered
                  // and brass boards apart at swatch size.
                  border: p.ring != null
                      ? Border.all(color: p.ring!, width: 2)
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(p.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(p.blurb,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 8.5, height: 1.25)),
        ]),
      ),
    );
  }

  Widget _stoneSwatch(GoosiStonePalette p) {
    final selected = theme.stone.id == p.id;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => theme.setStone(p),
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
          Container(
            height: 40,
            alignment: Alignment.center,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white70, width: 1.6),
                gradient: RadialGradient(colors: [p.top, p.mid]),
              ),
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
}
