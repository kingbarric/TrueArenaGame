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
  });

  final GameSocket socket;
  final String selfId;
  final bool isHost;

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

  bool get _amSpectator => !players.contains(widget.selfId);

  bool _musicOn = GameMusic.enabled;
  bool _sfxOn = GameSfx.enabled;

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
    final serverSeconds = p['secondsLeft'] as int?;
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
      phase = next;
      round = nextRound;
      _selectedTarget = null;
      _firstNightTarget = null;
      _actionLocked = false;
      // chat is per phase and never replayed — start clean
      _tableChat.clear();
      _traitorChat.clear();
      _chatExpanded = _botTextMode;
    });
    if (changed) _restartCountdown();
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
        _secondsLeft = (_secondsLeft ?? 1) - 1;
        if (_secondsLeft! <= 0) t.cancel();
      });
    });
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
        case 'PLAYER_ELIMINATED':
          final id = data['id'] as String;
          alive.remove(id);
          if (!eliminated.contains(id)) eliminated.add(id);
          causes[id] = data['cause'] as String? ?? 'unknown';
          if (data['roleShown'] == true && data['role'] != null) {
            revealedRoles[id] = data['role'] as String;
          }
        case 'GAME_OVER':
          winningSide = data['winningSide'] as String?;
          GameMusic.playOutcome(won: (winningSide == 'traitors') == isTraitor);
        case 'FULL_REVEAL':
          allRoles = (data['roles'] as Map).cast<String, String>();
          _hiddenBallots = ((data['ballots'] as List?) ?? const [])
              .map((b) => (b as Map).cast<String, dynamic>())
              .where((b) => b['veiled'] == true)
              .toList();
        case 'SPECTATOR_COUNT':
          _spectatorCount = data['count'] as int? ?? _spectatorCount;
        case 'CHAT_MESSAGE':
          final from = data['from'] as String;
          final channel = data['channel']?.toString();
          final text = data['text'] as String;
          if (channel == 'spectate' || channel == 'agent') {
            // Watchers and agents go to the audience box.
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
            _tableChat.add(_ChatLine(
                from: label(from), text: text, mine: from == widget.selfId));
          }
      }
      if (type != 'CHAT_MESSAGE') {
        final line = _describe(type, data);
        if (line != null) feed.insert(0, line);
      }
    });
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
      builder: (ctx) => SafeArea(child: ListView(
        shrinkWrap: true,
        children: [
          for (final id in candidates)
            ListTile(title: Text(label(id)), onTap: () => Navigator.pop(ctx, id)),
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
                _menuItem('exit', Icons.logout_rounded, 'Leave'),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
                child: GameBackdropMotifs(
                    gold: n.gold, brand: n.brand, jade: n.jade)),
            SafeArea(
              // Laid out under the stage rather than floating over it.
              child: Column(children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: KeyedSubtree(
                        key: ValueKey(phase), child: _phaseBody(n)),
                  ),
                ),
                if (!finished)
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
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phaseBody(NeonColors n) {
    return switch (phase) {
      'RoleReveal' => _roleReveal(n),
      'Night' => _night(n),
      'MorningReveal' => _simpleAdvance(n, '🌅', 'Morning', extras: [
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
      'Elimination' => _simpleAdvance(n, '⚖️', 'Elimination'),
      'WinCheck' => _simpleAdvance(n, '🔎', 'Checking the table…'),
      'Results' => _results(n),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  // ---------------------------------------------------------------- phase screens

  Widget _roleReveal(NeonColors n) {
    final traitor = isTraitor;
    final color = traitor ? n.brand : n.gold;
    return _centered([
      Text(traitor ? '😈' : '😇', style: const TextStyle(fontSize: 64)),
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
        _waiting(n, 'Waiting for the host…'),
    ]);
  }

  Widget _night(NeonColors n) {
    final candidates = alive
        .where((id) => id != widget.selfId && !fellowTraitors.contains(id))
        .toList();
    if (!isTraitor || !_amAlive) {
      return _centered([
        const Text('🌙', style: TextStyle(fontSize: 56)),
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
      const Text('🗣️', style: TextStyle(fontSize: 52)),
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
      const Text('🗳️', style: TextStyle(fontSize: 52)),
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

  Widget _roundTable(NeonColors n) {
    return Column(
      children: [
        Expanded(
          child: _centered([
            const Text('🎪', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 10),
            Text('Round table',
                style: Theme.of(context)
                    .textTheme
                    .displayLarge
                    ?.copyWith(fontSize: 28)),
            const SizedBox(height: 6),
            Text('Talk it out — who feels like a traitor?',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: n.mid)),
            if (_secondsLeft != null) ...[
              const SizedBox(height: 14),
              _countdown(n)
            ],
            const SizedBox(height: 18),
            _participantStrip(n),
            const SizedBox(height: 18),
            _recentFeed(n, max: 3),
            if (_canAccuse) ...[
              const SizedBox(height: 12),
              NeonButton('Make your accusation', style: NeonStyle.ghost,
                onPressed: _actionLocked ? null : () => _chooseTargetAction(
                  'ACCUSE', alive.where((id) => id != widget.selfId).toList())),
            ],
            if (_shieldAvailable) ...[
              const SizedBox(height: 12),
              NeonButton('Claim the mystery shield', style: NeonStyle.ghost,
                onPressed: _actionLocked ? null : () => _sendAction('CLAIM_SHIELD')),
            ],
            if (_twist('confessional') && _amAlive && !_confessionalSubmitted) ...[
              const SizedBox(height: 12),
              NeonButton('Submit your confessional', style: NeonStyle.ghost,
                onPressed: _actionLocked ? null : () => _sendTextAction('SUBMIT_CONFESSIONAL',
                    'Confessional', 'One line — it\'s shown anonymously', maxLength: 200)),
            ],
            if (isTraitor && _amAlive && _falseRevealUses > 0 && !_falseRevealArmed) ...[
              const SizedBox(height: 12),
              NeonButton('Hide the next banished Faithful\'s role', style: NeonStyle.ghost,
                onPressed: _actionLocked ? null : () => _sendAction('FALSE_REVEAL')),
            ],
            if (_survivorsChoiceAvailable) ...[
              const SizedBox(height: 12),
              _survivorsChoiceButton(n),
            ],
            if (widget.isHost && _immunityAvailable) ...[
              const SizedBox(height: 12),
              NeonButton('Award challenge immunity', style: NeonStyle.ghost,
                onPressed: _actionLocked ? null : () => _chooseTargetAction(
                  'AWARD_IMMUNITY', alive.toList())),
            ],
            if (widget.isHost) ...[
              const SizedBox(height: 18),
              NeonButton('Move to vote',
                  style: NeonStyle.ghost,
                  onPressed: _actionLocked ? null : _advance)
            ],
          ]),
        ),
        _chatPanel(n),
      ],
    );
  }

  /// Opens beneath the discussion for anyone who'd rather type than talk — a
  /// public "table" channel everyone sees, plus a "traitors" channel only
  /// traitors can even select (the backend also enforces this — see
  /// GameOrchestrator.handleChat — this hides the option, that guarantees it).
  /// Shown during RoundTable, and to the Traitors at night (traitors' channel
  /// only) so they can agree a target. There's no chat during voting.
  Widget _chatPanel(NeonColors n) {
    final atNight = phase == 'Night';
    final onTraitorChannel = atNight || _chatChannel == 'traitors';
    final messages = onTraitorChannel ? _traitorChat : _tableChat;
    final tint = onTraitorChannel ? n.brand : n.gold;
    // Shorter at night: the target picker above it matters more.
    final openHeight = MediaQuery.sizeOf(context).height < 600 ? 180.0 : (atNight ? 240.0 : 320.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: _chatExpanded ? openHeight : 54,
      decoration: BoxDecoration(
          color: n.panel,
          border: const Border(top: BorderSide(color: kCabinetInk, width: 2))),
      // Lay the contents out at their final height and clip while the panel
      // grows — otherwise they overflow for the length of the animation.
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
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              child: Row(children: [
                Text(onTraitorChannel ? '🎭' : '💬',
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
        const Text('🗳️', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 10),
        Text('The table is voting', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 26)),
        const SizedBox(height: 8),
        Text('You\'re out of this game — watch how it plays out$progress',
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

  Widget _simpleAdvance(NeonColors n, String emoji, String title,
      {List<Widget> extras = const [], List<Widget> hostExtras = const [], String continueLabel = 'Continue'}) {
    return _centered([
      Text(emoji, style: const TextStyle(fontSize: 52)),
      const SizedBox(height: 10),
      Text(title,
          style:
              Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 26)),
      const SizedBox(height: 14),
      _recentFeed(n, max: 4),
      if ((phase == 'VoteReview' || phase == 'Elimination') &&
          _immunityHolder == widget.selfId && !_immunitySpent) ...[
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
        _waiting(n, 'Waiting for the host…'),
    ]);
  }

  Widget _results(NeonColors n) {
    final won = winningSide == 'traitors' ? isTraitor : !isTraitor;
    return _centered([
      Text(winningSide == 'traitors' ? '😈' : '😇',
          style: const TextStyle(fontSize: 64)),
      const SizedBox(height: 10),
      Text(winningSide == 'traitors' ? 'The Traitors win' : 'The Faithful win',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
              fontSize: 28,
              color: winningSide == 'traitors' ? n.brand : n.gold)),
      const SizedBox(height: 6),
      Text(won ? 'You won! 🎉' : 'Better luck next table.',
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
      if (won) VictoryShareButton(roomId: widget.socket.roomId,
          gameType: 'truearena', detail: 'The ${winningSide == 'traitors' ? 'Traitors' : 'Faithful'} win'),
      NeonButton('Back to home', onPressed: () {
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
            Text(compact && countdown && _secondsLeft != null ? '$title · $_secondsLeft s' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .displayLarge
                    ?.copyWith(fontSize: compact ? 18 : 26),
                textAlign: TextAlign.center),
            if (!compact) ...[
              const SizedBox(height: 6),
              Text(subtitle,
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
                                  size: 58, imageUrl: widget.socket.memberAvatars[id], online: online.contains(id)),
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
  Widget _participantStrip(NeonColors n) {
    const alivePulse = Color(0xff4ade80);
    return SizedBox(
      height: 86,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final id in players)
            Builder(builder: (context) {
              final isAlive = alive.contains(id);
              final isMe = id == widget.selfId;
              final role = revealedRoles[id] ?? allRoles?[id];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Opacity(
                  opacity: isAlive ? 1 : 0.42,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Stack(alignment: Alignment.center, children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isAlive
                                ? (isMe
                                    ? alivePulse
                                    : Colors.white.withValues(alpha: 0.18))
                                : Colors.transparent,
                            width: isMe && isAlive ? 2.2 : 1.2,
                          ),
                          boxShadow: isMe && isAlive
                              ? [
                                  BoxShadow(
                                      color: alivePulse.withValues(alpha: 0.4),
                                      blurRadius: 10,
                                      spreadRadius: -2)
                                ]
                              : null,
                        ),
                        child: ValueListenableBuilder<Set<String>>(
                          valueListenable: widget.socket.onlinePlayers,
                          builder: (_, online, __) => OnlineAvatar(label(id),
                              size: 42, imageUrl: widget.socket.memberAvatars[id], online: online.contains(id)),
                        ),
                      ),
                      if (!isAlive)
                        const Icon(Icons.close_rounded,
                            size: 30, color: Color(0xffe0704a)),
                    ]),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 58,
                      child: Text(
                        isMe ? 'You' : label(id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: isAlive ? n.ink : n.mute,
                          decoration:
                              isAlive ? null : TextDecoration.lineThrough,
                        ),
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
                ),
              );
            }),
        ],
      ),
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

  Widget _countdown(NeonColors n) => Text('$_secondsLeft s',
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
  const _ChatLine({required this.from, required this.text, required this.mine});
  final String from;
  final String text;
  final bool mine;
}
