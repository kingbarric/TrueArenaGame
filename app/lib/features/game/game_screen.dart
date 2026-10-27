import '../../widgets/game_artwork.dart';
import '../../widgets/match_coin_reward.dart';
import '../../core/api_client.dart' show userErrorMessage;
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_music.dart';
import '../../core/game_sfx.dart';
import '../../core/game_socket.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/how_to_play_dialog.dart';
import '../../widgets/motif.dart';
import '../../widgets/neon.dart';
import '../../widgets/table_chat.dart';
import '../../widgets/game_voice_control.dart';
import '../../widgets/neon_form.dart';
import '../status/victory_status.dart';
import '../onboarding/guest_save_session_card.dart';
import '../huudspace/leave_game.dart';
import 'table_ring.dart';
import 'traitors_reveal.dart';
import '../whot/whot_effects.dart' show WhotReactionLane, whotReactions;
import '../../widgets/huud_art.dart';

/// The actual game loop — role reveal through results — driven entirely by
/// server frames over the socket the lobby already opened. This screen holds
/// no game rules of its own: everything it renders is either a `SNAPSHOT`/
/// `PHASE`/`EVENT` frame from `GameOrchestrator`, or a `PLAYER_ACTION` sent
/// back in response to a tap. See docs/DEV_REFERENCE.md §4 for the wire
/// shapes this is built against.
class GameScreen extends StatefulWidget {
  const GameScreen({
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

  /// Watching, not playing: the whole public table, its talk and its
  /// reveals, with nothing to act on — and a tray of reactions to send.
  final bool spectating;

  /// userId -> display name, best-effort (falls back to a short id).
  final Map<String, String> nicknames;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  StreamSubscription? _sub;
  Timer? _ticker;

  String phase = 'RoleReveal';
  int round = 1;
  List<String> players = [];
  Set<String> alive = {};
  String? yourRole;
  Set<String> fellowTraitors = {};
  final List<String> eliminated = [];
  final Map<String, String> causes = {};
  final Map<String, String> revealedRoles = {};
  Map<String, String>? allRoles;
  String? winningSide;
  final List<String> feed = [];

  String? _selectedTarget;
  String? _firstNightTarget;
  List<String> _tieCandidates = [];
  bool _canAccuse = false;
  bool _shieldAvailable = false;
  String? _immunityHolder;
  bool _immunitySpent = false;
  String? _accused;
  int _giftUses = 0;
  bool _actionLocked = false;

  /// The table's rules, straight from the server (`rules` on every snapshot).
  /// Read instead of the preset name, so Custom games get every rule too.
  Map<String, dynamic> _rules = const {};
  Map<String, String> _nightPicks = const {};
  bool _canSkipNight = false;
  bool _doubleMurderAvailable = false;
  String? _doubleAgentCandidate;
  int _falseRevealUses = 0;
  bool _falseRevealArmed = false;
  bool _confessionalSubmitted = true;
  bool _canLeaveLastWill = false;
  bool _immunityAvailable = false;
  List<String> _missingVoters = const [];
  int _survivorsChoiceVotes = 0;
  String? _yourVote;
  ({int locked, int total})? _voteProgress;

  /// Ballots a veiled endgame withheld, released with the full reveal.
  List<Map<String, dynamic>> _hiddenBallots = const [];

  bool _twist(String id) => ((_rules['twists'] as List?) ?? const []).contains(id);
  bool get _amAlive => alive.contains(widget.selfId);
  Map<String, int> _timers = const {night: 0, roundTable: 0, vote: 0};
  int _suddenDeathSeconds = 30;
  int _defenseSeconds = 60;
  static const night = 'night', roundTable = 'roundTable', vote = 'vote';
  int? _secondsLeft;

  /// The host stopped the clock (`PAUSE_TOGGLE`). Talk goes on; nothing times out.
  bool _paused = false;

  /// Seconds until a host's pause gives up and the clock runs again.
  int? _pauseResumesIn;

  // Discussion-only chat (see docs/DEV_REFERENCE.md — GameOrchestrator.handleChat):
  // ephemeral, not replayed on reconnect, so a fresh list per round table is correct.
  final List<_ChatLine> _tableChat = [];
  final List<_ChatLine> _traitorChat = [];
  String _chatChannel = 'table';
  bool _chatExpanded = false;
  bool _botTextMode = false;
  final _chatController = TextEditingController();

  /// The audience channel, deliberately separate from the players' chat.
  /// Table talk here is role- and phase-restricted (traitors only, round
  /// table only), so spectators and agents can't share that box — they'd
  /// either break those rules or be silenced by them.
  final List<TableChatLine> _watchFeed = [];
  final TextEditingController _watchController = TextEditingController();
  int _spectatorCount = 0;

  /// Spectators' reactions floating past — players see them too.
  final _reactions = <Map<String, dynamic>>[];
  final _seenReactions = <String>{};
  Timer? _reactionSweep, _reactionCooldown;
  int _reactionSerial = 0;
  bool _reactionCooling = false, _spectatorsMuted = false;

  bool get _amSpectator => !players.contains(widget.selfId);

  /// The host stopped the game partway: it's over, and nobody won.
  bool _endedByHost = false;

  /// Who left the table in this phase (a murder, a banishment), for its
  /// reveal — and whether nobody did, and whether the reveal has finished.
  final List<RevealSubject> _revealSubjects = [];
  bool _nobodyThisPhase = false;
  bool _revealDone = false;
  String? _preset;

  bool _musicOn = GameMusic.enabled;
  bool _sfxOn = GameSfx.enabled;

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        height: 42,
        child: Row(children: [
          Icon(icon, size: 18, color: const Color(0xffc9b18c)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xfff0d8a8), fontSize: 13)),
          ),
        ]),
      );

  void _showHelp() {
    showHowToPlay(
      context,
      emoji: '🎭',
      title: 'Traitors',
      tagline: 'A hidden-role social deduction game — Traitors secretly work '
          'against the Faithful majority.',
      steps: const [
        'Each round opens at night — Traitors secretly choose someone to eliminate while everyone else sleeps.',
        'By morning, discuss openly at the round table — work out who the Traitors are (or bluff, if you are one).',
        'Everyone votes for who they suspect; the most-voted player is put to the test before being banished.',
        'Traitors win once they equal or outnumber the remaining Faithful; Faithful win by banishing every Traitor first.',
        "Some tables play with twists — extra powers and rules — check the lobby's game settings before you start.",
      ],
    );
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

  /// Always reachable — a round can stall on somebody who has walked away,
  /// and there was no way out of this screen at all.
  Future<void> _confirmExit() async {
    // A spectator has no seat to give up — back to wherever they watched from.
    if (widget.spectating) {
      await Navigator.of(context).maybePop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this game?'),
        content: const Text('The round carries on without you.'),
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
    if (leave == true && mounted) {
      await leaveGame(context, widget.socket.roomId);
    }
  }

  /// The host's way out for everyone — a table that's stalled, or that
  /// simply has to stop. Nobody wins it; everyone sees who was who.
  Future<void> _confirmEndGame() async {
    final end = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End the game for everyone?'),
        content: const Text('Nobody wins this one, and everyone sees who was who.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep playing')),
          TextButton(
              key: const ValueKey('traitors-end-confirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('End game')),
        ],
      ),
    );
    if (end == true && mounted) widget.socket.send('PLAYER_ACTION', {'action': 'END_GAME'});
  }

  /// The Traitors music is Creative Commons BY 4.0, so it's credited here.
  void _showMusicCredits() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Music credits'),
        content: const SingleChildScrollView(
          child: SelectableText(
            key: ValueKey('traitors-music-credits'),
            '“Ossuary 1 - A Beginning”, “Gathering Darkness”, “Heart of Nowhere”, '
            '“Dark Times”, “Crypto”, “Controlled Chaos - no percussion”, '
            '“End of the Era” and “Lightless Dawn”\n'
            'Kevin MacLeod (incompetech.com)\n'
            'Licensed under Creative Commons: By Attribution 4.0 License\n'
            'https://creativecommons.org/licenses/by/4.0/\n\n'
            'Source: https://incompetech.com/music/royalty-free/\n\n'
            'Cut to two-minute excerpts, loudness normalised, faded and converted to AAC '
            'for quiet background playback.',
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _sub = widget.socket.envelopes.listen(_onEnvelope);
    GameMusic.start(GameMusic.moodFor('truearena'));
    // Always 0 — see the comment on the equivalent call in
    // draughts_game_screen.dart: reusing widget.socket.lastSeq here can
    // make the server skip sending a full snapshot entirely.
    widget.socket.send('HELLO', {'lastSeq': 0});
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.socket.close();
    _ticker?.cancel();
    GameMusic.stop();
    _chatController.dispose();
    _watchController.dispose();
    _reactionSweep?.cancel();
    _reactionCooldown?.cancel();
    super.dispose();
  }

  String label(String id) =>
      widget.nicknames[id] ?? (id.length > 6 ? id.substring(0, 6) : id);

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
        _sceneMusic();
      case 'PHASE':
        _applyPhase((env['payload'] as Map).cast<String, dynamic>());
      case 'EVENT':
        _applyEvent((env['payload'] as Map).cast<String, dynamic>());
      case 'ERROR':
        final msg = (env['payload'] as Map)['message']?.toString() ??
            userErrorMessage;
        _actionLocked = false;
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
    }
  }

  void _applySnapshot(Map<String, dynamic> p) {
    final serverSeconds = p['secondsLeft'] as int?;
    _paused = p['paused'] == true;
    _pauseResumesIn = p['pauseResumesInSeconds'] as int?;
    final phaseChanged = p['phase'] != null && p['phase'] != phase;
    setState(() {
      phase = p['phase'] as String? ?? phase;
      final botTextMode = p['botTextMode'] as bool? ?? _botTextMode;
      if (botTextMode && (!_botTextMode || phaseChanged)) _chatExpanded = true;
      _botTextMode = botTextMode;
      round = p['round'] as int? ?? round;
      _tieCandidates = ((p['tieCandidates'] as List?) ?? const []).cast<String>();
      _canAccuse = p['canAccuse'] == true;
      _shieldAvailable = p['shieldAvailable'] == true;
      _immunityHolder = p['immunityHolder'] as String?;
      _immunitySpent = p['immunitySpent'] == true;
      _accused = p['accused'] as String?;
      _giftUses = p['giftUses'] as int? ?? 0;
      players = ((p['players'] as List?) ?? players).cast<String>();
      _spectatorCount = p['spectatorCount'] as int? ?? _spectatorCount;
      _spectatorsMuted = p['spectatorsMuted'] as bool? ?? _spectatorsMuted;
      alive = ((p['alive'] as List?) ?? alive.toList()).cast<String>().toSet();
      yourRole = p['yourRole'] as String? ?? yourRole;
      fellowTraitors =
          ((p['fellowTraitors'] as List?) ?? const []).cast<String>().toSet();
      eliminated
        ..clear()
        ..addAll(((p['eliminated'] as List?) ?? const []).cast<String>());
      causes
        ..clear()
        ..addAll(((p['causes'] as Map?) ?? const {}).cast<String, String>());
      revealedRoles
        ..clear()
        ..addAll(
            ((p['revealedRoles'] as Map?) ?? const {}).cast<String, String>());
      if (p['allRoles'] != null) {
        allRoles = (p['allRoles'] as Map).cast<String, String>();
      }
      winningSide = p['winningSide'] as String? ?? winningSide;
      _preset = p['preset'] as String? ?? _preset;
      _applyRules(p['rules']);
      _nightPicks = ((p['nightPicks'] as Map?) ?? const {}).cast<String, String>();
      _canSkipNight = p['canSkipNight'] == true;
      _doubleMurderAvailable = p['doubleMurderAvailable'] == true;
      _doubleAgentCandidate = p['doubleAgentCandidate'] as String?;
      _falseRevealUses = p['falseRevealUses'] as int? ?? 0;
      _falseRevealArmed = p['falseRevealArmed'] == true;
      _confessionalSubmitted = p['confessionalSubmitted'] != false;
      _canLeaveLastWill = p['canLeaveLastWill'] == true;
      _immunityAvailable = p['immunityAvailable'] == true;
      _missingVoters = ((p['missingVoters'] as List?) ?? const []).cast<String>();
      _survivorsChoiceVotes = p['survivorsChoiceVotes'] as int? ?? 0;
      _yourVote = p['yourVote'] as String?;
      final progress = p['voteProgress'];
      if (progress is Map) {
        _voteProgress = (locked: progress['locked'] as int? ?? 0, total: progress['total'] as int? ?? 0);
      }
      // A snapshot follows every server-side change, so whatever we sent has
      // been dealt with (or refused, which arrives as an ERROR).
      _actionLocked = false;
    });
    if (serverSeconds != null) _startCountdown(serverSeconds);
  }

  void _applyRules(Object? raw) {
    if (raw is! Map) return;
    _rules = raw.cast<String, dynamic>();
    final t = ((_rules['timers'] as Map?) ?? const {}).cast<String, dynamic>();
    _timers = {
      night: t['night'] as int? ?? 0,
      roundTable: t['roundTable'] as int? ?? 0,
      vote: t['vote'] as int? ?? 0,
    };
    _suddenDeathSeconds = t['suddenDeath'] as int? ?? _suddenDeathSeconds;
    _defenseSeconds = t['defense'] as int? ?? _defenseSeconds;
  }

  void _applyPhase(Map<String, dynamic> p) {
    final next = p['phase'] as String;
    final nextRound = p['round'] as int? ?? round;
    final changed = next != phase || nextRound != round;
    // The server sends PHASE after every change, not just when the phase moves
    // on. Resetting on each one cleared your highlighted vote the moment anyone
    // else voted, and wiped the traitors' night chat on every pick.
    if (!changed) return;
    setState(() {
      if (nextRound != round && round > 0) {
        _tableChat.add(_ChatLine.marker('Round $nextRound'));
        _traitorChat.add(_ChatLine.marker('Round $nextRound'));
      }
      phase = next;
      round = nextRound;
      _revealSubjects.clear();
      _nobodyThisPhase = false;
      _revealDone = false;
      _selectedTarget = null;
      _firstNightTarget = null;
      _actionLocked = false;
      // One running conversation, as in any chat: nothing is wiped as the
      // phases change — a new round just gets a marker (above).
      _chatExpanded = _botTextMode;
    });
    if (changed) {
      _restartCountdown();
      _sceneMusic();
    }
  }

  void _restartCountdown() {
    _ticker?.cancel();
    final seconds = switch (phase) {
      'Night' => _timers[night],
      'RoundTable' => _timers[roundTable],
      'Vote' => _timers[vote],
      'Revote' => _timers[vote],
      'SuddenDeath' => _suddenDeathSeconds,
      'Defense' => _defenseSeconds,
      _ => null
    };
    if (seconds == null || seconds <= 0) {
      setState(() => _secondsLeft = null);
      return;
    }
    _startCountdown(seconds);
  }

  void _startCountdown(int seconds) {
    _ticker?.cancel();
    setState(() => _secondsLeft = seconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        // A paused clock holds still; only the pause's own limit counts down.
        if (_paused) {
          if ((_pauseResumesIn ?? 0) > 0) _pauseResumesIn = _pauseResumesIn! - 1;
          return;
        }
        _secondsLeft = (_secondsLeft ?? 1) - 1;
        if (_secondsLeft! <= 0) t.cancel();
      });
    });
  }

  /// Room-level clock news from the server — the host pausing, resuming or
  /// adding time, or a pause running out by itself.
  void _applyClockEvent(String type, Map<String, dynamic> data) {
    final seconds = data['secondsLeft'] as int?;
    switch (type) {
      case 'GAME_PAUSED':
        setState(() {
          _paused = true;
          _pauseResumesIn = data['resumesInSeconds'] as int?;
        });
        _startCountdown(seconds ?? _secondsLeft ?? 0);
      case 'GAME_RESUMED':
        setState(() {
          _paused = false;
          _pauseResumesIn = null;
        });
        if (seconds != null && seconds > 0) _startCountdown(seconds);
      case 'TIMER_EXTENDED':
        if (seconds != null) _startCountdown(seconds);
    }
  }

  /// The music follows the game — night, table, vote, reveal. The result has
  /// its own stinger, and a game the host ended goes quiet.
  void _sceneMusic() {
    if (finished || _endedByHost) return;
    unawaited(GameMusic.switchTo(GameMusic.traitorsScene(phase)));
  }

  void _togglePause() => widget.socket.send('PAUSE_TOGGLE');

  void _addTime() => widget.socket.send('HOST_CONTROL', {'cmd': 'EXTEND_TIMER'});

  static String _clock(int seconds) => seconds >= 60
      ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
      : '$seconds s';

  /// What a player who isn't the host sees on a reveal screen.
  String get _movingOnLine {
    if (_paused) return 'The host paused the clock';
    final left = _secondsLeft;
    return left != null && left > 0 ? 'Moving on in ${_clock(left)}' : 'Waiting for the host…';
  }

  void _applyEvent(Map<String, dynamic> payload) {
    final type = payload['type'] as String;
    final data =
        ((payload['data'] as Map?) ?? const {}).cast<String, dynamic>();
    setState(() {
      switch (type) {
        case 'NIGHT_TARGET_SET':
          if (data['by'] == widget.selfId) {
            _actionLocked = false;
          }
        case 'GAME_STARTED':
          players = (data['players'] as List).cast<String>();
          alive = players.toSet();
        case 'ROLE_ASSIGNED':
          yourRole = data['role'] as String;
        case 'FELLOW_TRAITORS':
          fellowTraitors = (data['ids'] as List).cast<String>().toSet();
        case 'ACCUSATION_GRANTED':
          _canAccuse = true;
        case 'PUBLIC_ACCUSATION':
          _canAccuse = false;
          _accused = data['accused'] as String?;
        case 'TIE_REPLAY':
        case 'TIE_HOST_DECISION':
          _tieCandidates = ((data['tied'] as List?) ?? const []).cast<String>();
        case 'NO_MURDER':
        case 'NO_BANISH':
        case 'SHIELD_BLOCKED_MURDER':
          _nobodyThisPhase = true;
        case 'PLAYER_ELIMINATED':
          final id = data['id'] as String;
          _revealSubjects.add(RevealSubject(
              id: id,
              name: id == widget.selfId ? 'You' : label(id),
              role: data['roleShown'] == true ? data['role'] as String? : null));
          alive.remove(id);
          if (!eliminated.contains(id)) eliminated.add(id);
          causes[id] = data['cause'] as String? ?? 'unknown';
          if (data['roleShown'] == true && data['role'] != null) {
            revealedRoles[id] = data['role'] as String;
          }
        case 'GAME_ENDED_BY_HOST':
          _endedByHost = true;
          unawaited(GameMusic.stop());
        case 'GAME_OVER':
          winningSide = data['winningSide'] as String?;
          // A spectator has no side: the ending is a show either way.
          GameMusic.playOutcome(won: widget.spectating || (winningSide == 'traitors') == isTraitor);
        case 'FULL_REVEAL':
          allRoles = (data['roles'] as Map).cast<String, String>();
          _hiddenBallots = ((data['ballots'] as List?) ?? const [])
              .map((b) => (b as Map).cast<String, dynamic>())
              .where((b) => b['veiled'] == true)
              .toList();
        case 'SPECTATOR_COUNT':
          _spectatorCount = data['count'] as int? ?? _spectatorCount;
        case 'SPECTATOR_REACTION':
          _receiveReaction(data);
        case 'SPECTATORS_MUTED':
          _spectatorsMuted = true;
        case 'SPECTATORS_UNMUTED':
          _spectatorsMuted = false;
        case 'CHAT_MESSAGE':
          final from = data['from'] as String;
          final channel = data['channel']?.toString();
          final text = data['text'] as String;
          if (channel == 'spectate') {
            // Watchers go to the audience box.
            _watchFeed.insert(
                0,
                TableChatLine(
                  who: label(from),
                  text: text,
                  isAgent: channel == 'agent',
                  isSpectator: channel == 'spectate',
                ));
          } else if (channel == 'traitors') {
            _traitorChat.add(_ChatLine(
                from: label(from), text: text, mine: from == widget.selfId));
          } else {
            // The table — Cyber Agents included: they're players at it, so
            // what they say sits in order with everyone else's.
            _tableChat.add(_ChatLine(
                from: label(from), text: text, mine: from == widget.selfId));
          }
      }
      if (type != 'CHAT_MESSAGE') {
        final line = _describe(type, data);
        if (line != null) feed.insert(0, line);
      }
    });
    _applyClockEvent(type, data);
  }

  void _sendWatchChat() {
    final text = _watchController.text.trim();
    if (text.isEmpty) return;
    widget.socket.send('CHAT_SEND', {'channel': 'spectate', 'text': text});
    _watchController.clear();
  }

  void _sendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    // At night only the traitors' channel is open (they're agreeing a target).
    widget.socket.send('CHAT_SEND', {'channel': phase == 'Night' ? 'traitors' : _chatChannel, 'text': text});
    _chatController.clear();
  }

  String? _describe(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'GAME_ENDED_BY_HOST':
        return 'The host ended the game.';
      case 'GAME_PAUSED':
        return 'The host paused the clock.';
      case 'GAME_RESUMED':
        return data['reason'] == 'pause_limit'
            ? 'The pause ran out — the clock is running again.'
            : 'The clock is running again.';
      case 'TIMER_EXTENDED':
        final added = data['addedSeconds'] as int? ?? 120;
        return 'The host added ${added ~/ 60} minutes.';
      case 'NIGHT_FALLS':
        return 'Night ${data['round']} falls.';
      case 'NO_MURDER':
        return switch (data['reason']) {
          'opening_night' => 'A quiet first night — no one was taken.',
          'no_consensus' => 'The traitors couldn\'t agree — no one was taken.',
          _ => 'No one was taken tonight.',
        };
      case 'MORNING_REVEAL':
        final id = data['eliminated'];
        return id == null
            ? 'The sun rises. Everyone made it through the night.'
            : '${label(id as String)} was found — gone by morning.';
      case 'ROUND_TABLE_OPEN':
        return 'The round table opens.';
      case 'ALL_VOTES_IN':
        return 'All votes are in.';
      case 'VOTE_REVEALED':
        return '${label(data['voter'] as String)} voted for ${label(data['target'] as String)}.';
      case 'NO_BANISH':
        return 'No one is banished this round.';
      case 'TIE_NO_ELIMINATION':
        return 'A tie — no one is banished.';
      case 'TIE_REPLAY':
        return switch (data['method']) {
          'sudden_death' => 'The vote is tied. A sudden-death vote begins.',
          'trial_of_two' => 'The vote is tied. Both tied players get to defend themselves.',
          _ => 'The vote is tied. A revote begins.',
        };
      case 'FINAL_VOTE_OPEN':
        return 'Final vote between the two tied players.';
      case 'AFK_ABSTAINED':
        final ids = ((data['ids'] as List?) ?? const []).cast<String>();
        return ids.isEmpty ? null : '${ids.map(label).join(', ')} didn\'t vote — counted as abstaining.';
      case 'AFK_PENDING':
        return 'Some votes are missing — the host will settle them.';
      case 'IMMUNITY_BLOCKED_BANISH':
        return 'The immunity coin saved ${label(data['holder'] as String)} from banishment.';
      case 'DIRECT_POISON_USED':
        return 'Someone has been poisoned…';
      case 'ACCUSATION_GRANTED':
        return 'You hold the secret accusation. Use it once, at a round table.';
      case 'BLACKMAIL_INTEL':
        return 'Blackmail: ${label(data['target'] as String)} is ${data['side'] == 'faithful' ? 'Faithful' : 'a Traitor'}. Share it, hide it, or lie.';
      case 'SILENT_WITNESS_INTEL':
        return 'Silent witness: ${label(data['victim'] as String)} was definitely Faithful.';
      case 'RECRUITED_AS_TRAITOR':
        return 'You have been recruited. You are now a Traitor.';
      case 'DOUBLE_AGENT_CANDIDATE':
        return '${label(data['id'] as String)} can be recruited on a later night.';
      case 'DOUBLE_AGENT_RECRUITED':
        return '${label(data['id'] as String)} has joined the Traitors.';
      case 'FALSE_REVEAL_ARMED':
        return 'False reveal armed — the next banished Faithful\'s role will read unknown.';
      case 'FALSE_REVEAL_USED':
        return 'The false reveal hid ${label(data['id'] as String)}\'s role.';
      case 'CONFESSIONAL_REVEALED':
        return 'Confessional: "${data['text']}"';
      case 'LAST_WILL_POSTED':
        return '${label(data['id'] as String)}\'s last will: "${data['text']}"';
      case 'SURVIVORS_CHOICE_PROGRESS':
        return 'Survivors\' choice: ${data['votes']} of ${data['needed']} want to end the game.';
      case 'SURVIVORS_CHOICE_CALLED':
        return 'The survivors ended the game.';
      case 'NIGHT_TARGET_SET':
        return data['by'] == widget.selfId ? null : '${label(data['by'] as String)} picked ${label(data['target'] as String)}.';
      case 'TIE_HOST_DECISION':
        return 'The vote is tied. The host will choose.';
      case 'PUBLIC_ACCUSATION':
        return '${label(data['by'] as String)} accuses ${label(data['accused'] as String)}.';
      case 'MYSTERY_SHIELD_OFFERED':
        return 'A mystery shield is available to claim.';
      case 'SHIELD_CLAIMED':
        return '${label(data['holder'] as String)} claimed the mystery shield.';
      case 'SHIELD_BLOCKED_MURDER':
        return 'The shield blocked a murder.';
      case 'IMMUNITY_AWARDED':
        return '${label(data['holder'] as String)} won the immunity coin.';
      case 'IMMUNITY_SPENT':
        return '${label(data['holder'] as String)} spent the immunity coin.';
      case 'POISONED':
        return 'You have been poisoned. You have one more day.';
      case 'TIE_RESOLVED':
        return 'Tie broken (${data['method']}) — ${label(data['chosen'] as String)} is banished.';
      case 'BANISHED':
        return '${label(data['id'] as String)} is banished from the table.';
      case 'PLAYER_ELIMINATED':
        final shown = data['roleShown'] == true;
        return '${label(data['id'] as String)} is out${shown ? ' — revealed as ${data['role']}' : ''}.';
      case 'HIDDEN_LEGACY':
        return 'A hidden legacy stirs among the traitors…';
      case 'GAME_OVER':
        return data['winningSide'] == 'traitors'
            ? 'The Traitors win.'
            : 'The Faithful win.';
      default:
        return null;
    }
  }

  bool get isTraitor =>
      yourRole == 'traitor' || yourRole == 'recruited_traitor';
  bool get finished => phase == 'Results';

  void _sendAction(String action, [Map<String, dynamic>? data]) {
    if (_actionLocked || !widget.socket.isConnected) return;
    setState(() => _actionLocked = true);
    widget.socket.send(
        'PLAYER_ACTION', {'action': action, if (data != null) 'data': data});
  }

  void _advance() => _sendAction('ADVANCE_PHASE');

  void _pickNightTarget(String id) {
    setState(() => _selectedTarget = id);
    if (_doubleMurderAvailable && _firstNightTarget == null) {
      setState(() => _firstNightTarget = id);
      return;
    }
    _sendAction('NIGHT_TARGET', {
      'target': _firstNightTarget ?? id,
      if (_firstNightTarget != null && _firstNightTarget != id)
        'secondTarget': id,
    });
    _firstNightTarget = null;
  }

  Future<void> _chooseTargetAction(String action, List<String> candidates,
      {String? choice}) async {
    final target = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.neon.panel.withValues(alpha: 1),
      showDragHandle: true,
      builder: (ctx) => SafeArea(child: ListView(
        shrinkWrap: true,
        children: [
          for (final id in candidates)
            ListTile(
              minTileHeight: 56,
              title: Text(label(id), style: TextStyle(
                color: ctx.neon.ink, fontSize: 18, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, id)),
        ],
      )),
    );
    if (!mounted || target == null) return;
    _sendAction(action, {'target': target, if (choice != null) 'choice': choice});
  }

  Future<void> _useGift() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Poisoned Gift'),
        content: const Text('Poison a Faithful for the next sunrise, or offer a mystery shield.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'shield'), child: const Text('Offer shield')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'direct_poison'), child: const Text('Direct poison')),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'shield') {
      _sendAction('NIGHT_GIFT', {'choice': choice});
    } else {
      _chooseTargetAction('NIGHT_GIFT',
          alive.where((id) => id != widget.selfId && !fellowTraitors.contains(id)).toList(),
          choice: choice);
    }
  }

  Future<String?> _promptText(String title, String hint, {int maxLength = 140}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Send')),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _sendTextAction(String action, String title, String hint, {int maxLength = 140}) async {
    final text = await _promptText(title, hint, maxLength: maxLength);
    if (!mounted || text == null || text.isEmpty) return;
    _sendAction(action, {'text': text});
  }

  /// Host fills in an absent player's ballot: pick the voter, then their vote.
  Future<void> _assignMissingVote(String voter) async {
    final target = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text('${label(voter)} votes for…', style: const TextStyle(fontWeight: FontWeight.w800))),
        for (final id in alive.where((id) => id != voter))
          ListTile(title: Text(label(id)), onTap: () => Navigator.pop(ctx, id)),
      ])),
    );
    if (!mounted || target == null) return;
    _sendAction('HOST_ASSIGN_VOTE', {'voterId': voter, 'target': target});
  }

  void _castVote(String id) {
    setState(() => _selectedTarget = id);
    _sendAction('CAST_VOTE', {'target': id});
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return PopScope(
      canPop: finished,
      child: Scaffold(
        appBar: AppBar(
          title: Text(finished ? 'Results' : 'Round $round'),
          automaticallyImplyLeading: finished,
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
              icon: const Icon(Icons.settings_rounded, size: 20),
              color: const Color(0xff241708),
              onSelected: (value) {
                switch (value) {
                  case 'help':
                    _showHelp();
                  case 'music':
                    _toggleMusic();
                  case 'sfx':
                    _toggleSfx();
                  case 'credits':
                    _showMusicCredits();
                  case 'end':
                    _confirmEndGame();
                  case 'exit':
                    _confirmExit();
                }
              },
              itemBuilder: (_) => [
                _menuItem('help', Icons.help_outline_rounded, 'How to play'),
                _menuItem(
                    'music',
                    _musicOn
                        ? Icons.music_note_rounded
                        : Icons.music_off_rounded,
                    _musicOn ? 'Mute music' : 'Play music'),
                _menuItem(
                    'sfx',
                    _sfxOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                    _sfxOn ? 'Mute game sounds' : 'Play game sounds'),
                _menuItem('credits', Icons.library_music_outlined, 'Music credits'),
                if (widget.isHost && !finished)
                  _menuItem('end', Icons.stop_circle_outlined, 'End game for everyone'),
                _menuItem('exit', Icons.logout_rounded, widget.spectating ? 'Stop watching' : 'Leave'),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(child: GameArtworkBackdrop(gameType: 'truearena', mode: _preset)),
            Positioned.fill(
                child: GameBackdropMotifs(
                    gold: n.gold, brand: n.brand, jade: n.jade)),
            SafeArea(
              // Laid out under the stage rather than floating over it.
              child: Column(children: [
                if (phase != 'RoundTable') _clockBar(n),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: KeyedSubtree(
                        key: ValueKey(phase), child: _phaseBody(n)),
                  ),
                ),
                // Players already have the round-table chat on screen when it's
                // open — one chat at a time, not two stacked boxes.
                if (!finished && (_amSpectator || !_roundChatOnScreen))
                  TableChatPanel(
                    lines: _watchFeed,
                    controller: _watchController,
                    onSend: _sendWatchChat,
                    spectatorCount: _spectatorCount,
                    amSpectator: _amSpectator,
                    height: MediaQuery.sizeOf(context).height < 600 ? 48 : 92,
                    // Players have their own chat, with its own rules about
                    // who may speak and when. This box is the audience.
                    canSend: _amSpectator,
                    disabledHint:
                        'Watchers comment here — you talk at the round table.',
                  ),
                if (widget.spectating && !finished && !_spectatorsMuted) _reactionTray(),
              ]),
            ),
            // Reactions drift up the edges, clear of the table and its buttons.
            for (final side in const [0, 1])
              Positioned(
                left: side == 0 ? 2 : null,
                right: side == 1 ? 2 : null,
                top: 96,
                bottom: 150,
                child: WhotReactionLane(
                    key: ValueKey('traitors-reactions-$side'),
                    reactions: _reactions,
                    side: side,
                    reduced: MediaQuery.disableAnimationsOf(context)),
              ),
          ],
        ),
      ),
    );
  }

  /// Someone watching reacted. Each shows once, only while it's fresh, and
  /// never while the players have quietened the audience.
  void _receiveReaction(Map<String, dynamic> data) {
    final id = data['id']?.toString();
    final sent = (data['sentAtMs'] as num?)?.toInt();
    if (_spectatorsMuted ||
        id == null ||
        sent == null ||
        !whotReactions.contains(data['emoji']) ||
        DateTime.now().millisecondsSinceEpoch - sent > 3000 ||
        !_seenReactions.add(id)) {
      return;
    }
    if (_seenReactions.length > 128) _seenReactions.remove(_seenReactions.first);
    _reactions.add({...data, 'lane': _reactionSerial++ % 2, 'expiresAtTick': (_reactionSweep?.tick ?? 0) + 23});
    if (_reactions.length > 8) _reactions.removeAt(0);
    _reactionSweep ??= Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _reactions.removeWhere((r) => (r['expiresAtTick'] as int) <= timer.tick));
      if (_reactions.isEmpty) {
        timer.cancel();
        _reactionSweep = null;
      }
    });
  }

  /// A spectator's reactions — one a second, as the server allows.
  Widget _reactionTray() => SizedBox(
      key: const ValueKey('traitors-reaction-tray'),
      height: 38,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final emoji in whotReactions)
          IconButton(
              key: ValueKey('traitors-react-$emoji'),
              tooltip: 'React $emoji',
              padding: const EdgeInsets.all(3),
              constraints: const BoxConstraints(minWidth: 42, minHeight: 34),
              onPressed: _reactionCooling
                  ? null
                  : () {
                      setState(() => _reactionCooling = true);
                      widget.socket.send('REACTION_SEND', {'emoji': emoji});
                      _reactionCooldown?.cancel();
                      _reactionCooldown = Timer(const Duration(milliseconds: 1100), () {
                        if (mounted) setState(() => _reactionCooling = false);
                      });
                    },
              icon: Text(emoji, style: const TextStyle(fontSize: 21))),
      ]));

  Widget _phaseBody(NeonColors n) {
    return switch (phase) {
      'RoleReveal' => _roleReveal(n),
      'Night' => _night(n),
      'MorningReveal' => _revealStage(n, 'Who was taken in the night?', extras: [
          if (_canLeaveLastWill)
            NeonButton('Leave your last will', style: NeonStyle.ghost,
                onPressed: _actionLocked ? null : () => _sendTextAction('LAST_WILL',
                    'Your last will', 'One sentence for the table', maxLength: 140)),
        ]),
      'RoundTable' => _roundTable(n),
      'Vote' => _vote(n),
      'Revote' => _vote(n),
      'SuddenDeath' => _vote(n),
      'Defense' => _defense(n),
      'HostAssignVotes' => _hostAssignVotes(n),
      'HostDecision' => widget.isHost
          ? _pickerScreen(n, title: 'Break the tie', subtitle: 'Choose a tied player to banish.',
              candidates: _tieCandidates, onPick: (id) => _sendAction('CHOOSE_TIE', {'target': id}),
              accent: n.gold)
          : _centered([const Text('The host is breaking the tie.')]),
      'VoteReview' => _simpleAdvance(n, '🗳️', 'Vote review', hostExtras: [
          if (_rules['voteReveal'] != 'all_at_once')
            NeonButton('Reveal next vote', style: NeonStyle.ghost,
                onPressed: _actionLocked ? null : () => _sendAction('REVEAL_NEXT')),
        ], continueLabel: 'Reveal all'),
      'Elimination' => _revealStage(n, 'The table has spoken…', extras: [
          if (_immunityHolder == widget.selfId && !_immunitySpent)
            NeonButton('Spend immunity coin', style: NeonStyle.ghost,
                onPressed: _actionLocked ? null : () => _sendAction('USE_IMMUNITY')),
        ]),
      'WinCheck' => _simpleAdvance(n, '🔎', 'Checking the table…'),
      'Results' => _results(n),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  // ---------------------------------------------------------------- phase screens

  Widget _roleReveal(NeonColors n) {
    if (widget.spectating) {
      return _centered([
        const HuudText('🎭', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 14),
        Text('The roles are being dealt',
            key: const ValueKey('watch-role-reveal'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28, color: n.gold)),
        const SizedBox(height: 10),
        Text('Everyone is finding out who they are. The Traitors are among them — watch closely.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid)),
        const SizedBox(height: 28),
        _waiting(n, _movingOnLine),
      ]);
    }
    final traitor = isTraitor;
    final color = traitor ? n.brand : n.gold;
    return _centered([
      HuudText(traitor ? '😈' : '😇', style: const TextStyle(fontSize: 64)),
      const SizedBox(height: 14),
      Text(traitor ? 'You are a Traitor' : 'You are Faithful',
          style: Theme.of(context)
              .textTheme
              .displayLarge
              ?.copyWith(fontSize: 30, color: color)),
      const SizedBox(height: 10),
      Text(
        traitor
            ? 'Blend in. Choose a target each night with your fellow traitors.'
            : 'Find the traitors before they take the table.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid),
      ),
      if (traitor && fellowTraitors.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text('WITH YOU',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: n.mute, letterSpacing: 2)),
        const SizedBox(height: 8),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final id in fellowTraitors)
                NeonChip(
                    label: label(id),
                    selected: true,
                    accent: n.brand,
                    onTap: () {}),
            ]),
      ],
      const SizedBox(height: 28),
      if (widget.isHost)
        NeonButton('Everyone knows their role',
            onPressed: _actionLocked ? null : _advance)
      else
        _waiting(n, _movingOnLine),
    ]);
  }

  Widget _night(NeonColors n) {
    final candidates = alive
        .where((id) => id != widget.selfId && !fellowTraitors.contains(id))
        .toList();
    if (!isTraitor || !_amAlive) {
      return _centered([
        const HuudText('🌙', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 14),
        Text('The town sleeps…',
            style: Theme.of(context)
                .textTheme
                .displayLarge
                ?.copyWith(fontSize: 26)),
        const SizedBox(height: 8),
        Text('The traitors are choosing.',
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid)),
        if (_secondsLeft != null) ...[
          const SizedBox(height: 14),
          _countdown(n)
        ],
      ]);
    }
    final consensus = _rules['requireTraitorConsensus'] == true;
    // Who has picked whom tonight, so the traitors can see whether they agree.
    final picks = <String, List<String>>{};
    _nightPicks.forEach((traitor, target) =>
        picks.putIfAbsent(target, () => []).add(traitor == widget.selfId ? 'You' : label(traitor)));
    return Column(children: [
      Expanded(child: _pickerScreen(
        n,
        title: _firstNightTarget == null ? 'Choose your target' : 'Choose a second target',
        subtitle: _firstNightTarget != null
            ? 'A second murder is allowed tonight.'
            : consensus
                ? 'Every traitor must pick the same target before the clock runs out.'
                : fellowTraitors.isEmpty
                    ? 'Pick who to eliminate tonight.'
                    : 'Agree with your fellow traitors on tonight\'s target.',
        candidates: _firstNightTarget == null
            ? candidates : candidates.where((id) => id != _firstNightTarget).toList(),
        onPick: _pickNightTarget,
        accent: n.brand,
        countdown: true,
        tags: {for (final e in picks.entries) e.key: e.value.join(', ')},
      )),
      if (_firstNightTarget != null)
        TextButton(onPressed: () {
          final target = _firstNightTarget!;
          setState(() => _firstNightTarget = null);
          _sendAction('NIGHT_TARGET', {'target': target});
        }, child: const Text('Continue with one target')),
      Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
        if (_canSkipNight)
          TextButton(
              onPressed: _actionLocked ? null : () => _sendAction('NIGHT_SKIP'),
              child: const Text('Skip tonight (once per game)')),
        if (_giftUses > 0)
          TextButton(onPressed: _actionLocked ? null : _useGift,
              child: const Text('Use Poisoned Gift')),
        if (_doubleAgentCandidate != null)
          TextButton(
              onPressed: _actionLocked ? null : () => _sendAction('RECRUIT_DOUBLE_AGENT'),
              child: Text('Recruit ${label(_doubleAgentCandidate!)}')),
      ]),
      if (fellowTraitors.isNotEmpty) _chatPanel(n),
    ]);
  }

  Widget _defense(NeonColors n) {
    final trial = _tieCandidates.isNotEmpty;
    return _centered([
      const HuudText('🗣️', style: TextStyle(fontSize: 52)),
      const SizedBox(height: 10),
      Text(trial ? 'Trial of two' : 'The defense',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 26)),
      const SizedBox(height: 8),
      Text(
        trial
            ? '${_tieCandidates.map(label).join(' and ')} each make their case. Then a final vote between them.'
            : '${_accused == null ? 'The accused player' : label(_accused!)} answers the accusation.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid),
      ),
      if (_secondsLeft != null) ...[const SizedBox(height: 12), _countdown(n)],
      const SizedBox(height: 14),
      _recentFeed(n, max: 3),
      const SizedBox(height: 20),
      if (widget.isHost)
        NeonButton('Go to the vote', style: NeonStyle.ghost, onPressed: _actionLocked ? null : _advance)
      else
        _waiting(n, 'Listen closely…'),
    ]);
  }

  /// "Host assigns" AFK rule: the host fills in missing ballots, or lets them
  /// count as abstentions. This phase used to render as an endless spinner.
  Widget _hostAssignVotes(NeonColors n) {
    return _centered([
      const HuudText('🗳️', style: TextStyle(fontSize: 52)),
      const SizedBox(height: 10),
      Text('Missing votes', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 26)),
      const SizedBox(height: 8),
      Text(
        _missingVoters.isEmpty
            ? 'Everyone has voted.'
            : '${_missingVoters.map(label).join(', ')} ${_missingVoters.length == 1 ? 'hasn\'t' : 'haven\'t'} voted.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid),
      ),
      if (_secondsLeft != null) ...[const SizedBox(height: 12), _countdown(n)],
      const SizedBox(height: 18),
      if (widget.isHost) ...[
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          for (final voter in _missingVoters)
            NeonChip(label: 'Vote for ${label(voter)}', accent: n.gold, selected: false,
                onTap: _actionLocked ? () {} : () => _assignMissingVote(voter)),
        ]),
        const SizedBox(height: 18),
        NeonButton('Count them as abstaining', style: NeonStyle.ghost,
            onPressed: _actionLocked ? null : _advance),
      ] else
        _waiting(n, 'The host is settling the missing votes…'),
    ]);
  }

  /// Everyone around the table, the talk in the middle: who's at the table
  /// sits on an oval ring (squashed to fit the space, so a full table of 16
  /// still shows every face), and the middle carries what the round table is
  /// about — the clock, the latest news, your accusation, and the host's skip.
  Widget _roundTable(NeonColors n) {
    final twists = <Widget>[
      if (_shieldAvailable)
        NeonButton('Claim the mystery shield', style: NeonStyle.ghost, expand: false,
          onPressed: _actionLocked ? null : () => _sendAction('CLAIM_SHIELD')),
      if (_twist('confessional') && _amAlive && !_confessionalSubmitted)
        NeonButton('Submit your confessional', style: NeonStyle.ghost, expand: false,
          onPressed: _actionLocked ? null : () => _sendTextAction('SUBMIT_CONFESSIONAL',
              'Confessional', 'One line — it\'s shown anonymously', maxLength: 200)),
      if (isTraitor && _amAlive && _falseRevealUses > 0 && !_falseRevealArmed)
        NeonButton('Hide the next banished Faithful\'s role', style: NeonStyle.ghost, expand: false,
          onPressed: _actionLocked ? null : () => _sendAction('FALSE_REVEAL')),
      if (_survivorsChoiceAvailable) _survivorsChoiceButton(n),
      if (widget.isHost && _immunityAvailable)
        NeonButton('Award challenge immunity', style: NeonStyle.ghost, expand: false,
          onPressed: _actionLocked ? null : () => _chooseTargetAction(
            'AWARD_IMMUNITY', alive.toList())),
    ];
    return LayoutBuilder(builder: (context, box) {
      final buttonCount = (_canAccuse ? 1 : 0) + (widget.isHost ? 1 : 0);
      final textWidth = (box.maxWidth - 144).clamp(1.0, double.infinity);
      double textHeight(String text, TextStyle style) {
        final painter = TextPainter(text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))
          ..layout(maxWidth: textWidth);
        return painter.height;
      }
      final titleHeight = textHeight('Round table',
        Theme.of(context).textTheme.displayLarge!.copyWith(fontSize: 28));
      final requiredHeight = 180 + textHeight('Talk it out — who feels like a traitor?',
        const TextStyle(fontSize: 16, height: 1.25)) +
        (_secondsLeft == null ? 0 : 48) + buttonCount * 58 + (buttonCount > 0 ? 12 : 0) +
        (feed.isEmpty ? 0 : 48);
      final clockHeight = widget.isHost || _paused ? 46 : 0;
      final chatHeight = _chatExpanded
        ? (box.maxHeight - requiredHeight - clockHeight - (twists.isEmpty ? 0 : 64)).clamp(120.0, 320.0)
        : 54.0;
      final tableHeight = box.maxHeight - chatHeight - (twists.isEmpty ? 0 : 64) - clockHeight;
      final titleAbove = tableHeight < requiredHeight + titleHeight + 6;
      return Column(children: [
        _clockBar(n, tableTitle: titleAbove),
        Expanded(child: DiscussionTable(
          players: players,
          seat: (id, size) => _seat(n, id, size),
          child: _tableCentre(n, showTitle: !titleAbove),
        )),
        if (twists.isNotEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: twists)),
        _chatPanel(n, height: chatHeight),
      ]);
    });
  }

  /// Controls keep their natural font and touch sizes on the solid tabletop.
  Widget _tableCentre(NeonColors n, {required bool showTitle}) =>
      LayoutBuilder(builder: (context, box) {
        const cream = Color(0xffffefd6);
        Widget action(String text, Key key, VoidCallback? onPressed) =>
            SizedBox(width: double.infinity, child: FilledButton(
              key: key,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffffdf9b),
                foregroundColor: const Color(0xff352010),
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              onPressed: onPressed, child: Text(text, textAlign: TextAlign.center)));
        final buttons = <Widget>[
          if (_canAccuse)
            action('Make your accusation', const ValueKey('round-table-accuse'),
              _actionLocked ? null : () => _chooseTargetAction(
                'ACCUSE', alive.where((id) => id != widget.selfId).toList())),
          if (widget.isHost)
            action('Skip to the vote', const ValueKey('round-table-skip'),
              _actionLocked ? null : _advance),
        ];
        final details = Column(mainAxisSize: MainAxisSize.min, children: [
          if (showTitle) ...[
            Text('Round table', key: const ValueKey('round-table-title'), textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28, color: cream)),
            const SizedBox(height: 6),
          ],
          const Text('Talk it out — who feels like a traitor?', textAlign: TextAlign.center,
            style: TextStyle(color: cream, fontSize: 16, height: 1.25)),
          if (_secondsLeft != null) ...[
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.hourglass_bottom_rounded, color: Color(0xffffdf9b), size: 24),
              const SizedBox(width: 8),
              Text(_paused ? '⏸ ${_clock(_secondsLeft!)}' : _clock(_secondsLeft!),
                style: const TextStyle(color: cream, fontSize: 28,
                  fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
            ]),
          ],
        ]);
        final controls = Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: 8), buttons[i],
          ],
        ]);
        if (box.maxWidth > 400 && box.maxHeight < 280) {
          return Row(children: [Expanded(child: details), const SizedBox(width: 20), Expanded(child: controls)]);
        }
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          details,
          if (feed.isNotEmpty) ...[
            const SizedBox(height: 8),
            Flexible(child: Text(feed.first, maxLines: 2, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center, style: const TextStyle(color: cream, fontSize: 16))),
          ],
          if (buttons.isNotEmpty) ...[const SizedBox(height: 12), controls],
        ]);
      });

  /// Opens beneath the discussion for anyone who'd rather type than talk — a
  /// public "table" channel everyone sees, plus a "traitors" channel only
  /// traitors can even select (the backend also enforces this — see
  /// GameOrchestrator.handleChat — this hides the option, that guarantees it).
  /// Shown during RoundTable, and to the Traitors at night (traitors' channel
  /// only) so they can agree a target. There's no chat during voting.
  Widget _chatPanel(NeonColors n, {double? height}) {
    final atNight = phase == 'Night';
    final onTraitorChannel = atNight || _chatChannel == 'traitors';
    final messages = onTraitorChannel ? _traitorChat : _tableChat;
    final tint = onTraitorChannel ? n.brand : n.gold;
    // Shorter at night: the target picker above it matters more.
    final openHeight = height ?? (MediaQuery.sizeOf(context).height < 600 ? 180.0 : (atNight ? 240.0 : 320.0));
    return Container(
      height: _chatExpanded ? openHeight : 54,
      decoration: BoxDecoration(
          color: n.panel,
          border: const Border(top: BorderSide(color: kCabinetInk, width: 2))),
      // Constrain chat independently so resizing never squeezes the table.
      child: ClipRect(
       child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: 0,
        maxHeight: (_chatExpanded ? openHeight : 54) - 2,
        child: Column(
        children: [
          Bouncy(
            onTap: () => setState(() => _chatExpanded = !_chatExpanded),
            pressScale: 0.99,
            child: Container(
              // 14 + 24 (icon) + 14 fills the collapsed 54px panel less its
              // 2px top border exactly; 15 overflowed it by two pixels.
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(children: [
                HuudText(onTraitorChannel ? '🎭' : '💬',
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(onTraitorChannel ? 'Traitors only' : 'Round table chat',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700, color: tint)),
                const Spacer(),
                Icon(
                    _chatExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    color: n.mute),
              ]),
            ),
          ),
          if (_chatExpanded) ...[
            if (isTraitor && !atNight)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: NeonSegmented<String>(
                  options: const [
                    SegOption('table', 'Table'),
                    SegOption('traitors', 'Traitors')
                  ],
                  value: _chatChannel,
                  onChanged: (c) => setState(() => _chatChannel = c),
                ),
              ),
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        onTraitorChannel
                            ? 'Only your fellow traitors can see this.'
                            : _botTextMode ? 'Type to discuss the round with the bots.' : 'Say something the table can hear.',
                        style: TextStyle(color: n.mute, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final m = messages[messages.length - 1 - i];
                        if (m.marker) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(m.text.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.4,
                                    color: n.mute)),
                          );
                        }
                        return Align(
                          alignment: m.mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 260),
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: m.mine
                                  ? tint.withValues(alpha: 0.16)
                                  : n.plate,
                              borderRadius:
                                  BorderRadius.circular(NeonRadius.control),
                              border:
                                  Border.all(color: kCabinetInk, width: 1.4),
                            ),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!m.mine)
                                    Text(m.from,
                                        style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: n.mute)),
                                  Text(m.text,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                ]),
                          ),
                        );
                      },
                    ),
            ),
            if (widget.spectating)
              Padding(
                key: const ValueKey('watch-table-chat-note'),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text('The players are talking — you\'re watching. Comment and react below.',
                    textAlign: TextAlign.center, style: TextStyle(color: n.mute, fontSize: 12)),
              )
            else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                        hintText: onTraitorChannel
                            ? 'Only traitors see this…'
                            : 'Say something…'),
                    onSubmitted: (_) => _sendChat(),
                  ),
                ),
                const SizedBox(width: 8),
                Bouncy(
                  onTap: _sendChat,
                  pressScale: 0.9,
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration:
                        BoxDecoration(color: tint, shape: BoxShape.circle),
                    child:
                        Icon(Icons.send_rounded, size: 18, color: n.onAccent),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
       ),
      ),
    );
  }

  /// The round-table (or, at night, the traitors') chat is showing.
  bool get _roundChatOnScreen =>
      phase == 'RoundTable' || (phase == 'Night' && isTraitor && _amAlive && fellowTraitors.isNotEmpty);

  bool get _survivorsChoiceAvailable =>
      _twist('survivors_choice') && _amAlive && alive.length <= 4;

  Widget _survivorsChoiceButton(NeonColors n) => NeonButton(
      'End the game now ($_survivorsChoiceVotes/${alive.length})', style: NeonStyle.ghost,
      onPressed: _actionLocked ? null : () => _sendAction('CALL_SURVIVORS_CHOICE'));

  Widget _vote(NeonColors n) {
    final progress = _voteProgress == null ? '' : ' · ${_voteProgress!.locked}/${_voteProgress!.total} in';
    if (!_amAlive) {
      // Eliminated players and spectators watch; the picker only produced errors for them.
      return _centered([
        const HuudText('🗳️', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 10),
        Text('The table is voting', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 26)),
        const SizedBox(height: 8),
        Text(widget.spectating ? 'Watch how the table votes$progress' : 'You\'re out of this game — watch how it plays out$progress',
            textAlign: TextAlign.center, style: TextStyle(color: n.mid)),
        if (_secondsLeft != null) ...[const SizedBox(height: 12), _countdown(n)],
        const SizedBox(height: 14),
        _recentFeed(n, max: 4),
      ]);
    }
    final candidates = alive.where((id) => id != widget.selfId &&
        (_tieCandidates.isEmpty || _tieCandidates.contains(id))).toList();
    final finalVote = phase == 'Vote' && _tieCandidates.isNotEmpty;
    final title = switch (phase) {
      'SuddenDeath' => 'Sudden death',
      'Revote' => 'Break the tie',
      _ => finalVote ? 'Final vote' : 'Cast your vote',
    };
    final voted = _yourVote;
    return Column(children: [
      Expanded(child: _pickerScreen(
        n,
        title: title,
        subtitle: voted != null
            ? 'Your vote is locked: ${label(voted)}$progress'
            : (phase == 'Vote' && !finalVote ? 'Who do you want to banish?' : 'Vote between the tied players.') + progress,
        candidates: candidates,
        onPick: _castVote,
        accent: n.gold,
        countdown: true,
        lockedChoice: voted,
      )),
      if (_survivorsChoiceAvailable) Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: _survivorsChoiceButton(n)),
    ]);
  }

  /// A murder or a banishment, revealed at the round table: a spotlight runs
  /// round the seats, stops on whoever's gone, and then shows what they were.
  /// The host moves on once it's all been shown (the clock still does too).
  Widget _revealStage(NeonColors n, String heading, {List<Widget> extras = const []}) {
    // Elimination is the server's pre-tally phase: ADVANCE_PHASE calculates
    // the banishment. Waiting for a subject here would deadlock the host.
    final awaitingTally = phase == 'Elimination' && _revealSubjects.isEmpty && !_nobodyThisPhase;
    return Column(children: [
      Expanded(
        child: EliminationReveal(
          key: ValueKey('reveal-$phase-$round'),
          players: players,
          subjects: List.of(_revealSubjects),
          nobody: _nobodyThisPhase,
          heading: heading,
          seat: (id, size, spotlight) => _seat(n, id, size, spotlight: spotlight),
          onDone: () {
            if (mounted) setState(() => _revealDone = true);
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final w in extras) ...[w, const SizedBox(height: 8)],
          if (widget.isHost)
            NeonButton('Continue',
                key: const ValueKey('reveal-continue'),
                style: NeonStyle.ghost,
                onPressed: _actionLocked || (!_revealDone && !awaitingTally) ? null : _advance)
          else
            _waiting(n, _movingOnLine),
        ]),
      ),
    ]);
  }

  Widget _simpleAdvance(NeonColors n, String emoji, String title,
      {List<Widget> extras = const [], List<Widget> hostExtras = const [], String continueLabel = 'Continue'}) {
    return _centered([
      HuudText(emoji, style: const TextStyle(fontSize: 52)),
      const SizedBox(height: 10),
      Text(title,
          style:
              Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 26)),
      const SizedBox(height: 14),
      _recentFeed(n, max: 4),
      if (phase == 'VoteReview' && _immunityHolder == widget.selfId && !_immunitySpent) ...[
        const SizedBox(height: 12),
        NeonButton('Spend immunity coin', style: NeonStyle.ghost,
            onPressed: _actionLocked ? null : () => _sendAction('USE_IMMUNITY')),
      ],
      for (final w in extras) ...[const SizedBox(height: 12), w],
      const SizedBox(height: 20),
      if (widget.isHost) ...[
        for (final w in hostExtras) ...[w, const SizedBox(height: 10)],
        NeonButton(continueLabel,
            style: NeonStyle.ghost, onPressed: _actionLocked ? null : _advance),
      ] else
        _waiting(n, _movingOnLine),
    ]);
  }

  Widget _results(NeonColors n) {
    final ended = _endedByHost && winningSide == null;
    final won = !ended && (winningSide == 'traitors' ? isTraitor : !isTraitor);
    return _centered([
      HuudText(ended ? '🎭' : winningSide == 'traitors' ? '😈' : '😇',
          style: const TextStyle(fontSize: 64)),
      const SizedBox(height: 10),
      Text(
          ended
              ? 'The host ended the game'
              : winningSide == 'traitors'
                  ? 'The Traitors win'
                  : 'The Faithful win',
          key: const ValueKey('traitors-result-title'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
              fontSize: 28,
              color: ended ? n.ink : winningSide == 'traitors' ? n.brand : n.gold)),
      const SizedBox(height: 6),
      HuudText(
          ended
              ? "Nobody won this one — here's who was who."
              : widget.spectating
                  ? 'Thanks for watching 👀'
                  : won
                      ? 'You won! 🎉'
                      : 'Better luck next table.',
          textAlign: TextAlign.center,
          style:
              Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid)),
      const SizedBox(height: 18),
      if (allRoles != null) ...[
        Text('FULL REVEAL',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: n.mute, letterSpacing: 2)),
        const SizedBox(height: 10),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final e in allRoles!.entries)
                NeonChip(
                  label:
                      '${label(e.key)} · ${e.value == 'traitor' || e.value == 'recruited_traitor' ? '😈' : '😇'}',
                  selected: e.key == widget.selfId,
                  accent:
                      (e.value == 'traitor' || e.value == 'recruited_traitor')
                          ? n.brand
                          : n.gold,
                  onTap: () {},
                ),
            ]),
      ],
      if (_hiddenBallots.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text('THE HIDDEN VOTES',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, letterSpacing: 2)),
        const SizedBox(height: 8),
        for (final b in _hiddenBallots) ...[
          Text('Round ${b['round']}${b['stage'] == 'tie' ? ' (tie-break)' : ''}',
              style: TextStyle(color: n.gold, fontWeight: FontWeight.w800, fontSize: 12)),
          for (final v in ((b['votes'] as Map?) ?? const {}).entries)
            Text('${label(v.key as String)} → ${label(v.value as String)}',
                style: TextStyle(color: n.mid, fontSize: 12)),
          const SizedBox(height: 6),
        ],
      ],
      const SizedBox(height: 28),
      if (!_amSpectator && !ended) MatchCoinReward(roomId: widget.socket.roomId),
      if (won) VictoryShareButton(roomId: widget.socket.roomId,
          gameType: 'truearena', detail: 'The ${winningSide == 'traitors' ? 'Traitors' : 'Faithful'} win'),
      NeonButton('Back to the Huud', onPressed: () {
        leaveGame(context, widget.socket.roomId);
      }),
      const GuestSaveSessionCard(),
    ]);
  }

  // ---------------------------------------------------------------- shared bits

  Widget _pickerScreen(
    NeonColors n, {
    required String title,
    required String subtitle,
    required List<String> candidates,
    required void Function(String) onPick,
    required Color accent,
    bool countdown = false,
    Map<String, String> tags = const {},
    String? lockedChoice,
  }) {
    // Short on height (e.g. the traitors' chat open at night on a phone):
    // drop to a one-line header rather than overflowing the screen.
    return LayoutBuilder(builder: (context, outer) {
     final compact = outer.maxHeight < 320;
     return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, compact ? 8 : 18, 20, compact ? 2 : 6),
          child: Column(children: [
            Text(compact && countdown && _secondsLeft != null ? '$title · ${_clock(_secondsLeft!)}' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .displayLarge
                    ?.copyWith(fontSize: compact ? 18 : 26),
                textAlign: TextAlign.center),
            if (!compact) ...[
              const SizedBox(height: 6),
              HuudText(subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: n.mid)),
              if (countdown && _secondsLeft != null) ...[
                const SizedBox(height: 10),
                _countdown(n)
              ],
            ],
          ]),
        ),
        Expanded(
          child: LayoutBuilder(
              builder: (context, box) => GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: box.maxWidth < 300 ? 2 : 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 8,
                      childAspectRatio: box.maxWidth < 300 ? 1.05 : 0.8,
                    ),
                    itemCount: candidates.length,
                    itemBuilder: (context, i) {
                      final id = candidates[i];
                      final selected = (lockedChoice ?? _selectedTarget) == id;
                      return Bouncy(
                        onTap: lockedChoice != null || (_actionLocked && !selected)
                            ? null
                            : () => onPick(id),
                        pressScale: 0.92,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: selected ? accent : n.line,
                                  width: selected ? 2.6 : 1.4),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                          color: accent.withValues(alpha: 0.4),
                                          blurRadius: 16,
                                          spreadRadius: -2)
                                    ]
                                  : null,
                            ),
                            child: ValueListenableBuilder<Set<String>>(
                              valueListenable: widget.socket.onlinePlayers,
                              builder: (_, online, __) => OnlineAvatar(label(id),
                                  size: 58, imageUrl: widget.socket.memberAvatars[id], online: online.contains(id), presence: widget.socket.presenceOf(id)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(label(id),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          if (tags[id] != null)
                            Text(tags[id]!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w800)),
                        ]),
                      );
                    },
                  )),
        ),
      ],
     );
    });
  }

  /// Everyone at the table, not just the survivors. Who has gone — and when
  /// — is most of what there is to reason about in this game, so the
  /// eliminated stay on the list, dimmed and struck through, with whatever
  /// their role turned out to be.
  /// One person at the table: their face (crossed out once they're gone),
  /// their name, and their role once it's been shown.
  Widget _seat(NeonColors n, String id, double size, {bool spotlight = false}) {
    const alivePulse = Color(0xff4ade80);
    final isAlive = alive.contains(id) || spotlight;
    final isMe = id == widget.selfId;
    final role = revealedRoles[id] ?? allRoles?[id];
    final accused = id == _accused;
    return Opacity(
      opacity: isAlive ? 1 : 0.42,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(alignment: Alignment.center, children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: spotlight
                    ? n.gold
                    : !isAlive
                    ? Colors.transparent
                    : accused
                        ? n.brand
                        : isMe
                            ? alivePulse
                            : Colors.white.withValues(alpha: 0.18),
                width: spotlight ? 3 : (isMe || accused) && isAlive ? 2.2 : 1.2,
              ),
              boxShadow: spotlight
                  ? [BoxShadow(color: n.gold.withValues(alpha: 0.75), blurRadius: 22, spreadRadius: 2)]
                  : isMe && isAlive
                  ? [BoxShadow(color: alivePulse.withValues(alpha: 0.4), blurRadius: 10, spreadRadius: -2)]
                  : null,
            ),
            child: ValueListenableBuilder<Set<String>>(
              valueListenable: widget.socket.onlinePlayers,
              builder: (_, online, __) => OnlineAvatar(label(id),
                  size: size, imageUrl: widget.socket.memberAvatars[id], online: online.contains(id),
                  presence: widget.socket.presenceOf(id)),
            ),
          ),
          if (!isAlive && !spotlight) Icon(Icons.close_rounded, size: size * 0.7, color: const Color(0xffe0704a)),
        ]),
        const SizedBox(height: 3),
        Text(
          isMe ? 'You' : label(id),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: isAlive ? n.ink : n.mute,
            decoration: isAlive ? null : TextDecoration.lineThrough,
          ),
        ),
        if (role != null)
          Text(
            role.contains('traitor') ? 'traitor' : 'faithful',
            style: TextStyle(
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: role.contains('traitor') ? n.brand : n.jade,
            ),
          ),
      ]),
    );
  }

  Widget _recentFeed(NeonColors n, {int max = 3}) {
    if (feed.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          for (final line in feed.take(max))
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: n.mid, fontSize: 12.5)))
        ],
      ),
    );
  }

  /// The host's hand on the clock — pause it for a longer talk, or add two
  /// minutes — and, for everyone, word that the clock is paused.
  /// Screens that already put their own countdown on the stage.
  bool get _phaseShowsClock =>
      const {'Night', 'RoundTable', 'Vote', 'Revote', 'SuddenDeath', 'Defense'}.contains(phase);

  Widget _clockBar(NeonColors n, {bool tableTitle = false}) {
    final left = _secondsLeft;
    final hostControls = widget.isHost && !_amSpectator && left != null && !finished;
    if (finished || (!tableTitle && !_paused && !hostControls)) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.labelSmall;
    final resumes = _pauseResumesIn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(children: [
        Icon(_paused ? Icons.pause_circle_rounded : Icons.timer_outlined,
            size: 16, color: _paused ? n.gold : n.jade),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            tableTitle ? 'Round table' : _paused
                ? (resumes != null && resumes > 0
                    ? 'Clock paused · runs again in ${_clock(resumes)}'
                    : 'Clock paused')
                : (_phaseShowsClock ? '' : _clock(left ?? 0)),
            key: tableTitle ? const ValueKey('round-table-title') : null,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style?.copyWith(
                fontSize: tableTitle ? 18 : null,
                color: tableTitle ? n.ink : (_paused ? n.gold : n.jade),
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        if (hostControls) ...[
          TextButton.icon(
            key: const ValueKey('traitors-pause'),
            onPressed: _togglePause,
            icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 16),
            label: Text(_paused ? 'Resume' : 'Pause'),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact, foregroundColor: n.gold),
          ),
          TextButton.icon(
            key: const ValueKey('traitors-add-time'),
            onPressed: _addTime,
            icon: const Icon(Icons.more_time_rounded, size: 16),
            label: const Text('+2 min'),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact, foregroundColor: n.jade),
          ),
        ],
      ]),
    );
  }

  Widget _countdown(NeonColors n) => Text(
      _paused ? '⏸ ${_clock(_secondsLeft ?? 0)}' : _clock(_secondsLeft ?? 0),
      style: TextStyle(
          color: n.jade,
          fontWeight: FontWeight.w800,
          fontSize: 13,
          fontFeatures: const [FontFeature.tabularFigures()]));

  Widget _waiting(NeonColors n, String text) => Text(text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute));

  Widget _centered(List<Widget> children) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );
}

class _ChatLine {
  const _ChatLine({required this.from, required this.text, required this.mine}) : marker = false;

  /// "Round 2" — where one round's talk ends and the next begins.
  const _ChatLine.marker(this.text)
      : from = '',
        mine = false,
        marker = true;

  final String from;
  final String text;
  final bool mine;
  final bool marker;
}
