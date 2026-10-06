import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import 'competitive_api.dart';
import 'competitive_models.dart';
import 'competitive_setup_screen.dart';
import 'competitive_widgets.dart';
import 'player_profile_screen.dart';

/// One game's rankings — Global, your country, your state, your friends.
/// Every board ranks the same per-game rating; location only decides which
/// boards you're on. Your own standing stays pinned at the bottom.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, required this.gameType, this.initialScope = LeaderboardScope.global});

  final String gameType;
  final LeaderboardScope initialScope;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  static const _pageSize = 25;

  late final CompetitiveApi _api = CompetitiveApi(AppScope.of(context).api);
  late LeaderboardScope _scope = widget.initialScope;
  Leaderboard? _board;
  List<LeaderboardEntry> _entries = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  /// Names for the Country/State tabs once a board has told us ("Nigeria").
  final Map<LeaderboardScope, String> _scopeNames = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final board = await _api.leaderboard(widget.gameType, scope: _scope, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _board = board;
        _entries = board.entries;
        _hasMore = board.entries.length == _pageSize;
        if (board.scopeName != null) _scopeNames[_scope] = board.scopeName!;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load rankings';
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await _api.leaderboard(widget.gameType,
          scope: _scope, key: _board?.scopeKey, limit: _pageSize, offset: _entries.length);
      if (!mounted) return;
      setState(() {
        _entries = [..._entries, ...next.entries];
        _hasMore = next.entries.length == _pageSize;
      });
    } catch (_) {/* the button stays; a retry is one tap */} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _select(LeaderboardScope scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
    _load();
  }

  Future<void> _completeProfile() async {
    CompetitiveProfile? current;
    try {
      current = await _api.mine();
    } catch (_) {}
    if (!mounted) return;
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => CompetitiveSetupScreen(initial: current)));
    if (saved == true) _load();
  }

  String _tabLabel(LeaderboardScope s) => _scopeNames[s] ?? s.label;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final selfId = AppScope.of(context).user?.id;
    final me = _board?.me;
    return Scaffold(
      appBar: AppBar(title: Text('${gameDisplayName(widget.gameType)} Rankings')),
      body: SafeArea(
        child: Column(children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              children: [
                for (final s in LeaderboardScope.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('scope-${s.wire}'),
                      label: Text(_tabLabel(s)),
                      selected: _scope == s,
                      onSelected: (_) => _select(s),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _body(n, selfId)),
          if (me != null) _MeBar(entry: me, scope: _scope),
        ]),
      ),
    );
  }

  Widget _body(NeonColors n, String? selfId) {
    final t = Theme.of(context).textTheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: TextStyle(color: n.danger)),
          const SizedBox(height: 12),
          NeonButton('Retry', expand: false, style: NeonStyle.ghost, onPressed: _load),
        ]),
      );
    }
    if (_board?.unavailableReason == RankInfo.locationRequired) {
      final what = _scope == LeaderboardScope.region ? 'State' : 'National';
      return ListView(padding: const EdgeInsets.all(20), children: [
        NeonCard(
          accent: n.brand,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Unlock $what rankings', style: t.titleMedium),
            const SizedBox(height: 6),
            Text('Complete your player profile to see where you rank in your '
                '${_scope == LeaderboardScope.region ? 'state' : 'country'}.',
                style: t.bodySmall?.copyWith(color: n.mid)),
            const SizedBox(height: 14),
            NeonButton('Complete profile', onPressed: _completeProfile),
          ]),
        ),
      ]);
    }
    if (_entries.isEmpty) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        NeonCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('No ranked players yet', style: t.titleMedium),
            const SizedBox(height: 6),
            Text(
              _scope == LeaderboardScope.friends
                  ? 'None of your friends has played a ranked ${gameDisplayName(widget.gameType)} match yet.'
                  : 'Players appear here after completing their placement games. Be the first.',
              style: t.bodySmall?.copyWith(color: n.mid),
            ),
          ]),
        ),
      ]);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        itemCount: _entries.length + (_hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _entries.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: NeonButton(_loadingMore ? 'Loading…' : 'Load more',
                  style: NeonStyle.ghost, onPressed: _loadingMore ? null : _loadMore),
            );
          }
          final e = _entries[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LeaderboardRow(
              entry: e,
              isMe: e.userId == selfId,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlayerProfileScreen(username: e.username, focusGame: widget.gameType))),
            ),
          );
        },
      ),
    );
  }
}

class LeaderboardRow extends StatelessWidget {
  const LeaderboardRow({super.key, required this.entry, this.isMe = false, this.onTap});

  final LeaderboardEntry entry;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = Theme.of(context).textTheme;
    final e = entry;
    final podium = switch (e.rank) {
      1 => n.gold,
      2 => const Color(0xffc9d1d9),
      3 => const Color(0xffcd8b55),
      _ => null,
    };
    return NeonCard(
      onTap: onTap,
      accent: isMe ? n.jade : podium,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        SizedBox(
          width: 44,
          child: Text(e.rank == 0 ? '—' : '#${groupedNumber(e.rank)}',
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: t.titleMedium?.copyWith(
                  color: podium ?? n.mid, fontWeight: FontWeight.w900, fontSize: e.rank > 999 ? 11 : 15)),
        ),
        PlayerAvatar(name: e.displayName, avatarUrl: e.avatarUrl, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(e.displayName,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (e.founding != null) ...[const SizedBox(width: 6), FoundingBadge(e.founding!, compact: true)],
            ]),
            const SizedBox(height: 2),
            Text(
              [
                if (e.playhuudId != null) e.playhuudId!,
                '${e.gamesPlayed} games',
                if (e.gamesPlayed > 0) '${(e.winRate * 100).round()}% W',
                if (e.tournamentWins > 0) '🏆 ${e.tournamentWins}',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.labelSmall?.copyWith(color: n.mute),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${e.rating}', style: t.titleMedium?.copyWith(color: n.gold, fontWeight: FontWeight.w900)),
          if (e.provisional)
            Text('PROV.', style: TextStyle(color: n.mute, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ]),
      ]),
    );
  }
}

/// Your own standing, pinned under whichever page you're looking at.
class _MeBar extends StatelessWidget {
  const _MeBar({required this.entry, required this.scope});

  final LeaderboardEntry entry;
  final LeaderboardScope scope;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: BoxDecoration(color: n.panel, border: Border(top: BorderSide(color: n.line))),
      child: Row(children: [
        Text('YOU', style: TextStyle(color: n.mute, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.2)),
        const SizedBox(width: 12),
        Text(entry.rank == 0 ? 'Placement games' : '#${groupedNumber(entry.rank)}',
            key: const ValueKey('leaderboard-me-rank'),
            style: t.titleMedium?.copyWith(color: entry.rank == 0 ? n.mid : n.gold, fontWeight: FontWeight.w900)),
        const Spacer(),
        Text('${entry.rating}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(width: 4),
        Text('RATING', style: TextStyle(color: n.mute, fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 1)),
      ]),
    );
  }
}
