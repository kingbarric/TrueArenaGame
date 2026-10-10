import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../games/game_select_screen.dart' show gameCatalog;
import 'competitive_widgets.dart';
import 'player_profile_screen.dart';

/// One place on the all-time board.
class RankedPlayer {
  const RankedPlayer({
    required this.rank,
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.strength,
    required this.gamesPlayed,
    required this.wins,
    required this.draws,
    required this.losses,
  });

  final int rank;
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final int strength;
  final int gamesPlayed;
  final int wins;
  final int draws;
  final int losses;

  factory RankedPlayer.fromJson(Map<String, dynamic> j) {
    int i(String k) => (j[k] as num?)?.toInt() ?? 0;
    return RankedPlayer(
      rank: i('rank'),
      userId: j['userId'].toString(),
      username: j['username'] as String? ?? '',
      displayName: j['displayName'] as String? ?? '',
      avatarUrl: j['avatarUrl'] as String?,
      strength: i('strength'),
      gamesPlayed: i('gamesPlayed'),
      wins: i('wins'),
      draws: i('draws'),
      losses: i('losses'),
    );
  }

  String get handle => username.isNotEmpty ? username : displayName;
}

/// All-time rankings: the top 20 on PlayHuud for each game, and overall,
/// by strength (every finished game adds to it — the shield's number).
class AllTimeRankingsScreen extends StatefulWidget {
  const AllTimeRankingsScreen({super.key, this.initialGame});

  /// A game to open on (server id, e.g. `whot`); null = Overall.
  final String? initialGame;

  @override
  State<AllTimeRankingsScreen> createState() => _AllTimeRankingsScreenState();
}

class _AllTimeRankingsScreenState extends State<AllTimeRankingsScreen> {
  late String? _game = widget.initialGame;
  List<RankedPlayer>? _top;
  RankedPlayer? _you;
  String? _error;
  int _request = 0;

  /// Overall, then every game, by the server's id (Word Bluff is `wordbluff`).
  static final _games = <(String?, String)>[
    (null, 'Overall'),
    for (final g in gameCatalog)
      if (g.available) (g.id == 'bluff' ? 'wordbluff' : g.id, '${g.emoji} ${g.name}'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final ticket = ++_request;
    setState(() {
      _top = null;
      _error = null;
    });
    try {
      final q = _game == null ? '' : '?gameType=${Uri.encodeQueryComponent(_game!)}';
      final raw = (await AppScope.of(context).api.get('/rankings/all-time$q') as Map).cast<String, dynamic>();
      if (!mounted || ticket != _request) return;
      setState(() {
        _top = [
          for (final e in (raw['top'] as List? ?? const [])) RankedPlayer.fromJson((e as Map).cast<String, dynamic>()),
        ];
        _you = raw['you'] == null ? null : RankedPlayer.fromJson((raw['you'] as Map).cast<String, dynamic>());
      });
    } catch (_) {
      if (mounted && ticket == _request) setState(() => _error = "We couldn't load the rankings. Pull down to try again.");
    }
  }

  void _pick(String? game) {
    if (game == _game) return;
    setState(() => _game = game);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final me = AppScope.of(context).user?.id;
    final top = _top;
    final youOutside = _you != null && (top == null || !top.any((p) => p.userId == _you!.userId));
    return Scaffold(
      appBar: AppBar(title: const Text('All-time rankings')),
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              children: [
                for (final (id, label) in _games)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('rank-game-${id ?? 'overall'}'),
                      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                      selected: _game == id,
                      onSelected: (_) => _pick(id),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
            child: Text('Top 20 of all time · every game you finish adds to your strength',
                style: TextStyle(fontSize: 13, color: n.mute)),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: n.mid)),
                      ),
                    ])
                  : top == null
                      ? const Center(child: CircularProgressIndicator())
                      : top.isEmpty
                          ? ListView(children: [
                              Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text('Nobody on this board yet — play a game and be the first!',
                                    key: const ValueKey('rank-empty'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: n.mid, fontSize: 15)),
                              ),
                            ])
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                              children: [
                                for (final p in top) _row(n, p, mine: p.userId == me),
                              ],
                            ),
            ),
          ),
          if (youOutside)
            Container(
              key: const ValueKey('rank-you'),
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              decoration: BoxDecoration(color: n.panel, border: Border(top: BorderSide(color: n.line))),
              child: _row(n, _you!, mine: true),
            ),
        ]),
      ),
    );
  }

  Widget _row(NeonColors n, RankedPlayer p, {required bool mine}) {
    final medal = switch (p.rank) { 1 => '🥇', 2 => '🥈', 3 => '🥉', _ => null };
    return Padding(
      key: ValueKey('rank-row-${p.userId}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: NeonCard(
        accent: mine ? n.gold : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: p.username.isEmpty
            ? null
            : () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => PlayerProfileScreen(username: p.username))),
        child: Row(children: [
          SizedBox(
            width: 38,
            child: medal != null
                ? Text(medal, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24))
                : Text('#${p.rank}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: n.mid)),
          ),
          const SizedBox(width: 8),
          PlayerAvatar(name: p.handle, avatarUrl: p.avatarUrl, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mine ? '${p.handle} (you)' : p.handle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: n.ink)),
              Text('${p.gamesPlayed} games · ${p.wins} W · ${p.draws} D · ${p.losses} L',
                  style: TextStyle(fontSize: 12, color: n.mute)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${p.strength}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: n.gold)),
            Text('STRENGTH', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: n.mute, letterSpacing: 1)),
          ]),
        ]),
      ),
    );
  }
}
