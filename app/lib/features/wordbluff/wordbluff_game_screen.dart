import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/app_state.dart';
import '../../core/game_music.dart';
import '../../core/fuzzy_match.dart';
import '../../core/game_socket.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/motif.dart';
import '../../core/game_sfx.dart';
import '../../widgets/neon.dart';
import '../../widgets/table_chat.dart';
import '../../widgets/game_voice_control.dart';
import '../shell/main_shell.dart';
import '../../widgets/how_to_play_dialog.dart';
import '../onboarding/guest_save_session_card.dart';
import '../status/victory_status.dart';

/// The 20 wheel categories, in the exact order the backend's `Category` enum
/// declares them (`ta-game-wordbluff/.../Category.java`) — the wheel's slice
/// order has to match so a `CATEGORY_LANDED` slug points at the right slice.
const List<(String slug, String name, String emoji)> _kCategories = [
  ('animals', 'Animals', '🐾'),
  ('nature', 'Nature', '🌿'),
  ('current_affairs', 'Current Affairs', '📰'),
  ('movies_tv', 'Movies & TV', '🎬'),
  ('music', 'Music', '🎵'),
  ('food_drink', 'Food & Drink', '🍔'),
  ('sports', 'Sports', '⚽'),
  ('occupations', 'Occupations', '👷'),
  ('famous_faces', 'Famous Faces', '🌟'),
  ('places_landmarks', 'Places & Landmarks', '🗺️'),
  ('technology', 'Technology', '💻'),
  ('emotions_actions', 'Emotions & Actions', '🎭'),
  ('fictional_characters', 'Fictional Characters', '🦸'),
  ('everyday_objects', 'Everyday Objects', '🪑'),
  ('science', 'Science', '🔬'),
  ('history', 'History', '📜'),
  ('school_education', 'School & Education', '🎓'),
  ('travel_transport', 'Travel & Transport', '✈️'),
  ('clothing_fashion', 'Clothing & Fashion', '👗'),
  ('mixed', 'Mixed', '🎲'),
];

/// The Word Bluff game loop — spin, reveal, describe, guess — driven entirely
/// by server frames over the socket the lobby already opened, the same
/// contract shape as `GameScreen` (SNAPSHOT/PHASE/EVENT in, PLAYER_ACTION
/// out). See docs/DEV_REFERENCE.md §8 for the wire shapes this is built
/// against (`WordBluffModule`'s events and `commonView`).
class WordBluffGameScreen extends StatefulWidget {
  const WordBluffGameScreen({
    super.key,
    required this.socket,
    required this.selfId,
    required this.isHost,
    required this.nicknames,
    this.spectating = false,
  });

  final GameSocket socket;
  final String selfId;
  final bool isHost;
  final Map<String, String> nicknames;
  final bool spectating;

  @override
  State<WordBluffGameScreen> createState() => _WordBluffGameScreenState();
}

class _WordBluffGameScreenState extends State<WordBluffGameScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription? _sub;
  Timer? _ticker;
  late final AnimationController _wheelController;

  /// Where the wheel is resting, and the arc the current spin travels.
  /// Kept cumulative so a spin carries on from where the last one stopped
  /// instead of snapping back to zero first.
  double _wheelAngle = 0;
  double _spinFrom = 0;
  double _spinTo = 0;

  /// How hard the last flick was, 0.15 (a tap) to 1 (a proper throw). Sets
  /// both how long the wheel runs and how far it travels.
  double _spinPower = 0.4;

  /// Ratchet bookkeeping: the last slice the wheel crossed, and when it last
  /// clicked, so the crank can be throttled at speed.
  int _lastSlice = 0;
  DateTime _lastCrank = DateTime.fromMillisecondsSinceEpoch(0);

  /// The category the wheel has already animated to and announced this turn.
  /// A SNAPSHOT can legitimately arrive more than once mid-turn (a reconnect,
  /// or this screen's own initial HELLO racing the socket's), and it always
  /// carries the turn's still-active category — without this guard, each one
  /// would restart the wheel spin and re-arm the announce timer, which is
  /// exactly what left players stuck on "X is describing…" indefinitely
  /// while the actual game moved on underneath.
  String? _settledCategory;

  /// The hand-crank below the wheel: press and hold to wind it up, release to
  /// let it go. 0 (just pressed) to 1 (fully wound, ~1.4s), redrawn every
  /// frame while held so the dial visibly fills.
  double _chargeLevel = 0;
  DateTime? _chargeStart;
  Timer? _chargeTicker;
  static const _fullChargeMs = 1400;

  /// True while the landed category is being announced, before the words
  /// come up — step three of the turn.
  bool _announcing = false;
  Timer? _announceTimer;

  String phase = 'Turn';
  int round = 1;
  List<String> teamA = [];
  List<String> teamB = [];
  int teamAScore = 0;
  int teamBScore = 0;
  String turnTeam = 'A';
  String? describer;
  bool hasActiveCategory = false;
  bool hasActiveWord = false;
  String? category;
  String? categoryName;
  String? yourWord;
  int targetScore = 30;
  int turnSeconds = 60;
  String? winningTeam;
  String?
      lastResolved; // "correct" | "wrong" | "skipped", for the brief flash between words
  /// This turn's words and their provisional marks — the review round edits
  /// these, and only an accepted list becomes score.
  List<Map<String, dynamic>> attempts = [];
  int proposedScore = 0;
  List<String> reviewAccepted = [];
  final List<TableChatLine> feed = [];
  final TextEditingController _chatController = TextEditingController();
  int _spectatorCount = 0;
  bool _textMode = false;
  int _wordIndex = 0;

  bool _actionLocked = false;
  bool _spinning = false;
  bool _leaving = false;
  int? _secondsLeft;
  bool _musicOn = GameMusic.enabled;
  bool _sfxOn = GameSfx.enabled;
  bool _spectatorsMuted = false;

  // ---------------------------------------------------------------- voice auto-detect
  //
  // Runs on a judge's device, which already receives the private word and is
  // allowed to mark it. The guessing team's devices never receive the word.
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _speechInitAttempted = false;
  bool _listening = false;
  String _heardText = '';

  @override
  void initState() {
    super.initState();
    _wheelController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..addListener(_onWheelTick);
    GameSfx.warmUp();
    _sub = widget.socket.envelopes.listen(_onEnvelope);
    GameMusic.start(GameMusic.moodFor('wordbluff'));
    // Always 0 — see the comment on the equivalent call in
    // draughts_game_screen.dart: reusing widget.socket.lastSeq here can
    // make the server skip sending a full snapshot entirely.
    widget.socket.send('HELLO', {'lastSeq': 0});
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVoiceListening());
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.socket.close();
    _ticker?.cancel();
    _announceTimer?.cancel();
    _chargeTicker?.cancel();
    _wheelController.dispose();
    GameMusic.stop();
    _speech.stop();
    super.dispose();
  }

  bool get _shouldBeListening =>
      mounted &&
      !_textMode &&
      phase == 'Turn' &&
      amOpponent &&
      hasActiveWord &&
      yourWord != null &&
      !_actionLocked &&
      AppScope.of(context).voiceMatchEnabled;

  /// Call after any state change that might flip whether voice detection
  /// should be running — starts/stops it to match, rather than the caller
  /// having to know every path that can turn it on or off.
  Future<void> _syncVoiceListening() async {
    if (!mounted) return;
    if (_shouldBeListening) {
      await _startListening();
    } else if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
    }
  }

  Future<void> _startListening() async {
    if (_listening) return;
    if (!_speechInitAttempted) {
      _speechInitAttempted = true;
      try {
        _speechAvailable = await _speech.initialize(
          onError: (_) {
            if (mounted) setState(() => _listening = false);
          },
          onStatus: (status) {
            // The engine auto-stops after its pause/listen window; restart it
            // if we still ought to be listening (still the active word).
            if ((status == 'done' || status == 'notListening') && mounted) {
              setState(() => _listening = false);
              if (_shouldBeListening) _startListening();
            }
          },
        );
      } catch (_) {
        _speechAvailable = false;
      }
    }
    if (!_speechAvailable || !mounted || !_shouldBeListening) return;
    setState(() => _listening = true);
    try {
      await _speech.listen(
        onResult: _onSpeechResult,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          pauseFor: const Duration(seconds: 12),
          listenFor: const Duration(seconds: 55),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _listening = false);
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() => _heardText = result.recognizedWords);
    final word = yourWord;
    if (word == null || _actionLocked) return;
    if (isCloseMatch(result.recognizedWords, word,
        AppScope.of(context).voiceMatchThreshold)) {
      _speech.stop();
      setState(() => _listening = false);
      _mark(true);
    }
  }

  String label(String id) =>
      widget.nicknames[id] ?? (id.length > 6 ? id.substring(0, 6) : id);

  bool get amDescriber => describer == widget.selfId;
  bool get onMyTeam =>
      (turnTeam == 'A' ? teamA : teamB).contains(widget.selfId);
  bool get finished => phase == 'Results';

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
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
    }
  }

  void _applySnapshot(Map<String, dynamic> p) {
    // The server's own remaining time, so reconnecting mid-turn picks the
    // clock up where it actually is rather than handing out a fresh sixty
    // seconds.
    final serverSecondsLeft = p['secondsLeft'] as int?;
    setState(() {
      phase = p['phase'] as String? ?? phase;
      _textMode = p['textMode'] as bool? ?? _textMode;
      _wordIndex = p['wordIndex'] as int? ?? _wordIndex;
      round = p['round'] as int? ?? round;
      teamA = ((p['teamA'] as List?) ?? teamA).cast<String>();
      teamB = ((p['teamB'] as List?) ?? teamB).cast<String>();
      teamAScore = p['teamAScore'] as int? ?? teamAScore;
      teamBScore = p['teamBScore'] as int? ?? teamBScore;
      turnTeam = p['turnTeam'] as String? ?? turnTeam;
      describer = p['describer'] as String? ?? describer;
      hasActiveCategory = p['hasActiveCategory'] as bool? ?? hasActiveCategory;
      category =
          p['category'] as String? ?? (hasActiveCategory ? category : null);
      hasActiveWord = p['hasActiveWord'] as bool? ?? hasActiveWord;
      targetScore = p['targetScore'] as int? ?? targetScore;
      turnSeconds = p['turnSeconds'] as int? ?? turnSeconds;
      _spectatorCount = p['spectatorCount'] as int? ?? _spectatorCount;
      _spectatorsMuted = p['spectatorsMuted'] as bool? ?? _spectatorsMuted;
      attempts = ((p['attempts'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      proposedScore = p['proposedScore'] as int? ?? 0;
      reviewAccepted =
          ((p['reviewAccepted'] as List?) ?? const []).cast<String>();
      winningTeam = p['winningTeam'] as String? ?? winningTeam;
      yourWord = p['yourWord'] as String?;
      if (hasActiveCategory &&
          category != null &&
          category != _settledCategory) {
        categoryName = _nameOf(category!);
        if (p['clockStarted'] == true) {
          // A reconnect must show the live word, not replay the category spin.
          _settledCategory = category;
          _spinning = false;
          _clearAnnouncing();
        } else {
          _settleWheel(category!);
        }
      }
    });
    if (phase == 'Turn' &&
        p['clockStarted'] == true &&
        serverSecondsLeft != null) {
      _resumeCountdownFrom(serverSecondsLeft);
    }
    _syncVoiceListening();
  }

  void _applyPhase(Map<String, dynamic> p) {
    final next = p['phase'] as String;
    final wasWaitingForNextTurn =
        (phase == 'Review' || phase == 'Summary') && next == 'Turn';
    setState(() {
      phase = next;
      round = p['round'] as int? ?? round;
      _actionLocked = false;
      if (wasWaitingForNextTurn) {
        hasActiveCategory = false;
        hasActiveWord = false;
        category = null;
        categoryName = null;
        yourWord = null;
        lastResolved = null;
      }
    });
    // Deliberately NOT restarting the clock here. The orchestrator
    // broadcasts a PHASE frame after every action, so every spin, skip and
    // mark arrived as phase "Turn" and sent the countdown back to 60 — it
    // never reached zero. A turn begins on TURN_STARTED, and nowhere else.
    _syncVoiceListening();
  }

  /// Starts a fresh turn's clock at the full duration.
  void _restartCountdown() => _resumeCountdownFrom(turnSeconds);

  /// Picks the clock up at whatever the server says is left, which is what
  /// a snapshot carries — reconnecting mid-turn shouldn't hand anyone a
  /// fresh sixty seconds.
  void _resumeCountdownFrom(int seconds) {
    _ticker?.cancel();
    if (seconds <= 0) {
      setState(() => _secondsLeft = null);
      return;
    }
    setState(() => _secondsLeft = seconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        _secondsLeft = (_secondsLeft ?? 1) - 1;
        if (_secondsLeft! <= 0) t.cancel();
      });
    });
  }

  void _applyEvent(Map<String, dynamic> payload) {
    final type = payload['type'] as String;
    final data =
        ((payload['data'] as Map?) ?? const {}).cast<String, dynamic>();
    if (type == 'TEXT_CLUE' || type == 'TEXT_GUESS') {
      setState(() {
        _wordIndex = data['wordIndex'] as int? ?? _wordIndex;
        _actionLocked = false;
        feed.insert(
            0,
            TableChatLine(
                who: label(data['from']?.toString() ?? ''),
                text: type == 'TEXT_GUESS'
                    ? '${data['text']} · ${data['correct'] == true ? 'Correct!' : 'Try again'}'
                    : data['text']?.toString() ?? ''));
      });
      return;
    }
    if (type == 'CHAT_MESSAGE') {
      _onChat(data);
      return;
    }
    setState(() {
      switch (type) {
        case 'SPECTATOR_COUNT':
          _spectatorCount = data['count'] as int? ?? _spectatorCount;
        case 'SPECTATORS_MUTED':
          _spectatorsMuted = true;
        case 'SPECTATORS_UNMUTED':
          _spectatorsMuted = false;
        case 'GAME_STARTED':
          _textMode = data['textMode'] as bool? ?? _textMode;
          teamA = (data['teamA'] as List).cast<String>();
          teamB = (data['teamB'] as List).cast<String>();
          targetScore = data['targetScore'] as int? ?? targetScore;
          turnSeconds = data['turnSeconds'] as int? ?? turnSeconds;
        case 'TURN_STARTED':
          turnTeam = data['team'] as String;
          attempts = [];
          proposedScore = 0;
          reviewAccepted = [];
          describer = data['describer'] as String?;
          round = data['round'] as int? ?? round;
          hasActiveCategory = false;
          hasActiveWord = false;
          category = null;
          categoryName = null;
          yourWord = null;
          lastResolved = null;
          _spinning = false;
          _settledCategory = null;
          // The server starts this clock when the wheel selects a category.
          _ticker?.cancel();
          _secondsLeft = null;
        case 'CATEGORY_LANDED':
          category = data['category'] as String?;
          categoryName = data['categoryName'] as String?;
          hasActiveCategory = true;
          if (category != null) _settleWheel(category!);
        case 'TURN_CLOCK_STARTED':
          // A word can only be revealed/resolved (and the clock only starts)
          // once the announce beat is over — a stray late CATEGORY_LANDED
          // replay (e.g. a snapshot racing an event right after a reconnect)
          // must not leave the screen stuck showing "X is describing…" while
          // the game has already moved on underneath it.
          _clearAnnouncing();
          _restartCountdown();
        case 'WORD_REVEALED':
          _wordIndex = data['wordIndex'] as int? ?? _wordIndex;
          _clearAnnouncing();
          yourWord = data['word'] as String?;
          hasActiveWord = true;
        case 'WORD_ACTIVE':
          // The describer's own teammates never get WORD_REVEALED (no word
          // to hide from them, but no word to show them either) — this is
          // the only signal telling their screen a word actually went live.
          _clearAnnouncing();
          hasActiveWord = true;
        case 'WORD_RESOLVED':
          _wordIndex = data['wordIndex'] as int? ?? _wordIndex;
          _clearAnnouncing();
          lastResolved = data['result'] as String?;
          hasActiveWord = false;
          proposedScore = data['correctSoFar'] as int? ?? proposedScore;
          yourWord = null;
        case 'TURN_ENDED':
          // Scores don't move here any more — this hands the turn's words to
          // both teams for review (see WordBluffModule.endTurn).
          attempts = ((data['attempts'] as List?) ?? const [])
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
          proposedScore = data['proposedScore'] as int? ?? 0;
          reviewAccepted = [];
          teamAScore = data['teamAScore'] as int? ?? teamAScore;
          teamBScore = data['teamBScore'] as int? ?? teamBScore;
        case 'REVIEW_CORRECTED':
          final i = data['index'] as int?;
          if (i != null && i >= 0 && i < attempts.length) {
            attempts[i] = {
              ...attempts[i],
              'correct': data['correct'] == true,
              'skipped': false
            };
          }
          proposedScore = data['correctSoFar'] as int? ?? proposedScore;
          reviewAccepted = [];
        case 'REVIEW_ACCEPTED':
          reviewAccepted =
              ((data['accepted'] as List?) ?? const []).cast<String>();
        case 'TURN_COMMITTED':
          teamAScore = data['teamAScore'] as int? ?? teamAScore;
          teamBScore = data['teamBScore'] as int? ?? teamBScore;
        case 'GAME_OVER':
          winningTeam = data['winningTeam'] as String?;
          GameMusic.playOutcome(
              won: winningTeam != null &&
                  (winningTeam == 'A' ? teamA : teamB).contains(widget.selfId));
      }
      final line = _describe(type, data);
      if (line != null) feed.insert(0, TableChatLine.system(line));
    });
    _syncVoiceListening();
  }

  String? _describe(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'CATEGORY_LANDED':
        return 'Landed on ${data['categoryName']}.';
      case 'WORD_RESOLVED':
        return data['result'] == 'correct' ? 'Got it! ✅' : 'Skipped. ⏭️';
      case 'TURN_ENDED':
        return "Team ${data['team']}'s turn ends.";
      case 'GAME_OVER':
        return 'Team ${data['winningTeam']} wins!';
      default:
        return null;
    }
  }

  String _nameOf(String slug) => _kCategories
      .firstWhere((c) => c.$1 == slug, orElse: () => (slug, slug, '❓'))
      .$2;

  /// Clicks the ratchet once for each slice the wheel passes, so the crank
  /// slows down exactly as the wheel does. Throttled, because at full tilt
  /// it crosses a slice every few milliseconds and that reads as a buzz
  /// rather than a wheel.
  void _onWheelTick() {
    if (!_spinning) return;
    final t = Curves.easeOutQuart.transform(_wheelController.value);
    final angle = _spinFrom + (_spinTo - _spinFrom) * t;
    final slice = (angle / (2 * math.pi / _kCategories.length)).floor();
    if (slice == _lastSlice) return;
    _lastSlice = slice;
    final now = DateTime.now();
    if (now.difference(_lastCrank).inMilliseconds < 55) return;
    _lastCrank = now;
    GameSfx.crank();
  }

  /// Spins the wheel to the category the server picked.
  ///
  /// The old version eased twice — once in `animateTo` and again in the
  /// builder — and always rotated from zero, so it barely moved and snapped
  /// back between spins. This travels from wherever the wheel is resting,
  /// eases once, and runs for as long as the flick earned.
  void _settleWheel(String slug) {
    final idx = _kCategories.indexWhere((c) => c.$1 == slug);
    if (idx < 0) return;
    _settledCategory = slug;
    final sliceAngle = 2 * math.pi / _kCategories.length;

    // Where this slice has to end up under the fixed pointer at the top.
    final landing = -(idx * sliceAngle + sliceAngle / 2);
    final turns = 4 + (_spinPower * 8); // a tap gets 4 turns, a throw 12
    var delta = (landing - _wheelAngle) % (2 * math.pi);
    if (delta < 0) delta += 2 * math.pi;

    _spinFrom = _wheelAngle;
    _spinTo = _wheelAngle + turns * 2 * math.pi + delta;
    _wheelAngle = _spinTo;

    // 4 seconds for a nudge, 10 for a hard flick.
    _wheelController.duration =
        Duration(milliseconds: (4000 + _spinPower * 6000).round());
    _lastSlice = (_spinFrom / (2 * math.pi / _kCategories.length)).floor();
    setState(() => _spinning = true);
    _wheelController
      ..reset()
      ..forward().whenComplete(() {
        if (!mounted) return;
        GameSfx.wheelStop();
        // Step three: say what they're describing before any word appears.
        setState(() {
          _spinning = false;
          _announcing = true;
        });
        _announceTimer?.cancel();
        _announceTimer = Timer(const Duration(milliseconds: 2200), () {
          if (!mounted) return;
          setState(() => _announcing = false);
          if (amDescriber && phase == 'Turn' && _secondsLeft == null) {
            _sendAction('START_TURN_CLOCK');
          }
        });
      });
  }

  /// Ends the announce beat immediately, whatever triggered it — called from
  /// every event that can only happen after it (see the call sites), always
  /// from inside `_applyEvent`'s own `setState`, so this just mutates the
  /// field rather than wrapping another `setState` around it.
  void _clearAnnouncing() {
    _announceTimer?.cancel();
    _announcing = false;
  }

  /// A flick on the wheel. The harder it's thrown, the longer it runs —
  /// [velocity] is in pixels per second, straight off the gesture.
  void _spinWithPower(double velocity) {
    if (_actionLocked || _spinning || !amDescriber) return;
    _spinPower = (velocity.abs() / 3500).clamp(0.15, 1.0);
    _sendAction('SPIN');
  }

  /// Starts winding the crank up. Ticks its own clock (rather than riding
  /// the animation controller, which isn't running yet) so the dial fills
  /// smoothly while a finger is just sitting there holding it down.
  void _startCrank() {
    if (_actionLocked || _spinning || !amDescriber) return;
    _chargeStart = DateTime.now();
    _chargeTicker?.cancel();
    _chargeTicker = Timer.periodic(const Duration(milliseconds: 16), (t) {
      final start = _chargeStart;
      if (start == null) {
        t.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final level = (elapsed / _fullChargeMs).clamp(0.0, 1.0);
      setState(() => _chargeLevel = level);
      if (level >= 1.0) t.cancel();
    });
    setState(() =>
        _chargeLevel = 0.001); // gives the dial an immediate nudge on press
  }

  /// Lets go — how long it was held becomes the spin's power, same scale a
  /// hard flick would give it.
  void _releaseCrank() {
    _chargeTicker?.cancel();
    final start = _chargeStart;
    _chargeStart = null;
    if (start == null) return;
    final heldMs = DateTime.now().difference(start).inMilliseconds;
    setState(() => _chargeLevel = 0);
    if (_actionLocked || _spinning || !amDescriber) return;
    final level = (heldMs / _fullChargeMs).clamp(0.0, 1.0);
    _spinWithPower(500 + level * 3000);
  }

  void _cancelCrank() {
    _chargeTicker?.cancel();
    _chargeStart = null;
    if (mounted) setState(() => _chargeLevel = 0);
  }

  void _sendAction(String action, [Map<String, dynamic>? data]) {
    if (_amSpectator || _actionLocked || !widget.socket.isConnected) return;
    setState(() => _actionLocked = true);
    widget.socket.send(
        'PLAYER_ACTION', {'action': action, if (data != null) 'data': data});
    _syncVoiceListening(); // an in-flight action means it's about to stop being our turn to listen
  }

  /// Only the opposing team may judge a word — see `WordBluffModule.mark`.
  /// The describing side can't award itself points; that's the whole reason
  /// marking moved off the describer.
  bool get amOpponent => !_amSpectator && !onMyTeam;

  void _mark(bool correct) {
    final word = yourWord;
    if (word == null) return;
    _sendAction('MARK', {'correct': correct, 'word': word});
  }

  void _toggleAttempt(int index) {
    if (_amSpectator || phase != 'Review') return;
    if (!widget.socket.isConnected) return;
    widget.socket.send('PLAYER_ACTION', {
      'action': 'REVIEW_TOGGLE',
      'data': {'index': index},
    });
  }

  void _acceptReview() {
    if (_amSpectator || phase != 'Review') return;
    if (!widget.socket.isConnected) return;
    widget.socket.send('PLAYER_ACTION', {'action': 'REVIEW_ACCEPT'});
  }

  void _showHelp() {
    showHowToPlay(
      context,
      emoji: '🎡',
      title: 'Word Bluff',
      tagline: 'Two teams take turns describing words without saying them — '
          'guess fast before the clock runs out.',
      steps: [
        "When it's your turn, hold the crank to spin the wheel — the longer you hold, the harder it spins.",
        _textMode
            ? 'With bots at the table, type clues in the text box without naming the word. Your bot partner guesses from your clues.'
            : 'The wheel picks a category and your first word appears — describe it out loud without saying the word itself.',
        _textMode
            ? 'When your partner describes, read their clue and type your guess. Correct answers count toward the round review.'
            : 'Your teammates shout their guesses; the other team decides if your partner got it right or wrong.',
        'Stuck on a word? Skip it — it moves straight to the next one.',
        "When the clock runs out, everyone reviews the round's calls together before the score locks in.",
        'First team to reach the target score wins.',
      ],
    );
  }

  Future<void> _toggleMusic() async {
    final next = !_musicOn;
    await GameMusic.setEnabled(next);
    if (mounted) setState(() => _musicOn = next);
  }

  Future<void> _toggleSfx() async {
    final next = !_sfxOn;
    await GameSfx.setEnabled(next);
    if (mounted) setState(() => _sfxOn = next);
  }

  void _toggleMuteSpectators() {
    if (!widget.socket.isConnected) return;
    widget.socket.send('MUTE_SPECTATORS_TOGGLE');
  }

  PopupMenuItem<String> _menuItem(
          NeonColors n, String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        height: 42,
        child: Row(children: [
          Icon(icon, size: 18, color: n.gold),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: n.ink, fontSize: 13)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: finished || widget.spectating,
      child: Scaffold(
        appBar: AppBar(
          title: Text(finished ? 'Results' : 'Round $round'),
          automaticallyImplyLeading: finished || widget.spectating,
          // Always reachable, deliberately. The review waits on both teams
          // and has no clock, so a table that stops responding used to
          // leave no way out at all.
          actions: [
            if (!finished)
              GameVoiceControl(
                roomId: widget.socket.roomId,
                socket: widget.socket,
                selfId: widget.selfId,
                nicknames: widget.nicknames,
                spectating: _amSpectator,
              ),
            PopupMenuButton<String>(
              tooltip: 'Game settings',
              icon: const Icon(Icons.settings_rounded),
              onSelected: (value) {
                switch (value) {
                  case 'help':
                    _showHelp();
                  case 'music':
                    _toggleMusic();
                  case 'sfx':
                    _toggleSfx();
                  case 'spectators':
                    _toggleMuteSpectators();
                  case 'forfeit':
                    _confirmForfeit();
                  case 'leave':
                    _confirmExit();
                }
              },
              itemBuilder: (_) => [
                _menuItem(context.neon, 'help', Icons.help_outline_rounded,
                    'How to play'),
                _menuItem(
                    context.neon,
                    'music',
                    _musicOn
                        ? Icons.music_note_rounded
                        : Icons.music_off_rounded,
                    _musicOn ? 'Mute music' : 'Play music'),
                _menuItem(
                    context.neon,
                    'sfx',
                    _sfxOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                    _sfxOn ? 'Mute game sounds' : 'Play game sounds'),
                if (!_amSpectator)
                  _menuItem(
                      context.neon,
                      'spectators',
                      _spectatorsMuted
                          ? Icons.comments_disabled_rounded
                          : Icons.chat_bubble_outline_rounded,
                      _spectatorsMuted
                          ? 'Let spectators comment'
                          : 'Mute spectator comments'),
                if (!finished && !_amSpectator)
                  _menuItem(context.neon, 'forfeit', Icons.flag_outlined,
                      'End game · forfeit'),
                _menuItem(
                    context.neon, 'leave', Icons.logout_rounded, 'Leave game'),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
                child: GameBackdropMotifs(
                    gold: context.neon.gold,
                    brand: context.neon.brand,
                    jade: context.neon.jade)),
            SafeArea(
              // Laid out under the stage rather than floating over it — as
              // an overlay the panel sat on top of the wheel.
              child: Column(children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: KeyedSubtree(
                        key: ValueKey(phase), child: _phaseBody(context.neon)),
                  ),
                ),
                if (!finished)
                  TableChatPanel(
                    lines: feed,
                    controller: _chatController,
                    onSend: _sendChat,
                    spectatorCount: _spectatorCount,
                    amSpectator: _amSpectator,
                    initiallyExpanded: _textMode && !_amSpectator,
                    composerHint: !_textMode || _amSpectator
                        ? null
                        : amDescriber
                            ? 'Describe your word without naming it…'
                            : onMyTeam
                                ? 'Type your guess…'
                                : 'Discuss the round…',
                    emptyHint: _textMode
                        ? 'Clues and guesses appear here. Bots play through text.'
                        : null,
                    // An agent's clue is a sentence or two, and it's the
                    // thing the guessing team is reading — at 96 it scrolled
                    // out of sight almost as it arrived.
                    height: MediaQuery.sizeOf(context).height < 600 ? 48 : 132,
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmExit() async {
    if (widget.spectating) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this game?'),
        content: const Text(
            'The round carries on without you, and you lose any points still waiting on the review. '
            'A table with only system Cyber Agents will end.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Stay')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Leave')),
        ],
      ),
    );
    if (leave == true && mounted && !_leaving) {
      _leaving = true;
      final app = AppScope.of(context);
      try {
        final endedBotTable = await app.api
                .post('/rooms/${widget.socket.roomId}/leave-wordbluff') ==
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
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell()), (r) => false);
    }
  }

  Future<void> _confirmForfeit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End the game?'),
        content: const Text('Your team forfeits and the other team wins.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep playing')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Forfeit')),
        ],
      ),
    );
    if (confirmed == true && widget.socket.isConnected) _sendAction('FORFEIT');
  }

  Widget _phaseBody(NeonColors n) {
    return switch (phase) {
      'Turn' => _turn(n),
      'Review' => _review(n),
      'Summary' => _review(n),
      'Results' => _results(n),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  // ---------------------------------------------------------------- Turn

  /// Spectators talk on the muteable `spectate` channel, players on
  /// `table` — same box either way.
  bool get _amSpectator =>
      widget.spectating ||
      (!teamA.contains(widget.selfId) && !teamB.contains(widget.selfId));

  void _sendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    if (_textMode &&
        !_amSpectator &&
        phase == 'Turn' &&
        hasActiveWord &&
        (amDescriber || onMyTeam)) {
      _sendAction(amDescriber ? 'TEXT_CLUE' : 'TEXT_GUESS',
          {'text': text, 'wordIndex': _wordIndex});
      _chatController.clear();
      return;
    }
    widget.socket.send('CHAT_SEND',
        {'channel': _amSpectator ? 'spectate' : 'table', 'text': text});
    _chatController.clear();
  }

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

  Widget _turn(NeonColors n) {
    return Column(
      children: [
        _scoreboard(n),
        Expanded(
          // The turn runs in four beats: the wheel, the spin, the category
          // being announced, then the words themselves.
          child: !hasActiveCategory || _spinning
              ? _spinStage(n)
              : _announcing
                  ? _announceStage(n)
                  : !hasActiveWord
                      ? _revealStage(n)
                      : _guessStage(n),
        ),
      ],
    );
  }

  Widget _scoreboard(NeonColors n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
          color: n.panel, border: Border(bottom: BorderSide(color: n.line))),
      child: Row(children: [
        _teamBox(n, 'Team A', teamA, teamAScore,
            active: turnTeam == 'A', accent: n.gold),
        const SizedBox(width: 10),
        Column(children: [
          Text('to $targetScore',
              style: TextStyle(
                  color: n.mute,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6)),
          if (_secondsLeft != null) ...[
            const SizedBox(height: 4),
            Text('$_secondsLeft s',
                style: TextStyle(
                    color: _secondsLeft! <= 10 ? n.danger : n.jade,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ]),
        const SizedBox(width: 10),
        _teamBox(n, 'Team B', teamB, teamBScore,
            active: turnTeam == 'B', accent: n.brand),
      ]),
    );
  }

  /// A team, with the people actually on it. Whoever is describing lights
  /// up green — with four seats at the table it was otherwise impossible to
  /// tell who the game was waiting on.
  Widget _teamBox(NeonColors n, String name, List<String> members, int score,
      {required bool active, required Color accent}) {
    const turnGreen = Color(0xff4ade80);
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 9),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.14) : n.plate,
          borderRadius: BorderRadius.circular(NeonRadius.control),
          border: Border.all(
              color: active ? accent : kCabinetInk, width: active ? 1.8 : 1.2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: active ? accent : n.mute,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1))),
            const SizedBox(width: 2),
            Text('$score',
                style: TextStyle(
                    color: n.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 6),
          for (final id in members)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: id == describer ? turnGreen : Colors.transparent,
                      width: 1.6,
                    ),
                    boxShadow: id == describer
                        ? [
                            BoxShadow(
                                color: turnGreen.withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: -1)
                          ]
                        : null,
                  ),
                  child: ValueListenableBuilder<Set<String>>(
                    valueListenable: widget.socket.onlinePlayers,
                    builder: (_, online, __) => OnlineAvatar(
                        id == widget.selfId ? 'You' : label(id),
                        size: 18,
                        imageUrl: widget.socket.memberAvatars[id],
                        voiceIdentity: id,
                        online: online.contains(id)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    id == widget.selfId ? 'You' : label(id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: id == describer ? turnGreen : n.mid,
                      fontSize: 10.5,
                      fontWeight:
                          id == describer ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (id == describer)
                  const Icon(Icons.campaign_rounded,
                      size: 12, color: turnGreen),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _spinStage(NeonColors n) {
    final mine = amDescriber;
    return LayoutBuilder(builder: (context, box) {
      final compact = box.maxHeight < 300;
      final wheelSize = math
          .min(box.maxWidth - 8, box.maxHeight - (compact ? 72 : 96))
          .clamp(96.0, 560.0);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(children: [
          Text(
            mine
                ? 'Your turn to describe'
                : '${label(describer ?? "")} is spinning…',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .displayLarge
                ?.copyWith(fontSize: compact ? 17 : 20),
          ),
          if (!compact) ...[
            const SizedBox(height: 4),
            Text(
              mine
                  ? (_spinning
                      ? 'Round it goes…'
                      : 'Hold the crank — the longer you hold, the harder it spins. Or just flick the wheel.')
                  : (onMyTeam
                      ? 'Get ready to guess!'
                      : "It's the other team's turn."),
              textAlign: TextAlign.center,
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(color: n.mid),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(height: wheelSize, child: Center(child: _wheel(n))),
          if (mine) ...[
            const SizedBox(height: 10),
            _crankControl(n),
          ],
        ]),
      );
    });
  }

  /// The wheel, as big as the space allows. Flick it to spin — how hard you
  /// throw it decides how long it runs — or tap for a gentle one.
  Widget _wheel(NeonColors n) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = math
            .min(
              box.maxWidth,
              box.maxHeight.isFinite ? box.maxHeight : box.maxWidth,
            )
            .clamp(96.0, 560.0);
        return GestureDetector(
          onPanEnd: (d) => _spinWithPower(d.velocity.pixelsPerSecond.distance),
          onTap: () => _spinWithPower(700),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(alignment: Alignment.center, children: [
              AnimatedBuilder(
                animation: _wheelController,
                builder: (context, _) {
                  // One easing, applied here; the controller runs linear.
                  // Easing in both places was why it barely moved.
                  final t =
                      Curves.easeOutQuart.transform(_wheelController.value);
                  final angle = _spinning
                      ? _spinFrom + (_spinTo - _spinFrom) * t
                      : _wheelAngle;
                  return Transform.rotate(
                    angle: angle,
                    child: CustomPaint(
                      size: Size(size, size),
                      painter: _WheelPainter(
                          categories: _kCategories,
                          panel: n.panel,
                          line: kCabinetInk,
                          ink: n.ink),
                    ),
                  );
                },
              ),
              // The pointer stays put at the top; the wheel turns under it.
              Positioned(
                  top: -2,
                  child: Icon(Icons.arrow_drop_down_rounded,
                      size: 46, color: n.gold)),
            ]),
          ),
        );
      },
    );
  }

  /// The hand-crank: hold it down to wind the dial up, let go to spin. A
  /// tap-and-release barely charges it (a gentle nudge); holding the full
  /// ~1.4 seconds sends the wheel round as hard as a good flick would.
  Widget _crankControl(NeonColors n) {
    final charging = _chargeStart != null;
    final label = _spinning
        ? 'Spinning…'
        : charging
            ? (_chargeLevel >= 1.0 ? 'Full power — let go!' : 'Winding up…')
            : 'Hold to spin';
    return GestureDetector(
      onTapDown: (_) => _startCrank(),
      onTapUp: (_) => _releaseCrank(),
      onTapCancel: _cancelCrank,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 84,
          height: 84,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 84,
              height: 84,
              child: CircularProgressIndicator(
                value: _spinning ? null : (charging ? _chargeLevel : 0),
                strokeWidth: 5,
                backgroundColor: n.line,
                valueColor: AlwaysStoppedAnimation(
                    Color.lerp(n.gold, n.brand, charging ? _chargeLevel : 0) ??
                        n.gold),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 60 + (charging ? _chargeLevel * 6 : 0),
              height: 60 + (charging ? _chargeLevel * 6 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: n.plate,
                border: Border.all(color: n.gold, width: 1.4),
              ),
              child: Transform.rotate(
                // The gear winds with the charge — a visible sign the hold is
                // registering, not just a static icon sitting there.
                angle: (charging ? _chargeLevel : 0) * math.pi,
                child: Icon(Icons.settings_rounded, color: n.gold, size: 30),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: n.mid, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _revealStage(NeonColors n) {
    final emoji = _kCategories
        .firstWhere((c) => c.$1 == category, orElse: () => ('', '', '❓'))
        .$3;
    if (amDescriber) {
      return _centered([
        Text(emoji, style: const TextStyle(fontSize: 56)),
        const SizedBox(height: 10),
        Text(categoryName ?? '',
            style: Theme.of(context)
                .textTheme
                .displayLarge
                ?.copyWith(fontSize: 26)),
        const SizedBox(height: 8),
        Text('Reveal your word and start describing.',
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid)),
        const SizedBox(height: 20),
        NeonButton('Reveal word',
            onPressed: _actionLocked ? null : () => _sendAction('REVEAL')),
      ]);
    }
    return _centered([
      Text(emoji, style: const TextStyle(fontSize: 56)),
      const SizedBox(height: 10),
      Text(categoryName ?? '',
          style:
              Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 26)),
      const SizedBox(height: 8),
      Text('${label(describer ?? "")} is about to describe…',
          style:
              Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid)),
    ]);
  }

  /// Step three: the wheel has stopped, so say plainly what this turn is
  /// about before any word appears.
  Widget _announceStage(NeonColors n) {
    final cat = _kCategories.firstWhere(
      (c) => c.$1 == category,
      orElse: () => ('', categoryName ?? '', '🎲'),
    );
    return _centered([
      Text(
          amDescriber
              ? 'YOU ARE DESCRIBING'
              : '${label(describer ?? "")} IS DESCRIBING',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: n.mute,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2)),
      const SizedBox(height: 18),
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 520),
        curve: Curves.elasticOut,
        builder: (_, t, child) =>
            Transform.scale(scale: 0.7 + 0.3 * t, child: child),
        child: Column(children: [
          Text(cat.$3, style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 10),
          Text(cat.$2,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .displayLarge
                  ?.copyWith(fontSize: 30, color: n.gold)),
        ]),
      ),
      const SizedBox(height: 18),
      Text(amDescriber ? 'Get ready…' : 'Listen out for the clues.',
          style:
              Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid)),
    ]);
  }

  Widget _guessStage(NeonColors n) {
    if (amDescriber) {
      return _centered([
        Text(categoryName ?? '',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: n.mute, letterSpacing: 2)),
        const SizedBox(height: 10),
        // A deck: the word you're on, with the rest of the pile showing
        // behind it. Skipping deals the next card.
        SizedBox(
          height: 130,
          child: Stack(alignment: Alignment.center, children: [
            for (final depth in const [2, 1])
              Transform.translate(
                offset: Offset(depth * 7.0, depth * 7.0),
                child: Transform.rotate(
                  angle: depth * 0.025,
                  child: Container(
                    width: 232 - depth * 14.0,
                    height: 104,
                    decoration: BoxDecoration(
                      color: n.plate.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(NeonRadius.card),
                      border: Border.all(color: n.line),
                    ),
                  ),
                ),
              ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position:
                      Tween(begin: const Offset(0.18, -0.08), end: Offset.zero)
                          .animate(anim),
                  child: child,
                ),
              ),
              child: Container(
                key: ValueKey(yourWord),
                width: 246,
                height: 112,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: n.plate,
                  borderRadius: BorderRadius.circular(NeonRadius.card),
                  border: Border.all(color: n.jade, width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: n.jade.withValues(alpha: 0.3),
                        blurRadius: 24,
                        spreadRadius: -4)
                  ],
                ),
                child: FittedBox(
                  child: Text(yourWord ?? '…',
                      style: Theme.of(context)
                          .textTheme
                          .displayLarge
                          ?.copyWith(fontSize: 32, color: n.jade)),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Text(
            _textMode
                ? 'Type a clue below — do not name the word!'
                : "Don't say the word — describe it!",
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid)),
        const SizedBox(height: 24),
        // No "Got it" here any more — the other team calls it. All the
        // describer can do is give up on a word.
        NeonButton('Skip this word',
            style: NeonStyle.ghost,
            onPressed: _actionLocked ? null : () => _sendAction('SKIP')),
        const SizedBox(height: 8),
        Text(
            _textMode
                ? 'Correct text guesses count toward the round review.'
                : 'The other team decides if your partner got it.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: n.mute)),
      ]);
    }
    return _centered([
      const Text('🤔', style: TextStyle(fontSize: 56)),
      const SizedBox(height: 12),
      Text(
          onMyTeam
              ? (_textMode ? 'Type your guesses below!' : 'Shout your guesses!')
              : 'You\'re judging this one',
          style:
              Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 22)),
      const SizedBox(height: 8),
      Text(
          '${label(describer ?? "")} is describing a ${categoryName ?? ''} word.',
          textAlign: TextAlign.center,
          style:
              Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid)),
      // The judging team is shown the word — they can't call an attempt
      if (_textMode && onMyTeam && hasActiveWord) ...[
        const SizedBox(height: 12),
        NeonButton('Ask for another word',
            style: NeonStyle.ghost,
            onPressed: _actionLocked
                ? null
                : () => _sendAction('TEXT_SKIP', {'wordIndex': _wordIndex})),
      ],
      // right or wrong without it. The describer's own team never sees this
      // block, because guessing it is their job.
      if (amOpponent && hasActiveWord && yourWord != null) ...[
        const SizedBox(height: 18),
        Text('THEY ARE DESCRIBING',
            style: TextStyle(
                color: n.mute,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 2)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            color: n.plate.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(NeonRadius.card),
            border: Border.all(color: n.gold, width: 2),
          ),
          child: Text(yourWord!,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .displayLarge
                  ?.copyWith(fontSize: 26, color: n.gold)),
        ),
        const SizedBox(height: 6),
        Text('Keep it to yourself — just say whether they got it.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: n.mute)),
        if (AppScope.of(context).voiceMatchEnabled) ...[
          const SizedBox(height: 14),
          _voiceIndicator(n),
        ],
      ],
      // The opposing team holds the verdict — first opponent to press wins,
      // and anything mis-called gets fixed in the review round.
      if (amOpponent && hasActiveWord) ...[
        const SizedBox(height: 22),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Expanded(
              child: NeonButton('Wrong',
                  style: NeonStyle.ghost,
                  onPressed: _actionLocked ? null : () => _mark(false))),
          const SizedBox(width: 12),
          Expanded(
              child: NeonButton('Correct ✅',
                  onPressed: _actionLocked ? null : () => _mark(true))),
        ]),
        const SizedBox(height: 8),
        Text('Did they get it? Your call.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: n.mute)),
      ],
      if (lastResolved != null) ...[
        const SizedBox(height: 14),
        Text(
            switch (lastResolved) {
              'correct' => '✅ Correct!',
              'wrong' => '❌ Not it',
              _ => '⏭️ Skipped',
            },
            style: TextStyle(color: n.mute)),
      ],
    ]);
  }

  /// The review round: both teams look at the same list, either side can
  /// correct a call, and the turn only banks once each team has accepted.
  /// Untimed on purpose — a disagreement shouldn't be settled by a clock.
  Widget _review(NeonColors n) {
    final myTeam = onMyTeam ? turnTeam : (turnTeam == 'A' ? 'B' : 'A');
    final iAccepted = reviewAccepted.contains(myTeam);
    final scored = attempts.where((a) => a['correct'] == true).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Text("Team $turnTeam's round",
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .displayLarge
                ?.copyWith(fontSize: 24)),
        const SizedBox(height: 6),
        Text('$scored of ${attempts.length} attempted',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: n.gold, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
            phase == 'Summary'
                ? 'Round complete. Next turn starts shortly.'
                : _amSpectator
                    ? 'The teams are reviewing this round.'
                    : 'Tap any word to change the call. Both teams must agree.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: n.mute)),
        const SizedBox(height: 18),
        if (attempts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text('No words attempted this round.',
                textAlign: TextAlign.center, style: TextStyle(color: n.mute)),
          )
        else
          for (var i = 0; i < attempts.length; i++)
            _attemptRow(n, i, attempts[i]),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _acceptChip(n, 'A', reviewAccepted.contains('A')),
          const SizedBox(width: 10),
          _acceptChip(n, 'B', reviewAccepted.contains('B')),
        ]),
        const SizedBox(height: 16),
        if (phase == 'Summary')
          const SizedBox.shrink()
        else if (_amSpectator)
          const SizedBox.shrink()
        else if (iAccepted)
          Text('Waiting for the other team…',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: n.mute))
        else
          NeonButton('Accept $scored point${scored == 1 ? '' : 's'}',
              onPressed: _acceptReview),
      ],
    );
  }

  Widget _attemptRow(NeonColors n, int index, Map<String, dynamic> a) {
    final correct = a['correct'] == true;
    final skipped = a['skipped'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Bouncy(
        feel: BouncyFeel.soft,
        onTap: () => _toggleAttempt(index),
        child: NeonCard(
          child: Row(children: [
            Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: correct ? n.jade : n.mute, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${a['word']}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                        skipped
                            ? 'skipped'
                            : (correct ? 'counted' : 'not counted'),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: n.mute)),
                  ]),
            ),
            if (!_amSpectator)
              Icon(Icons.swap_horiz_rounded, size: 16, color: n.mute),
          ]),
        ),
      ),
    );
  }

  Widget _acceptChip(NeonColors n, String team, bool accepted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: accepted ? n.jade.withValues(alpha: 0.16) : n.plate,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accepted ? n.jade : n.line, width: 1.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(accepted ? Icons.check_rounded : Icons.hourglass_empty_rounded,
            size: 13, color: accepted ? n.jade : n.mute),
        const SizedBox(width: 5),
        Text('Team $team',
            style: TextStyle(
                color: accepted ? n.jade : n.mute,
                fontSize: 11,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _results(NeonColors n) {
    final won = winningTeam != null &&
        (winningTeam == 'A' ? teamA : teamB).contains(widget.selfId);
    final accent = winningTeam == 'A' ? n.gold : n.brand;
    return _centered([
      const Text('🏆', style: TextStyle(fontSize: 64)),
      const SizedBox(height: 10),
      Text('Team ${winningTeam ?? '?'} wins',
          style: Theme.of(context)
              .textTheme
              .displayLarge
              ?.copyWith(fontSize: 28, color: accent)),
      const SizedBox(height: 6),
      Text(
          _amSpectator
              ? 'Final score'
              : won
                  ? 'You won! 🎉'
                  : 'Better luck next round.',
          style:
              Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid)),
      const SizedBox(height: 18),
      Row(children: [
        _teamBox(n, 'Team A', teamA, teamAScore,
            active: winningTeam == 'A', accent: n.gold),
        const SizedBox(width: 10),
        _teamBox(n, 'Team B', teamB, teamBScore,
            active: winningTeam == 'B', accent: n.brand),
      ]),
      const SizedBox(height: 28),
      if (won)
        VictoryShareButton(
            roomId: widget.socket.roomId,
            gameType: 'wordbluff',
            detail: 'Team $winningTeam wins'),
      NeonButton(widget.spectating ? 'Close' : 'Back to home', onPressed: () {
        if (widget.spectating) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainShell()),
              (r) => false);
        }
      }),
      const GuestSaveSessionCard(),
    ]);
  }

  Widget _centered(List<Widget> children) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );

  /// Shows whether it's actively listening (a pulsing mic) and, once
  /// something's been heard, the live transcript — so it's obvious this is
  /// an assist and not a silent auto-guesser. Doesn't say anything if the
  /// mic never became available (denied permission, unsupported simulator,
  /// etc.) — the Skip/Got it buttons still work regardless.
  Widget _voiceIndicator(NeonColors n) {
    if (!_speechAvailable && _speechInitAttempted) {
      return Text(
          'Voice detection unavailable on this device — use the buttons below.',
          textAlign: TextAlign.center,
          style:
              Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _listening ? n.jade : n.mute,
            boxShadow: _listening
                ? [
                    BoxShadow(
                        color: n.jade.withValues(alpha: 0.6),
                        blurRadius: 8,
                        spreadRadius: 1)
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(
            _listening
                ? 'Listening for their guess…'
                : 'Voice detection paused',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: n.mute)),
      ]),
      if (_heardText.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('"$_heardText"',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: n.mid, fontStyle: FontStyle.italic)),
      ],
    ]);
  }
}

/// Fixed-pointer wheel: 20 equal slices, alternating tints, category emoji +
/// initial letters on each. The pointer is implicit (always "up" / 12
/// o'clock) — `_settleWheel` computes the rotation that lands a slice there.
class _WheelPainter extends CustomPainter {
  _WheelPainter(
      {required this.categories,
      required this.panel,
      required this.line,
      required this.ink});

  final List<(String slug, String name, String emoji)> categories;
  final Color panel;
  final Color line;
  final Color ink;

  String _shortLabel(String slug, String full) => switch (slug) {
        'current_affairs' => 'News',
        'movies_tv' => 'Film/TV',
        'food_drink' => 'Food',
        'occupations' => 'Jobs',
        'famous_faces' => 'Famous',
        'places_landmarks' => 'Places',
        'emotions_actions' => 'Actions',
        'fictional_characters' => 'Fiction',
        'everyday_objects' => 'Objects',
        'school_education' => 'School',
        'travel_transport' => 'Travel',
        'clothing_fashion' => 'Fashion',
        _ => full,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final sliceAngle = 2 * math.pi / categories.length;
    final rimPaint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    for (var i = 0; i < categories.length; i++) {
      final start = i * sliceAngle - math.pi / 2 - sliceAngle / 2;
      final tint = i.isEven
          ? panel
          : Color.alphaBlend(line.withValues(alpha: 0.35), panel);
      final paint = Paint()..color = tint;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(Rect.fromCircle(center: center, radius: radius), start,
            sliceAngle, false)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, rimPaint);

      // Emoji and name run outward along the slice, so each one is
      // readable rather than a row of anonymous symbols.
      final mid = start + sliceAngle / 2;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(mid);

      final emoji = TextPainter(
        text: TextSpan(
            text: categories[i].$3, style: TextStyle(fontSize: radius * 0.085)),
        textDirection: TextDirection.ltr,
      )..layout();
      emoji.paint(canvas, Offset(radius * 0.30, -emoji.height / 2));

      final name = TextPainter(
        text: TextSpan(
          text: _shortLabel(categories[i].$1, categories[i].$2),
          style: TextStyle(
            fontSize: (radius * 0.075).clamp(10.0, 15.0),
            fontWeight: FontWeight.w800,
            color: ink,
            height: 1.05,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: radius * 0.42);
      name.paint(
          canvas, Offset(radius * 0.30 + emoji.width + 6, -name.height / 2));
      canvas.restore();
    }

    canvas.drawCircle(center, radius, rimPaint);
    canvas.drawCircle(center, 14, Paint()..color = ink.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => false;
}
