import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import 'huud_kit.dart';

/// A Chess or Draughts championship inside a Huud: registration, the system
/// draw, rounds of matches (several at once), and a champion — then the Huud
/// goes back to hanging out. Huud chat stays the one chat; voice is the
/// championship lobby (the Huud's own room) or the match you're looking at.

const championshipGames = ['chess', 'draughts'];

class CupEntrant {
  const CupEntrant({required this.userId, required this.name, required this.username, this.avatarUrl, this.out = false});

  final String userId;
  final String name;
  final String username;
  final String? avatarUrl;

  /// Knocked out.
  final bool out;

  String get handle => username.isNotEmpty ? username : name.split(' ').first;

  factory CupEntrant.fromJson(Map<String, dynamic> j) => CupEntrant(
        userId: j['userId'].toString(),
        name: j['name'] as String? ?? '',
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        out: j['out'] == true,
      );
}

class CupMatch {
  const CupMatch({
    required this.id,
    required this.round,
    required this.roundName,
    required this.position,
    required this.status,
    this.playerA,
    this.playerB,
    this.winnerId,
    this.roomId,
    this.voiceRoom,
    this.gameNumber = 1,
    this.watching = 0,
    this.aReconnectMs = 0,
    this.bReconnectMs = 0,
  });

  final String id;
  final int round;
  final String roundName;
  final int position;

  /// pending · active · completed · bye · no_winner
  final String status;
  final String? playerA, playerB, winnerId;

  /// Set while it's being played.
  final String? roomId, voiceRoom;

  /// Draws are replayed: game 2, 3…
  final int gameNumber;
  final int watching;
  final int aReconnectMs, bReconnectMs;

  bool get live => status == 'active' && roomId != null;
  bool get done => status == 'completed' || status == 'bye' || status == 'no_winner';
  bool has(String? userId) => userId != null && (playerA == userId || playerB == userId);

  factory CupMatch.fromJson(Map<String, dynamic> j) => CupMatch(
        id: j['id'].toString(),
        round: (j['round'] as num?)?.toInt() ?? 1,
        roundName: j['roundName'] as String? ?? '',
        position: (j['position'] as num?)?.toInt() ?? 1,
        status: j['status'] as String? ?? 'pending',
        playerA: j['playerA']?.toString(),
        playerB: j['playerB']?.toString(),
        winnerId: j['winnerId']?.toString(),
        roomId: j['roomId']?.toString(),
        voiceRoom: j['voiceRoom'] as String?,
        gameNumber: (j['gameNumber'] as num?)?.toInt() ?? 1,
        watching: (j['watching'] as num?)?.toInt() ?? 0,
        aReconnectMs: (j['aReconnectMs'] as num?)?.toInt() ?? 0,
        bReconnectMs: (j['bReconnectMs'] as num?)?.toInt() ?? 0,
      );
}

class HuudCup {
  const HuudCup({
    required this.id,
    required this.name,
    required this.gameType,
    required this.size,
    required this.status,
    required this.roundTiming,
    required this.spectatorsAllowed,
    required this.graceSeconds,
    required this.currentRound,
    required this.rounds,
    required this.players,
    required this.matches,
    required this.lobbyVoiceRoom,
    this.roundName,
    this.youAreRegistered = false,
    this.championId,
    this.runnerUpId,
    this.yourMatchId,
  });

  final String id, name, gameType;
  final int size;

  /// registering · playing · finished · cancelled
  final String status;

  /// simultaneous · sequential
  final String roundTiming;
  final bool spectatorsAllowed;
  final int graceSeconds;
  final int currentRound, rounds;
  final String? roundName;
  final List<CupEntrant> players;
  final List<CupMatch> matches;
  final String lobbyVoiceRoom;
  final bool youAreRegistered;
  final String? championId, runnerUpId, yourMatchId;

  bool get registering => status == 'registering';
  bool get playing => status == 'playing';
  bool get finished => status == 'finished';
  bool get full => players.length >= size;

  List<CupMatch> get liveMatches => matches.where((m) => m.live).toList();

  CupMatch? matchById(String? id) {
    for (final m in matches) {
      if (m.id == id) return m;
    }
    return null;
  }

  CupMatch? liveMatchWithVoice(String? room) {
    for (final m in matches) {
      if (m.live && m.voiceRoom == room) return m;
    }
    return null;
  }

  CupEntrant? player(String? id) {
    for (final p in players) {
      if (p.userId == id) return p;
    }
    return null;
  }

  String handle(String? id, {String? me}) {
    if (id == null) return 'TBD';
    if (id == me) return 'You';
    return player(id)?.handle ?? 'Player';
  }

  /// Usernames for the game screens' labels.
  Map<String, String> get nicknames => {for (final p in players) p.userId: p.handle};

  factory HuudCup.fromJson(Map<String, dynamic> j) => HuudCup(
        id: j['id'].toString(),
        name: j['name'] as String? ?? 'Championship',
        gameType: j['gameType'] as String? ?? 'chess',
        size: (j['size'] as num?)?.toInt() ?? 8,
        status: j['status'] as String? ?? 'registering',
        roundTiming: j['roundTiming'] as String? ?? 'simultaneous',
        spectatorsAllowed: j['spectatorsAllowed'] != false,
        graceSeconds: (j['graceSeconds'] as num?)?.toInt() ?? 180,
        currentRound: (j['currentRound'] as num?)?.toInt() ?? 0,
        rounds: (j['rounds'] as num?)?.toInt() ?? 3,
        roundName: j['roundName'] as String?,
        players: [
          for (final p in (j['players'] as List? ?? const [])) CupEntrant.fromJson((p as Map).cast<String, dynamic>()),
        ],
        matches: [
          for (final m in (j['matches'] as List? ?? const [])) CupMatch.fromJson((m as Map).cast<String, dynamic>()),
        ],
        lobbyVoiceRoom: j['lobbyVoiceRoom'] as String? ?? 'huud-${j['huudSpaceId']}',
        youAreRegistered: j['youAreRegistered'] == true,
        championId: j['championId']?.toString(),
        runnerUpId: j['runnerUpId']?.toString(),
        yourMatchId: j['yourMatchId']?.toString(),
      );
}

/// How the match card shows it, from your seat.
String cupMatchTitle(HuudCup cup, CupMatch m, {String? me}) =>
    '${cup.handle(m.playerA, me: me)} vs ${cup.handle(m.playerB, me: me)}';

// ---------------------------------------------------------------- setup

/// The host sets up a championship: the game, how many players, how rounds
/// run, whether people can watch, and how long a dropped player has to come
/// back. Answers with the new championship, or null.
Future<HuudCup?> showChampionshipSetup(BuildContext context, String huudId) =>
    showHuudSheet<HuudCup>(context, builder: (_) => _SetupSheet(huudId: huudId));

class _SetupSheet extends StatefulWidget {
  const _SetupSheet({required this.huudId});
  final String huudId;

  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  String _game = 'chess';
  int _size = 8;
  String _timing = 'simultaneous';
  bool _watching = true;
  int _grace = 3;
  bool _busy = false;

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final raw = await AppScope.of(context).api.post('/huud-spaces/${widget.huudId}/championship', {
        'gameType': _game,
        'size': _size,
        'roundTiming': _timing,
        'spectatorsAllowed': _watching,
        'graceMinutes': _grace,
      });
      if (!mounted) return;
      Navigator.of(context).pop(HuudCup.fromJson((raw as Map).cast<String, dynamic>()));
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, "Error has occurred, try again later.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: n.mid)),
        );
    Widget choices<T>(List<(T, String)> options, T value, ValueChanged<T> pick, String keyPrefix) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (v, text) in options)
              _Pill(
                key: ValueKey('$keyPrefix-$v'),
                text: text,
                selected: v == value,
                onTap: () => setState(() => pick(v)),
              ),
          ],
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('🏆', textAlign: TextAlign.center, style: TextStyle(fontSize: 40)),
          Text('Start a championship',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: n.ink)),
          const SizedBox(height: 4),
          Text('Everyone in the Huud can register. When every place is filled, the draw happens by itself.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: n.mid)),
          label('Game'),
          Row(children: [
            for (final g in championshipGames) ...[
              Expanded(
                child: _GameChoice(
                  key: ValueKey('cup-game-$g'),
                  gameType: g,
                  selected: _game == g,
                  onTap: () => setState(() => _game = g),
                ),
              ),
              if (g != championshipGames.last) const SizedBox(width: 12),
            ],
          ]),
          label('Players'),
          choices<int>(const [(4, '4'), (8, '8'), (16, '16')], _size, (v) => _size = v, 'cup-size'),
          label('Format'),
          Text('Knockout · one game a match · a draw is replayed until someone wins',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: n.ink)),
          label('Rounds'),
          choices<String>(const [('simultaneous', 'All matches at once'), ('sequential', 'One match at a time')],
              _timing, (v) => _timing = v, 'cup-timing'),
          const SizedBox(height: 6),
          Text(
              _timing == 'simultaneous'
                  ? 'Quicker — the Final is always on its own.'
                  : 'Everyone watches the same match — good for hosting or streaming.',
              style: TextStyle(fontSize: 13, color: n.mute)),
          label('Watching'),
          choices<bool>(const [(true, 'People can watch'), (false, 'Players only')], _watching, (v) => _watching = v,
              'cup-watch'),
          label('If a player drops out'),
          choices<int>(const [(1, '1 min'), (3, '3 min'), (5, '5 min')], _grace, (v) => _grace = v, 'cup-grace'),
          const SizedBox(height: 6),
          Text('They have this long to come back before they lose the match.',
              style: TextStyle(fontSize: 13, color: n.mute)),
          const SizedBox(height: 22),
          HuudButton(
            key: const ValueKey('cup-start'),
            label: 'Open registration',
            icon: Icons.emoji_events_rounded,
            big: true,
            expand: true,
            busy: _busy,
            onPressed: _start,
          ),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.text, required this.selected, required this.onTap});
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? h.orange : n.plate,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: selected ? kCabinetInk : n.line, width: selected ? 2 : 1.2),
          ),
          child: Text(text,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: selected ? h.onOrange : n.ink)),
        ),
      ),
    );
  }
}

class _GameChoice extends StatelessWidget {
  const _GameChoice({super.key, required this.gameType, required this.selected, required this.onTap});
  final String gameType;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: huudGameName(gameType),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? h.orangeSoft : n.plate,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? h.orange : n.line, width: selected ? 2.4 : 1.2),
          ),
          child: Column(children: [
            HuudGameArt(gameType, size: 56),
            const SizedBox(height: 8),
            Text(huudGameName(gameType), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: n.ink)),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- the panel

/// Everything the Play tab shows while a championship is on.
class ChampionshipPanel extends StatelessWidget {
  const ChampionshipPanel({
    super.key,
    required this.cup,
    required this.me,
    required this.youAreHost,
    required this.youOwn,
    required this.youAreIn,
    required this.onRegister,
    required this.onWithdraw,
    required this.onOpenMatch,
    required this.onCallOff,
    required this.onNew,
    required this.onHangOut,
    required this.onEndLive,
    required this.onRemovePlayer,
    required this.onEndBothAbsent,
    this.listeningTo,
    this.busy,
  });

  final HuudCup cup;
  final String? me;
  final bool youAreHost, youAreIn, youOwn;

  /// The match whose voice you're hearing — null in the championship lobby.
  final CupMatch? listeningTo;
  final String? busy;
  final VoidCallback onRegister, onWithdraw, onCallOff, onNew, onHangOut, onEndLive;
  final ValueChanged<CupMatch> onOpenMatch, onEndBothAbsent;
  final ValueChanged<CupEntrant> onRemovePlayer;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      _header(context),
      const SizedBox(height: 14),
      if (cup.registering) ..._registration(context),
      if (cup.playing) ..._playing(context),
      if (cup.finished) ..._finished(context),
      if (cup.status == 'cancelled')
        const HuudFriendlyState(emoji: '🌙', title: 'Called off', message: 'This championship was called off.'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _header(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final subtitle = cup.registering
        ? 'Registration · ${cup.players.length} / ${cup.size} players'
        : cup.playing
            ? (cup.roundName == 'Final' ? 'Championship Final' : cup.roundName ?? 'Playing')
            : cup.finished
                ? 'Finished'
                : '';
    return HuudCard(
      highlight: !cup.finished,
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Stack(clipBehavior: Clip.none, children: [
          HuudGameArt(cup.gameType, size: 64),
          const Positioned(right: -6, bottom: -6, child: Text('🏆', style: TextStyle(fontSize: 24))),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (cup.playing) const HuudLiveChip(label: 'Championship'),
            if (cup.playing) const SizedBox(height: 6),
            Text(cup.name,
                key: const ValueKey('cup-name'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: n.ink)),
            const SizedBox(height: 2),
            Text(subtitle,
                key: const ValueKey('cup-status'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: h.orangeText)),
            const SizedBox(height: 4),
            Text(
                'Knockout · ${cup.size} players · '
                '${cup.roundTiming == 'sequential' ? 'one match at a time' : 'matches at once'}'
                '${cup.spectatorsAllowed ? '' : ' · players only'}',
                style: TextStyle(fontSize: 13, color: n.mute)),
          ]),
        ),
      ]),
    );
  }

  // -------------------------------------------------------- registration

  List<Widget> _registration(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final left = cup.size - cup.players.length;
    return [
      HuudCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('Players', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: n.ink)),
            const Spacer(),
            Text('${cup.players.length} / ${cup.size}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: h.orangeText)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: cup.players.length / cup.size,
              minHeight: 8,
              backgroundColor: n.plate,
              color: h.orange,
            ),
          ),
          const SizedBox(height: 12),
          if (cup.players.isEmpty)
            Text('Nobody yet — be the first!', style: TextStyle(fontSize: 14, color: n.mid))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in cup.players)
                _EntrantChip(
                  entrant: p,
                  me: me,
                  onTap: youAreHost && p.userId != me ? () => onRemovePlayer(p) : null,
                ),
            ]),
          if (youAreHost && cup.players.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Tap someone to free their place.', style: TextStyle(fontSize: 12, color: n.mute)),
          ],
        ]),
      ),
      const SizedBox(height: 14),
      if (!youAreIn)
        _note(context, 'Join the Huud to take part')
      else if (cup.youAreRegistered) ...[
        _note(context, left == 0 ? "You're in ✅ — drawing the bracket…" : "You're in ✅ — waiting for $left more"),
        const SizedBox(height: 10),
        HuudButton(
          key: const ValueKey('cup-withdraw'),
          label: 'Give my place back',
          icon: Icons.undo_rounded,
          kind: HuudButtonKind.plain,
          expand: true,
          busy: busy == 'cup-withdraw',
          onPressed: onWithdraw,
        ),
      ] else
        HuudButton(
          key: const ValueKey('cup-register'),
          label: cup.full ? 'All places are taken' : 'Register to play',
          icon: Icons.how_to_reg_rounded,
          big: true,
          expand: true,
          busy: busy == 'cup-register',
          onPressed: cup.full ? null : onRegister,
        ),
      if (youAreHost) ...[
        const SizedBox(height: 10),
        HuudButton(
          key: const ValueKey('cup-call-off'),
          label: 'Call it off',
          icon: Icons.close_rounded,
          kind: HuudButtonKind.plain,
          expand: true,
          busy: busy == 'cup-close',
          onPressed: onCallOff,
        ),
      ],
    ];
  }

  // -------------------------------------------------------- playing

  List<Widget> _playing(BuildContext context) {
    final n = context.neon;
    final yours = cup.matchById(cup.yourMatchId);
    final live = cup.liveMatches;
    final upNext = cup.matches
        .where((m) => m.round == cup.currentRound && m.status == 'pending' && m.playerA != null && m.playerB != null)
        .toList();
    final mine = cup.player(me);
    final inThisRound = cup.matches.where((m) => m.round == cup.currentRound && m.has(me)).firstOrNull;
    String? standing;
    if (mine != null && yours == null) {
      if (mine.out) {
        standing = "You're out this time — watch the rest 👀";
      } else if (inThisRound != null && inThisRound.done && inThisRound.winnerId == me) {
        standing = "You're through! 🎉 Waiting for the other ${cup.roundName ?? 'matches'}";
      } else if (inThisRound != null && inThisRound.status == 'pending') {
        standing = 'Your match is up next — hang on ⏳';
      }
    }
    final isFinal = cup.roundName == 'Final';
    return [
      if (yours != null) ...[
        _YourMatch(cup: cup, match: yours, me: me, busy: busy == 'match-${yours.id}', onOpen: () => onOpenMatch(yours)),
        const SizedBox(height: 14),
      ],
      if (standing != null) ...[
        _note(context, standing),
        const SizedBox(height: 14),
      ],
      _VoiceLine(listeningTo: listeningTo, cup: cup, me: me),
      const SizedBox(height: 14),
      HuudSectionTitle(isFinal ? 'Championship Final' : 'Live matches', emoji: isFinal ? '🏆' : '🔴'),
      if (live.isEmpty)
        Text('Getting the next boards ready…', style: TextStyle(fontSize: 14, color: n.mid))
      else
        for (final m in live) ...[
          _LiveMatchCard(
            cup: cup,
            match: m,
            me: me,
            big: isFinal,
            listening: listeningTo?.id == m.id,
            busy: busy == 'match-${m.id}',
            onTap: m.has(me) || cup.spectatorsAllowed ? () => onOpenMatch(m) : null,
            onEndBothAbsent: youAreHost && m.aReconnectMs == 0 && m.bReconnectMs == 0 ? () => onEndBothAbsent(m) : null,
          ),
          const SizedBox(height: 10),
        ],
      if (upNext.isNotEmpty) ...[
        const SizedBox(height: 6),
        const HuudSectionTitle('Up next', emoji: '⏳'),
        for (final m in upNext)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(cupMatchTitle(cup, m, me: me),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: n.mid)),
          ),
      ],
      const SizedBox(height: 10),
      const HuudSectionTitle('Bracket', emoji: '🗂️'),
      ChampionshipBracket(cup: cup, me: me),
    ];
  }

  // -------------------------------------------------------- finished

  List<Widget> _finished(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final champion = cup.player(cup.championId);
    final runnerUp = cup.player(cup.runnerUpId);
    return [
      HuudCard(
        highlight: true,
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const Text('🏆', style: TextStyle(fontSize: 48)),
          if (champion == null)
            Text('No champion this time',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: n.ink))
          else ...[
            Avatar(champion.handle, size: 72, imageUrl: champion.avatarUrl),
            const SizedBox(height: 8),
            Text(champion.userId == me ? 'You are the champion!' : '${champion.handle} is the champion!',
                key: const ValueKey('cup-champion'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: h.orangeText)),
          ],
          if (runnerUp != null) ...[
            const SizedBox(height: 6),
            Text('🥈 Runner-up: ${runnerUp.userId == me ? 'You' : runnerUp.handle}',
                key: const ValueKey('cup-runner-up'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: n.mid)),
          ],
        ]),
      ),
      const SizedBox(height: 14),
      const HuudSectionTitle('Bracket', emoji: '🗂️'),
      ChampionshipBracket(cup: cup, me: me),
      const SizedBox(height: 16),
      if (youAreHost) ...[
        HuudButton(
          key: const ValueKey('cup-new'),
          label: 'New championship',
          icon: Icons.emoji_events_rounded,
          big: true,
          expand: true,
          onPressed: onNew,
        ),
        const SizedBox(height: 10),
        HuudButton(
          key: const ValueKey('cup-hang-out'),
          label: 'Hang out',
          icon: Icons.weekend_rounded,
          kind: HuudButtonKind.soft,
          expand: true,
          busy: busy == 'cup-close',
          onPressed: onHangOut,
        ),
      ] else
        _note(context, 'Good games, everyone! The host picks what happens next.'),
      if (youOwn) ...[
        const SizedBox(height: 10),
        HuudButton(
          key: const ValueKey('cup-end-live'),
          label: 'End Live',
          icon: Icons.nights_stay_rounded,
          kind: HuudButtonKind.plain,
          expand: true,
          onPressed: onEndLive,
        ),
      ],
    ];
  }

  Widget _note(BuildContext context, String text) => Text(text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: HuudColors.of(context).orangeText));
}

class _EntrantChip extends StatelessWidget {
  const _EntrantChip({required this.entrant, required this.me, this.onTap});
  final CupEntrant entrant;
  final String? me;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        decoration: BoxDecoration(
          color: n.plate,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: n.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Avatar(entrant.handle, size: 26, imageUrl: entrant.avatarUrl),
          const SizedBox(width: 6),
          Text(entrant.userId == me ? 'You' : entrant.handle,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: n.ink)),
        ]),
      ),
    );
  }
}

/// Your own board, on top, with one big button.
class _YourMatch extends StatelessWidget {
  const _YourMatch({required this.cup, required this.match, required this.me, required this.onOpen, this.busy = false});
  final HuudCup cup;
  final CupMatch match;
  final String? me;
  final VoidCallback onOpen;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final opponent = match.playerA == me ? match.playerB : match.playerA;
    return HuudCard(
      highlight: true,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Your ${match.roundName == 'Final' ? 'Final' : match.roundName}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: HuudColors.of(context).orangeText)),
        const SizedBox(height: 4),
        Text('You vs ${cup.handle(opponent)}',
            key: const ValueKey('cup-your-match'),
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: n.ink)),
        if (match.gameNumber > 1)
          Text('Game ${match.gameNumber} — the last one was a draw',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: n.mid)),
        const SizedBox(height: 14),
        HuudButton(
          key: const ValueKey('cup-play'),
          label: 'Play your match',
          icon: Icons.sports_esports_rounded,
          big: true,
          expand: true,
          busy: busy,
          onPressed: onOpen,
        ),
      ]),
    );
  }
}

/// Which voice you're hearing: the championship lobby or one match.
class _VoiceLine extends StatelessWidget {
  const _VoiceLine({required this.listeningTo, required this.cup, required this.me});
  final CupMatch? listeningTo;
  final HuudCup cup;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final m = listeningTo;
    return Row(children: [
      Icon(Icons.headphones_rounded, size: 18, color: n.mid),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
            m == null ? "You're in the Championship Lobby" : 'Listening to ${cupMatchTitle(cup, m, me: me)}',
            key: const ValueKey('cup-voice-line'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: n.mid)),
      ),
    ]);
  }
}

class _LiveMatchCard extends StatelessWidget {
  const _LiveMatchCard({
    required this.cup,
    required this.match,
    required this.me,
    required this.onTap,
    this.onEndBothAbsent,
    this.big = false,
    this.listening = false,
    this.busy = false,
  });

  final HuudCup cup;
  final CupMatch match;
  final String? me;
  final VoidCallback? onTap, onEndBothAbsent;
  final bool big, listening, busy;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final mine = match.has(me);
    return HuudCard(
      key: ValueKey('cup-match-${match.position}'),
      onTap: busy ? null : onTap,
      highlight: listening || mine,
      padding: EdgeInsets.all(big ? 18 : 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cupMatchTitle(cup, match, me: me),
                  style: TextStyle(fontSize: big ? 22 : 17, fontWeight: FontWeight.w900, color: n.ink)),
              const SizedBox(height: 2),
              Text(
                  [
                    if (match.watching > 0) '${match.watching} watching',
                    if (match.gameNumber > 1) 'game ${match.gameNumber}',
                    if (listening) 'you\'re listening',
                  ].join(' · ').ifEmpty('Live now'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: n.mid)),
            ]),
          ),
          if (busy)
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
          else if (onTap != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: mine ? h.orange : n.plate,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: mine ? kCabinetInk : n.line),
              ),
              child: Text(mine ? 'Play' : 'Watch',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: mine ? h.onOrange : n.ink)),
            ),
        ]),
        if (onEndBothAbsent != null) ...[
          const SizedBox(height: 10),
          HuudButton(
            label: 'Both players are gone — end with no winner',
            icon: Icons.person_off_rounded,
            kind: HuudButtonKind.plain,
            expand: true,
            onPressed: onEndBothAbsent,
          ),
        ],
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// The whole draw, round by round, side by side. Scrolls sideways on a phone.
class ChampionshipBracket extends StatelessWidget {
  const ChampionshipBracket({super.key, required this.cup, required this.me});
  final HuudCup cup;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    if (cup.matches.isEmpty) {
      return Text('The draw happens when every place is filled.', style: TextStyle(fontSize: 14, color: n.mid));
    }
    final rounds = <int, List<CupMatch>>{};
    for (final m in cup.matches) {
      rounds.putIfAbsent(m.round, () => []).add(m);
    }
    Widget name(String? id, String? winner, bool done) {
      final won = done && id != null && id == winner;
      final lost = done && id != null && winner != null && id != winner;
      return Text(id == null ? (done ? '—' : 'TBD') : cup.handle(id, me: me),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: won ? FontWeight.w900 : FontWeight.w700,
            color: won ? h.orangeText : lost ? n.mute : n.ink,
            decoration: lost ? TextDecoration.lineThrough : null,
          ));
    }

    return SingleChildScrollView(
      key: const ValueKey('cup-bracket'),
      scrollDirection: Axis.horizontal,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final entry in rounds.entries) ...[
          SizedBox(
            width: 150,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(entry.value.first.roundName,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: n.mid)),
              const SizedBox(height: 8),
              for (final m in entry.value)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: n.panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: m.live ? h.orange : n.line, width: m.live ? 2 : 1.2),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    name(m.playerA, m.winnerId, m.done),
                    const SizedBox(height: 4),
                    name(m.playerB, m.winnerId, m.done),
                    if (m.live) ...[
                      const SizedBox(height: 4),
                      Text('LIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: h.live)),
                    ],
                    if (m.status == 'bye')
                      Text('bye', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: n.mute)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(width: 10),
        ],
      ]),
    );
  }
}
