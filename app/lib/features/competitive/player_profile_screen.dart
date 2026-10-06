import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/game_badge.dart';
import '../../widgets/neon.dart';
import 'competitive_api.dart';
import 'competitive_models.dart';
import 'competitive_setup_screen.dart';
import 'competitive_widgets.dart';
import 'leaderboard_screen.dart';
import 'player_card.dart';
import '../status/victory_status.dart';

/// `NG -> 🇳🇬`, from the two regional-indicator code points.
String flagEmoji(String? countryCode) {
  final c = countryCode?.toUpperCase();
  if (c == null || c.length != 2) return '';
  return String.fromCharCodes(c.codeUnits.map((u) => 0x1F1E6 + u - 0x41));
}

/// "🇳🇬 Nigeria · Rivers" — public location only (city appears only when the
/// player opted in, or on your own profile).
String locationLine(CompetitiveLocation? loc) {
  if (loc == null || loc.countryCode == null) return loc?.city ?? '';
  return [
    '${flagEmoji(loc.countryCode)} ${loc.countryName ?? loc.countryCode}',
    if (loc.regionName != null) loc.regionName!,
    if (loc.city != null && loc.city!.isNotEmpty) loc.city!,
  ].join(' · ');
}

/// Name, PlayHuud number, founding status, location — the identity block
/// that sits on top of every competitive profile, own or someone else's.
class CompetitiveIdentityHeader extends StatelessWidget {
  const CompetitiveIdentityHeader({super.key, required this.profile, this.showAvatar = true});

  final CompetitiveProfile profile;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = Theme.of(context).textTheme;
    final p = profile;
    final location = locationLine(p.location);
    return Column(children: [
      if (showAvatar) ...[
        PlayerAvatar(name: p.displayName, avatarUrl: p.avatarUrl, size: 84),
        const SizedBox(height: 12),
        Text(p.displayName.toUpperCase(), style: t.titleLarge?.copyWith(letterSpacing: 1.5)),
        const SizedBox(height: 2),
        Text('@${p.username}', style: t.bodySmall?.copyWith(color: n.mute)),
        const SizedBox(height: 10),
      ],
      if (p.playhuudId != null) PlayhuudIdLabel(p.playhuudId!, fontSize: 14),
      if (p.founding != null) ...[const SizedBox(height: 8), FoundingBadge(p.founding!)],
      if (location.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(location, style: t.bodySmall?.copyWith(color: n.mid, fontWeight: FontWeight.w700)),
      ],
    ]);
  }
}

/// Someone else's competitive profile — reached from a leaderboard row or by
/// tapping a friend. Same cards as your own profile; if they've made their
/// profile private you see who they are and nothing more.
class PlayerProfileScreen extends StatefulWidget {
  const PlayerProfileScreen({super.key, required this.username, this.focusGame, this.statusUserId});

  final String username;
  final String? focusGame;

  /// Set when opened from the friends list, to keep their Status one tap away.
  final String? statusUserId;

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  late final CompetitiveApi _api = CompetitiveApi(AppScope.of(context).api);
  CompetitiveProfile? _profile;
  List<String> _ratedGames = const ['draughts'];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final p = await _api.player(widget.username);
      List<String> rated = _ratedGames;
      try {
        rated = await _api.ratedGames();
      } catch (_) {/* default list is fine */}
      if (mounted) {
        setState(() {
          _profile = p;
          _ratedGames = rated;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load this player');
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = Theme.of(context).textTheme;
    final p = _profile;
    final statusId = widget.statusUserId;
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? '' : '@${p.username}'),
        actions: [
          if (statusId != null && p != null)
            IconButton(
              tooltip: 'Status',
              icon: const Icon(Icons.auto_awesome_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StatusScreen(userId: statusId, title: p.displayName))),
            ),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text(_error!, style: TextStyle(color: n.danger)))
            : p == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(padding: const EdgeInsets.symmetric(vertical: 20), children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: CompetitiveIdentityHeader(profile: p),
                    ),
                    const SizedBox(height: 22),
                    if (p.restricted)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: NeonCard(
                          key: const ValueKey('profile-private'),
                          child: Row(children: [
                            Icon(Icons.lock_rounded, color: n.mute),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text('${p.displayName} keeps their competitive profile private.',
                                  style: t.bodySmall?.copyWith(color: n.mid)),
                            ),
                          ]),
                        ),
                      )
                    else
                      CompetitiveRecordSection(profile: p, own: false, ratedGames: _ratedGames),
                  ]),
      ),
    );
  }
}

/// The player's cards — Overall first, then one per rated game — plus, on
/// your own profile, the prompt to finish your location and the visibility
/// switch. Used on your own profile and on anyone else's.
class CompetitiveRecordSection extends StatelessWidget {
  const CompetitiveRecordSection({
    super.key,
    required this.profile,
    required this.own,
    this.ratedGames = const ['draughts'],
    this.onChanged,
    this.horizontalPadding = 20,
  });

  final CompetitiveProfile profile;
  final bool own;

  /// Inset for the text around the cards; the cards themselves always use
  /// the full width so neighbours can peek in.
  final double horizontalPadding;

  /// Every game that has a rating — each gets a card, blank until played.
  final List<String> ratedGames;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = Theme.of(context).textTheme;
    final cards = buildPlayerCards(profile, ratedGames: ratedGames);
    final side = EdgeInsets.symmetric(horizontal: horizontalPadding);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (own && !profile.profileComplete) ...[
        Padding(
          padding: side,
          child: NeonCard(
            key: const ValueKey('complete-player-profile'),
            accent: n.brand,
            onTap: () async {
              final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => CompetitiveSetupScreen(initial: profile)));
              if (saved == true) onChanged?.call();
            },
            child: Row(children: [
              Icon(Icons.flag_rounded, color: n.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Complete your player profile to unlock National & State rankings.',
                    style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Icon(Icons.chevron_right, color: n.mute, size: 20),
            ]),
          ),
        ),
        const SizedBox(height: 16),
      ],
      Padding(
        padding: side,
        child: Text('PLAYER CARDS', style: t.labelLarge?.copyWith(color: n.gold)),
      ),
      const SizedBox(height: 8),
      PlayerCardCarousel(
        cards: cards,
        onOpen: (card) {
          final game = card.gameType;
          if (game == null) return;
          Navigator.of(context)
              .push(MaterialPageRoute(
                  builder: (_) => GameCompetitiveScreen(profile: profile, gameType: game, own: own)))
              .then((_) => onChanged?.call());
        },
      ),
      const SizedBox(height: 6),
      Center(
        child: Text('Swipe for each game · tap a card for details',
            style: t.labelSmall?.copyWith(color: n.mute)),
      ),
      if (own) ...[
        const SizedBox(height: 8),
        Padding(padding: side, child: _VisibilitySwitch(profile: profile, onChanged: onChanged)),
      ],
      if (profile.achievements.isNotEmpty) ...[
        const SizedBox(height: 14),
        Padding(padding: side, child: Text('ACHIEVEMENTS', style: t.labelLarge?.copyWith(color: n.gold))),
        const SizedBox(height: 10),
        Padding(padding: side, child: AchievementShelf(achievements: profile.achievements)),
      ],
    ]);
  }
}

/// "Public profile" — on by default; off means other players see only your
/// name, avatar and PlayHuud number. You still appear on leaderboards.
class _VisibilitySwitch extends StatefulWidget {
  const _VisibilitySwitch({required this.profile, this.onChanged});

  final CompetitiveProfile profile;
  final VoidCallback? onChanged;

  @override
  State<_VisibilitySwitch> createState() => _VisibilitySwitchState();
}

class _VisibilitySwitchState extends State<_VisibilitySwitch> {
  late bool _public = widget.profile.profilePublic;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _VisibilitySwitch old) {
    super.didUpdateWidget(old);
    if (!_saving) _public = widget.profile.profilePublic;
  }

  Future<void> _set(bool value) async {
    setState(() {
      _public = value;
      _saving = true;
    });
    try {
      await CompetitiveApi(AppScope.of(context).api).updateLocation(profilePublic: value);
      widget.onChanged?.call();
    } catch (_) {
      if (mounted) {
        setState(() => _public = !value);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not update your profile visibility')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = Theme.of(context).textTheme;
    return SwitchListTile(
      key: const ValueKey('profile-public-switch'),
      contentPadding: EdgeInsets.zero,
      value: _public,
      onChanged: _saving ? null : _set,
      title: Text('Public profile', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
      subtitle: Text(
          _public
              ? 'Anyone can open your cards and match history.'
              : 'Others only see your name and PlayHuud number. You still appear in rankings.',
          style: t.labelSmall?.copyWith(color: n.mute)),
    );
  }
}

/// One game in depth: rating, the three ranks, the stat line, badges, and
/// recent matches with their rating changes.
class GameCompetitiveScreen extends StatefulWidget {
  const GameCompetitiveScreen({super.key, required this.profile, required this.gameType, required this.own});

  final CompetitiveProfile profile;
  final String gameType;
  final bool own;

  @override
  State<GameCompetitiveScreen> createState() => _GameCompetitiveScreenState();
}

class _GameCompetitiveScreenState extends State<GameCompetitiveScreen> {
  late final CompetitiveApi _api = CompetitiveApi(AppScope.of(context).api);
  late CompetitiveProfile _profile = widget.profile;
  List<MatchHistoryEntry>? _matches;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMatches());
  }

  Future<void> _loadMatches() async {
    try {
      final m = widget.own
          ? await _api.myMatches(gameType: widget.gameType)
          : await _api.playerMatches(_profile.username, gameType: widget.gameType);
      if (mounted) setState(() => _matches = m);
    } catch (_) {
      if (mounted) setState(() => _matches = const []);
    }
  }

  Future<void> _completeProfile() async {
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => CompetitiveSetupScreen(initial: _profile)));
    if (saved == true) {
      try {
        final fresh = await _api.mine();
        if (mounted) setState(() => _profile = fresh);
      } catch (_) {}
    }
  }

  void _openBoard(LeaderboardScope scope) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LeaderboardScreen(gameType: widget.gameType, initialScope: scope)));

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = Theme.of(context).textTheme;
    final r = _profile.game(widget.gameType) ?? GameRecord(gameType: widget.gameType);
    final s = r.stats;
    final placement = '${r.placementGamesPlayed} / ${r.placementGamesRequired}';
    final region = _profile.location?.regionName;
    final country = _profile.location?.countryName;
    final gameAchievements = _profile.achievements.where((a) => a.gameType == widget.gameType).toList();

    return Scaffold(
      appBar: AppBar(title: Text(r.name)),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          CompetitiveIdentityHeader(profile: _profile, showAvatar: false),
          const SizedBox(height: 18),
          NeonCard(
            accent: r.hasRating && !r.provisional ? n.gold : null,
            child: Row(children: [
              GameBadge(gameId: r.gameType, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.provisional ? 'PROVISIONAL RATING' : 'RATING',
                      style: TextStyle(color: n.mute, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.2)),
                  Text(r.rating?.toString() ?? '—',
                      key: const ValueKey('game-rating'),
                      style: t.displayLarge?.copyWith(fontSize: 44, color: r.provisional ? n.mid : n.gold)),
                  if (r.peakRating != null)
                    Text('Peak ${r.peakRating}', style: t.labelSmall?.copyWith(color: n.mid)),
                ]),
              ),
            ]),
          ),
          if (r.provisional) ...[
            const SizedBox(height: 10),
            NeonCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.hasRating ? 'Placement: $placement ranked games' : 'Not rated yet',
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: r.placementGamesRequired == 0 ? 0 : r.placementGamesPlayed / r.placementGamesRequired,
                    minHeight: 6,
                    backgroundColor: n.plate,
                    color: n.gold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.own
                      ? 'PlayHuud is still finding your level. You join the rankings after ${r.placementGamesRequired} ranked games.'
                      : 'Still in placement — not on the rankings yet.',
                  style: t.labelSmall?.copyWith(color: n.mute, height: 1.4),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 18),
          Text('RANKINGS', style: t.labelLarge?.copyWith(color: n.gold)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: RankTile(
                key: const ValueKey('rank-global'),
                label: 'Global',
                rank: r.ranks.global,
                placement: placement,
                onTap: () => _openBoard(LeaderboardScope.global),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RankTile(
                key: const ValueKey('rank-country'),
                label: country ?? 'Country',
                rank: r.ranks.country,
                placement: placement,
                onTap: () => _openBoard(LeaderboardScope.country),
                onCompleteProfile: widget.own ? _completeProfile : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RankTile(
                key: const ValueKey('rank-region'),
                label: region ?? 'State',
                rank: r.ranks.region,
                placement: placement,
                onTap: () => _openBoard(LeaderboardScope.region),
                onCompleteProfile: widget.own ? _completeProfile : null,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _openBoard(LeaderboardScope.global),
              icon: const Icon(Icons.leaderboard_rounded, size: 18),
              label: const Text('View rankings'),
            ),
          ),
          const SizedBox(height: 8),
          Text('RANKED RECORD', style: t.labelLarge?.copyWith(color: n.gold)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.1, // room for the label + number at phone widths
            children: [
              StatTile('Games', '${s.gamesPlayed}'),
              StatTile('Win rate', s.gamesPlayed == 0 ? '—' : '${(s.winRate * 100).round()}%', accent: n.jade),
              StatTile('W / L / D', '${s.wins}/${s.losses}/${s.draws}'),
              StatTile('Streak', '${s.currentWinStreak}', accent: s.currentWinStreak >= 3 ? n.gold : null),
              StatTile('Best streak', '${s.bestWinStreak}'),
              StatTile('Titles', '${s.tournamentWins}', accent: s.tournamentWins > 0 ? n.gold : null),
            ],
          ),
          if (s.top100Wins > 0 || s.casualGames > 0) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (s.top100Wins > 0) '⚔ ${s.top100Wins} wins over Top-100 players',
                if (s.casualGames > 0) '${s.casualGames} casual games',
              ].join(' · '),
              style: t.labelSmall?.copyWith(color: n.mid),
            ),
          ],
          if (gameAchievements.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('ACHIEVEMENTS', style: t.labelLarge?.copyWith(color: n.gold)),
            const SizedBox(height: 10),
            AchievementShelf(achievements: gameAchievements),
          ],
          const SizedBox(height: 18),
          Text('RECENT MATCHES', style: t.labelLarge?.copyWith(color: n.gold)),
          const SizedBox(height: 10),
          if (_matches == null)
            const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          else if (_matches!.isEmpty)
            Text('No matches yet.', style: t.bodySmall?.copyWith(color: n.mute))
          else
            for (final m in _matches!) Padding(padding: const EdgeInsets.only(bottom: 8), child: MatchRow(match: m)),
        ]),
      ),
    );
  }
}

class MatchRow extends StatelessWidget {
  const MatchRow({super.key, required this.match});

  final MatchHistoryEntry match;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = Theme.of(context).textTheme;
    final m = match;
    final (label, color) = switch (m.outcome) {
      'won' => ('W', n.jade),
      'tied' => ('D', n.mid),
      _ => ('L', n.danger),
    };
    final opponent = m.opponents.isEmpty
        ? 'Unknown'
        : m.opponents.map((o) => o.isBot ? '${o.displayName} (agent)' : o.displayName).join(', ');
    final opponentRating = m.opponents.length == 1 ? m.opponents.first.ratingBefore : null;
    return NeonCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('vs $opponent${opponentRating == null ? '' : ' ($opponentRating)'}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              [
                m.championship ? 'Championship' : (m.ranked ? 'Ranked' : 'Casual'),
                if (m.completedAt != null) _ago(m.completedAt!),
              ].join(' · '),
              style: t.labelSmall?.copyWith(color: n.mute),
            ),
          ]),
        ),
        if (m.ranked)
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            RatingDelta(m.ratingDelta),
            if (m.ratingAfter != null) Text('${m.ratingAfter}', style: t.labelSmall?.copyWith(color: n.mute)),
          ]),
      ]),
    );
  }

  static String _ago(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    if (d.inDays < 30) return '${d.inDays}d ago';
    return '${when.day}/${when.month}/${when.year}';
  }
}
