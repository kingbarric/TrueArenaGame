import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../spectate/watch_live.dart';
import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/compact_list_row.dart';
import '../../widgets/game_badge.dart';
import '../../widgets/neon.dart';
import '../competitive/player_profile_screen.dart';
import '../draughts/championships_screen.dart';
import '../friends/invite_contacts_screen.dart';
import '../lobby/joined_room_screen.dart';
import '../notifications/notifications_screen.dart';
import '../onboarding/guest_gate.dart';
import '../profile/profile_screen.dart';
import '../calls/hangouts_screen.dart';
import 'huud_models.dart';

/// The Huud — PlayHuud's lobby feed, one tab in the shell.
///
/// Two tabs: **Your Huud** (you and your friends: their open games, their
/// wins, challenges sent to you) comes first, then **For you** (the whole
/// public lobby). Both read `GET /huud/feed`; every open game on it is a
/// real lobby room, so Join is the ordinary `POST /rooms/join` and lands in
/// the same `JoinedRoomScreen` as a typed huud code.
class HuudScreen extends StatefulWidget {
  const HuudScreen({super.key});

  @override
  State<HuudScreen> createState() => _HuudScreenState();
}

/// The games a request or challenge can be for, in the order the composer
/// offers them.
const _postableGames = ['draughts', 'chess', 'whot', 'ludo', 'goosi', 'wordbluff', 'truearena'];

const _requestTtl = Duration(minutes: 15);
const _challengeTtl = Duration(minutes: 10);

class _HuudScreenState extends State<HuudScreen> {
  HuudTab _tab = HuudTab.friends;
  HuudFilter _filter = HuudFilter.all;

  /// Last result per tab+filter, so flipping tabs shows something at once
  /// while the fresh copy loads.
  final _cache = <String, List<HuudItem>>{};
  bool _loading = false;
  String? _error;
  int _loadGeneration = 0;

  List<HuudPerson> _friends = const [];
  Set<String> _ratedGames = const {'draughts'};

  final _scroll = ScrollController();
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  String _composerGame = 'draughts';
  bool _ranked = false;
  bool _posting = false;

  final _search = TextEditingController();
  Timer? _searchDebounce;
  bool _searching = false;
  List<HuudPerson> _searchResults = const [];

  /// Re-renders "8 min left" and drops expired requests between reloads.
  Timer? _tick;
  StreamSubscription? _events;
  bool _started = false;

  String get _key => '${_tab.wire}-${_filter.wire}';
  List<HuudItem>? get _items => _cache[_key];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final app = AppScope.of(context);
    _events = app.huudEvents.listen(_onHuudEvent);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadFriends();
      _loadRatedGames();
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    _tick?.cancel();
    _searchDebounce?.cancel();
    _scroll.dispose();
    _composer.dispose();
    _composerFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- data

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final key = _key;
    setState(() {
      _loading = true;
      _error = null;
    });
    final app = AppScope.of(context);
    try {
      final raw = await app.api.get('/huud/feed?tab=${_tab.wire}&filter=${_filter.wire}') as List;
      final items = raw.map((e) => HuudItem.fromJson((e as Map).cast<String, dynamic>())).toList();
      if (!mounted) return;
      setState(() => _cache[key] = items);
    } on ApiException catch (e) {
      if (mounted && generation == _loadGeneration) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && generation == _loadGeneration) setState(() => _error = 'Could not reach the server');
    } finally {
      if (mounted && generation == _loadGeneration) setState(() => _loading = false);
    }
  }

  Future<void> _loadFriends() async {
    final app = AppScope.of(context);
    if (app.identity == Identity.guest) return;
    try {
      final raw = await app.api.get('/friends') as List;
      if (!mounted) return;
      setState(() => _friends = raw
          .map((e) => (e as Map).cast<String, dynamic>())
          // Cyber Agents sit in the friends list too; they're never "online".
          .where((j) => j['agentGameType'] == null)
          .map((j) => HuudPerson.fromJson({...j, 'friend': true}))
          .toList());
    } catch (_) {
      // the strip just stays empty — the feed itself still works
    }
  }

  Future<void> _loadRatedGames() async {
    try {
      final raw = await AppScope.of(context).api.get('/competitive/games') as List;
      if (mounted) setState(() => _ratedGames = raw.map((e) => e.toString()).toSet());
    } catch (_) {
      // keep the default
    }
  }

  void _onHuudEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final data = (event['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final from = data['fromName'] as String? ?? 'Someone';
    final game = huudGameNames[data['gameType']] ?? data['gameType'] ?? 'a game';
    final String text;
    if (event['type'] == 'HUUD_CHALLENGE') {
      text = '$from challenged you to $game';
    } else {
      text = data['answer'] == 'accepted'
          ? '$from accepted your challenge — your lobby is waiting'
          : '$from can\'t play right now';
    }
    _cache.removeWhere((key, _) => key.startsWith(HuudTab.friends.wire));
    if (_tab == HuudTab.friends) _load();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      action: event['type'] == 'HUUD_CHALLENGE' && _tab != HuudTab.friends
          ? SnackBarAction(label: 'View', onPressed: () => _switchTab(HuudTab.friends))
          : null,
    ));
  }

  void _switchTab(HuudTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _error = null;
    });
    _load();
  }

  void _switchFilter(HuudFilter filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      _error = null;
    });
    _load();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final raw = await AppScope.of(context).api.get('/friends/search?q=${Uri.encodeQueryComponent(q)}') as List;
        if (!mounted || _search.text.trim() != q) return;
        setState(() => _searchResults = raw
            .map((e) => (e as Map).cast<String, dynamic>())
            .map((j) => HuudPerson.fromJson({...j, 'friend': j['isFriend'] == true}))
            .toList());
      } catch (_) {
        if (mounted) setState(() => _searchResults = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  // ---------------------------------------------------------------- actions

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _enterRoom(RoomView room) async {
    final app = AppScope.of(context);
    await app.rememberActiveRoom(room.id);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => JoinedRoomScreen(room: room)));
    if (mounted) _load();
  }

  Future<void> _post() async {
    if (_posting) return;
    if (!await canHostOrPromptToVerify(context)) return;
    if (!mounted) return;
    setState(() => _posting = true);
    final app = AppScope.of(context);
    try {
      final raw = await app.api.post('/huud/posts', {
        'gameType': _composerGame,
        if (_composer.text.trim().isNotEmpty) 'message': _composer.text.trim(),
        if (_ranked && _ratedGames.contains(_composerGame)) 'ranked': true,
      }) as Map<String, dynamic>;
      _composer.clear();
      _composerFocus.unfocus();
      _cache.clear();
      await _enterRoom(RoomView.fromJson((raw['room'] as Map).cast<String, dynamic>()));
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not post your game');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  /// The floating Post button: back to the top, cursor in the composer.
  void _startPost() {
    if (_search.text.isNotEmpty) {
      _search.clear();
      _onSearchChanged('');
    }
    _scroll.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    _composerFocus.requestFocus();
  }

  Future<void> _join(HuudOpenGame game) async {
    final app = AppScope.of(context);
    try {
      final raw = game.joined
          ? await app.api.get('/rooms/${game.roomId}')
          : await app.api.post('/rooms/join', {'code': game.roomCode});
      await _enterRoom(RoomView.fromJson((raw as Map).cast<String, dynamic>()));
    } on ApiException catch (e) {
      if (isAlreadyPlaying(e) && await watchHuudByCode(app, game.roomCode, context: context)) {
        if (mounted) announceWatching(ScaffoldMessenger.of(context));
        _load();
        return;
      }
      _snack(e.message);
      _load();
    } catch (_) {
      _snack('Could not reach the server');
    }
  }

  Future<void> _challenge(HuudPerson person, {String? suggestedGame}) async {
    if (!await canHostOrPromptToVerify(context)) return;
    if (!mounted) return;
    final game = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GamePickerSheet(
          title: 'Challenge ${person.firstName}', suggested: suggestedGame),
    );
    if (game == null || !mounted) return;
    try {
      final raw = await AppScope.of(context).api.post('/huud/challenges', {
        'targetUserId': person.userId,
        'gameType': game,
      }) as Map<String, dynamic>;
      _cache.clear();
      _snack('Challenge sent to ${person.firstName}');
      await _enterRoom(RoomView.fromJson((raw['room'] as Map).cast<String, dynamic>()));
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not send the challenge');
    }
  }

  Future<void> _accept(HuudOpenGame game) async {
    try {
      final raw = await AppScope.of(context).api.post('/huud/posts/${game.postId}/accept') as Map<String, dynamic>;
      _cache.clear();
      await _enterRoom(RoomView.fromJson(raw));
    } on ApiException catch (e) {
      _snack(e.message);
      _load();
    } catch (_) {
      _snack('Could not reach the server');
    }
  }

  Future<void> _decline(HuudOpenGame game) async {
    try {
      await AppScope.of(context).api.post('/huud/posts/${game.postId}/decline');
      _load();
    } on ApiException catch (e) {
      _snack(e.message);
      _load();
    } catch (_) {
      _snack('Could not reach the server');
    }
  }

  Future<void> _closePost(HuudOpenGame game) async {
    try {
      await AppScope.of(context).api.delete('/huud/posts/${game.postId}');
      _load();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not reach the server');
    }
  }

  void _profile(HuudPerson person) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerProfileScreen(username: person.username, statusUserId: person.userId)));

  void _share(HuudItem item) {
    final text = switch (item.kind) {
      'game_request' => item.game!.mine
          ? 'Join my ${item.gameName} huud on PlayHuud — huud code ${item.game!.roomCode}'
          : '${item.actor.firstName} is looking for a ${item.gameName} game on PlayHuud — huud code ${item.game!.roomCode}',
      'win' => item.win!.streak >= 3
          ? '${item.actor.name} won ${item.win!.streak} ${item.gameName} games in a row on PlayHuud'
          : '${item.actor.name} won at ${item.gameName} on PlayHuud',
      _ when item.tournament != null =>
        '${item.tournament!.name} · ${item.gameName} on PlayHuud\nhttps://playhuud.com/championships/${item.tournament!.code}',
      _ => 'PlayHuud',
    };
    Share.share(text);
  }

  void _openTournament(HuudTournament t) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ChampionshipDetailScreen(id: t.championshipId)))
      .then((_) {
    if (mounted) _load();
  });

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final app = AppScope.of(context);
    final isGuest = app.identity == Identity.guest;
    final searchingNow = _search.text.trim().isNotEmpty;
    final items = (_items ?? const <HuudItem>[])
        .where((i) => i.game == null || i.game!.expiresAt.isAfter(clock.now()))
        .toList();

    return Scaffold(
      floatingActionButton: Padding(
        // Clear of the shell's floating nav pill.
        padding: const EdgeInsets.only(bottom: 78),
        child: FloatingActionButton(
          heroTag: 'huud-post',
          tooltip: 'Post a game request',
          backgroundColor: n.gold,
          foregroundColor: kCabinetInk,
          onPressed: _startPost,
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ),
      body: SafeArea(
        child: Column(children: [
          _header(context, n, app),
          _tabs(context, n),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await Future.wait([_load(), _loadFriends()]);
              },
              // Slivers so only the cards on screen are built — a full page
              // is 40 cards with game art, and building them all up front is
              // what made a long feed hitch on open and on tab switch.
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    sliver: SliverList.list(children: [
                      _searchField(n),
                      const SizedBox(height: 10),
                      if (searchingNow)
                        ..._searchSection(context, n)
                      else ...[
                        _filterChips(n),
                        const SizedBox(height: 12),
                        _composerCard(context, n, app),
                        if (_tab == HuudTab.friends) ...[
                          const SizedBox(height: 16),
                          if (isGuest) _guestCard(context, n) else _friendsOnline(context, n, app),
                        ],
                        const SizedBox(height: 16),
                        if (_error != null) _errorCard(n),
                        if (_items == null && _loading)
                          const Padding(
                              padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                        else if (items.isEmpty && _error == null)
                          _emptyState(context, n),
                      ],
                    ]),
                  ),
                  if (!searchingNow)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) => Padding(
                          key: ValueKey(items[i].id),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _card(context, n, items[i]),
                        ),
                      ),
                    ),
                  // Room to scroll the last card clear of the nav pill and the Post button.
                  const SliverToBoxAdapter(child: SizedBox(height: 128)),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _header(BuildContext context, NeonColors n, AppState app) {
    final me = app.user?.username ?? app.user?.displayName ?? 'Player';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
      child: Row(children: [
        Bouncy(
          feel: BouncyFeel.soft,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          child: Semantics(
            button: true,
            label: 'Your profile',
            child: Avatar(me,
                size: 36,
                emoji: app.avatarEmoji,
                imagePath: app.avatarImagePath,
                imageUrl: app.user?.avatarUrl),
          ),
        ),
        Expanded(
          child: Text('Huud',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ),
        IconButton(tooltip: 'Hangouts', icon: const Icon(Icons.headset_rounded),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HangoutsScreen()))),
        IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_none_rounded),
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
        ),
      ]),
    );
  }

  Widget _tabs(BuildContext context, NeonColors n) {
    Widget tab(HuudTab tab, String label) {
      final active = _tab == tab;
      return Expanded(
        child: Semantics(
          selected: active,
          button: true,
          child: InkWell(
            key: ValueKey('huud-tab-${tab.wire}'),
            onTap: () => _switchTab(tab),
            child: SizedBox(
              height: 48,
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800, color: active ? n.ink : n.mute)),
                const SizedBox(height: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 56,
                  height: 4,
                  decoration: BoxDecoration(
                      color: active ? n.gold : Colors.transparent,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: n.line))),
      child: Row(children: [
        tab(HuudTab.friends, 'Your Huud'),
        tab(HuudTab.forYou, 'For you'),
      ]),
    );
  }

  Widget _searchField(NeonColors n) => TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search players or PlayHuud #',
          prefixIcon: Icon(Icons.search_rounded, color: n.mute),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              : (_search.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        _onSearchChanged('');
                      })
                  : null),
        ),
        onChanged: _onSearchChanged,
      );

  List<Widget> _searchSection(BuildContext context, NeonColors n) {
    if (_searchResults.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(_searching ? 'Searching…' : 'No one matches that search',
              textAlign: TextAlign.center, style: TextStyle(color: n.mute)),
        ),
      ];
    }
    return [
      for (final p in _searchResults)
        CompactListRow(
          onTap: () => _profile(p),
          leading: Avatar(p.name, size: 32, imageUrl: p.avatarUrl),
          title: Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text('@${p.username}${p.friend ? ' · friend' : ''}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
          trailing: _FeedPill('Challenge', outlined: true, onTap: () => _challenge(p)),
        ),
    ];
  }

  Widget _filterChips(NeonColors n) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in HuudFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _FeedPill(f.label,
                  key: ValueKey('huud-filter-${f.wire}'),
                  outlined: _filter != f,
                  quiet: _filter != f,
                  onTap: () => _switchFilter(f)),
            ),
        ]),
      );

  Widget _composerCard(BuildContext context, NeonColors n, AppState app) {
    final me = app.user?.username ?? app.user?.displayName ?? 'Player';
    final canRank = _ratedGames.contains(_composerGame);
    return NeonCard(
      glass: false,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Avatar(me, size: 40, emoji: app.avatarEmoji, imagePath: app.avatarImagePath, imageUrl: app.user?.avatarUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              key: const ValueKey('huud-composer'),
              controller: _composer,
              focusNode: _composerFocus,
              maxLength: 280,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'What do you want to play?',
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final g in _postableGames)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _FeedPill(huudGameNames[g]!,
                        key: ValueKey('huud-game-$g'),
                        small: true,
                        outlined: true,
                        quiet: _composerGame != g,
                        onTap: () => setState(() => _composerGame = g)),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              if (canRank)
                _FeedPill(_ranked ? 'Ranked' : 'Casual',
                    small: true,
                    outlined: true,
                    quiet: !_ranked,
                    icon: _ranked ? Icons.military_tech_rounded : Icons.sports_esports_outlined,
                    onTap: () => setState(() => _ranked = !_ranked)),
              const Spacer(),
              _FeedPill(_posting ? 'Posting…' : 'Post',
                  key: const ValueKey('huud-post'), onTap: _posting ? null : _post),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _guestCard(BuildContext context, NeonColors n) => NeonCard(
        accent: n.jade,
        onTap: () => canUseFriendsOrPromptToVerify(context),
        child: Row(children: [
          Icon(Icons.group_add_rounded, color: n.jade, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Add an account to see your friends\' games, wins and challenges here.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: n.mid)),
          ),
        ]),
      );

  Widget _friendsOnline(BuildContext context, NeonColors n, AppState app) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: app.onlineFriends,
      builder: (context, online, _) {
        final here = _friends.where((f) => online.contains(f.userId)).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('FRIENDS ONLINE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, letterSpacing: 2)),
            ),
            if (_friends.isNotEmpty)
              Text('${here.length} of ${_friends.length}',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: n.jade, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 82,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final f in here)
                _StripPerson(
                  label: f.firstName,
                  onTap: () => _friendSheet(f),
                  child: OnlineAvatar(f.name, online: true, size: 52, imageUrl: f.avatarUrl),
                ),
              if (here.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Center(
                    child: Text(_friends.isEmpty ? 'Add friends to fill your huud' : 'No friends online right now',
                        style: TextStyle(color: n.mute)),
                  ),
                ),
              _StripPerson(
                label: 'Invite',
                labelColor: n.gold,
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const InviteContactsScreen())),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: n.gold, width: 2)),
                  child: Icon(Icons.add_rounded, color: n.gold),
                ),
              ),
            ]),
          ),
        ]);
      },
    );
  }

  Future<void> _friendSheet(HuudPerson f) async {
    final n = context.neon;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              OnlineAvatar(f.name, online: true, size: 44, imageUrl: f.avatarUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.name, style: Theme.of(sheet).textTheme.titleMedium),
                  Text('@${f.username} · online', style: TextStyle(color: n.mute)),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            NeonButton('Challenge ${f.firstName}', onPressed: () {
              Navigator.pop(sheet);
              _challenge(f);
            }),
            const SizedBox(height: 10),
            NeonButton('View profile', style: NeonStyle.ghost, onPressed: () {
              Navigator.pop(sheet);
              _profile(f);
            }),
          ]),
        ),
      ),
    );
  }

  Widget _errorCard(NeonColors n) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: NeonCard(
          accent: n.danger,
          child: Row(children: [
            Expanded(child: Text(_error!, style: TextStyle(color: n.mid))),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ]),
        ),
      );

  Widget _emptyState(BuildContext context, NeonColors n) {
    final friends = _tab == HuudTab.friends;
    final text = switch (_filter) {
      HuudFilter.open => friends ? 'None of your friends are looking for a game.' : 'No open games right now.',
      HuudFilter.wins => friends ? 'No wins from your huud in the last two days.' : 'No big wins in the last two days.',
      HuudFilter.tournaments => 'No tournaments open for registration.',
      HuudFilter.all => friends
          ? 'Nothing from your huud yet. Post a game request or challenge a friend.'
          : 'The lobby is quiet. Post a game request to get one going.',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Column(children: [
        Icon(Icons.track_changes_rounded, size: 40, color: n.mute),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: n.mute)),
      ]),
    );
  }

  Widget _card(BuildContext context, NeonColors n, HuudItem item) {
    final online = AppScope.of(context).onlineFriends.value;
    return switch (item.kind) {
      'challenge' => _ChallengeCard(
          item: item,
          online: online,
          viewerId: AppScope.of(context).user?.id,
          onAccept: () => _accept(item.game!),
          onDecline: () => _decline(item.game!),
          onOpen: () => _join(item.game!),
          onCancel: () => _closePost(item.game!),
          onProfile: _profile),
      'game_request' => _GameRequestCard(
          item: item,
          online: online,
          onJoin: () => _join(item.game!),
          onCancel: () => _closePost(item.game!),
          onChallenge: () => _challenge(item.actor, suggestedGame: item.gameType),
          onProfile: _profile,
          onShare: () => _share(item)),
      'win' => _WinCard(
          item: item,
          online: online,
          mine: item.actor.userId == AppScope.of(context).user?.id,
          onChallenge: () => _challenge(item.actor, suggestedGame: item.gameType),
          onProfile: _profile,
          onShare: () => _share(item)),
      'tournament' => _TournamentCard(
          item: item, onOpen: () => _openTournament(item.tournament!), onShare: () => _share(item)),
      'champion' => _ChampionCard(item: item, onOpen: () => _openTournament(item.tournament!)),
      _ => const SizedBox.shrink(),
    };
  }
}

// ---------------------------------------------------------------- pieces

/// The feed's small rounded button — filled gold for the main action,
/// outlined for the rest. The nav pill's gold, at button size.
class _FeedPill extends StatelessWidget {
  const _FeedPill(this.label,
      {super.key, this.onTap, this.outlined = false, this.quiet = false, this.small = false, this.icon});
  final String label;
  final VoidCallback? onTap;
  final bool outlined;

  /// Outlined in the neutral line colour rather than gold — an unselected chip.
  final bool quiet;
  final bool small;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    // Disabled (no onTap) reads as a status, not a faded button: full-strength muted text.
    final fg = onTap == null ? n.mute : (outlined ? (quiet ? n.ink : n.gold) : kCabinetInk);
    return Semantics(
      button: true,
      selected: outlined && !quiet,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: small ? 34 : 40),
          padding: EdgeInsets.symmetric(horizontal: small ? 12 : 16),
          decoration: BoxDecoration(
            color: outlined ? (quiet ? Colors.transparent : n.gold.withValues(alpha: 0.10)) : n.gold,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: outlined ? (quiet ? n.line : n.gold) : kCabinetInk, width: outlined ? 1.2 : 2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)],
            Text(label,
                style: TextStyle(
                    color: fg,
                    fontWeight: quiet ? FontWeight.w600 : FontWeight.w800,
                    fontSize: small ? 12 : 13)),
          ]),
        ),
      ),
    );
  }
}

/// A muted icon+label action under a card (Challenge, Profile, Share).
class _CardAction extends StatelessWidget {
  const _CardAction({required this.icon, this.label, required this.onTap, this.tooltip});
  final IconData icon;
  final String? label;
  final String? tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final child = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40, minWidth: 40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: n.mute),
            if (label != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: n.mute, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ],
          ]),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class _StripPerson extends StatelessWidget {
  const _StripPerson({required this.label, required this.child, required this.onTap, this.labelColor});
  final String label;
  final Widget child;
  final VoidCallback onTap;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Semantics(
          button: true,
          label: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              width: 58,
              child: Column(children: [
                child,
                const SizedBox(height: 6),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: labelColor)),
              ]),
            ),
          ),
        ),
      );
}

/// Game art, decoded at the size it's shown — the source PNGs are ~1250px
/// square (~6 MB each decoded), far too much to decode for a 48px icon in
/// every card of a scrolling feed.
class _GameArt extends StatelessWidget {
  const _GameArt(this.gameType, this.size);
  final String gameType;
  final double size;

  @override
  Widget build(BuildContext context) {
    final art = GameBadge.artworkFor(huudArtworkId(gameType));
    final px = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return SizedBox(
      width: size,
      height: size,
      child: art == null
          ? GameBadge(gameId: huudArtworkId(gameType), size: size)
          : Image.asset(art, fit: BoxFit.contain, cacheWidth: px, gaplessPlayback: true),
    );
  }
}

/// Name, @handle and age — the top line of every person card.
class _Byline extends StatelessWidget {
  const _Byline({required this.person, required this.at, required this.online, required this.onProfile});
  final HuudPerson person;
  final DateTime at;
  final bool online;
  final void Function(HuudPerson) onProfile;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return InkWell(
      onTap: () => onProfile(person),
      borderRadius: BorderRadius.circular(10),
      child: Row(children: [
        OnlineAvatar(person.name, online: online, size: 40, imageUrl: person.avatarUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: person.name,
                  style: TextStyle(color: n.ink, fontWeight: FontWeight.w800, fontSize: 14)),
              TextSpan(text: '  @${person.username} · ${huudAgo(at)}'),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: n.mute, fontSize: 12.5),
          ),
        ),
      ]),
    );
  }
}

/// The inset game panel inside a card: art, name, a detail line, an action.
class _GamePanel extends StatelessWidget {
  const _GamePanel({required this.gameType, required this.title, required this.detail, this.action, this.footer});
  final String gameType;
  final String title;
  final Widget detail;
  final Widget? action;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: n.plate,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: n.line),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            _GameArt(gameType, 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
                const SizedBox(height: 2),
                detail,
              ]),
            ),
            if (action != null) ...[const SizedBox(width: 8), action!],
          ]),
        ),
        if (footer != null) footer!,
      ]),
    );
  }
}

/// The thin "time left" bar under an open game.
class _TimeLeftBar extends StatelessWidget {
  const _TimeLeftBar({required this.expiresAt, required this.ttl});
  final DateTime expiresAt;
  final Duration ttl;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final left = expiresAt.difference(clock.now());
    final fraction = (left.inSeconds / ttl.inSeconds).clamp(0.0, 1.0);
    return LinearProgressIndicator(
      value: fraction,
      minHeight: 4,
      backgroundColor: n.line,
      color: left.inMinutes < 5 ? n.danger : n.gold,
    );
  }
}

Widget _stackedPlayers(NeonColors n, HuudOpenGame g) {
  const size = 24.0;
  final slots = g.seats.clamp(0, 6);
  return SizedBox(
    height: size,
    width: size + (slots - 1) * (size - 8),
    child: Stack(children: [
      for (var i = 0; i < slots; i++)
        Positioned(
          left: i * (size - 8),
          child: i < g.players.length
              ? Avatar(g.players[i].name, size: size, imageUrl: g.players[i].avatarUrl)
              : Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: n.panel,
                    border: Border.all(color: n.line, width: 1.5),
                  ),
                ),
        ),
    ]),
  );
}

class _GameRequestCard extends StatelessWidget {
  const _GameRequestCard({
    required this.item,
    required this.online,
    required this.onJoin,
    required this.onCancel,
    required this.onChallenge,
    required this.onProfile,
    required this.onShare,
  });
  final HuudItem item;
  final Set<String> online;
  final VoidCallback onJoin, onCancel, onChallenge, onShare;
  final void Function(HuudPerson) onProfile;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final g = item.game!;
    final timeLeft = huudTimeLeft(g.expiresAt);
    return NeonCard(
      glass: false,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Byline(person: item.actor, at: item.at, online: online.contains(item.actor.userId), onProfile: onProfile),
        if (item.message != null) ...[
          const SizedBox(height: 10),
          Text(item.message!, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.35)),
        ],
        const SizedBox(height: 10),
        _GamePanel(
          gameType: item.gameType,
          title: item.gameName,
          detail: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: g.ranked ? 'Ranked' : 'Casual',
                    style: TextStyle(color: g.ranked ? n.gold : n.mute, fontWeight: FontWeight.w800)),
                TextSpan(text: '${g.seats == 2 ? ' · 1v1' : ''} · ${g.seatsTaken}/${g.seats} seats'),
                if (g.filled) TextSpan(text: ' · Filled', style: TextStyle(color: n.ink, fontWeight: FontWeight.w800)),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: n.mute, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (g.seats > 2) ...[const SizedBox(height: 6), _stackedPlayers(n, g)],
          ]),
          action: g.mine || g.joined
              ? _FeedPill('Open lobby', outlined: true, onTap: onJoin)
              : g.filled
                  ? const _FeedPill('Filled', key: ValueKey('huud-filled'), outlined: true, quiet: true,
                      icon: Icons.check_rounded)
                  : _FeedPill(g.seatsLeft == 1 && g.seats > 2 ? 'Take last seat' : 'Join game', onTap: onJoin),
          footer: g.filled ? null : _TimeLeftBar(expiresAt: g.expiresAt, ttl: _requestTtl),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            // Wraps rather than overflows on a narrow phone or at a large text size.
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (g.mine)
                _CardAction(icon: Icons.close_rounded, label: 'Take down', onTap: onCancel)
              else ...[
                _CardAction(icon: Icons.sports_kabaddi_rounded, label: 'Challenge', onTap: onChallenge),
                _CardAction(icon: Icons.person_outline_rounded, label: 'Profile', onTap: () => onProfile(item.actor)),
              ],
              _CardAction(icon: Icons.ios_share_rounded, tooltip: 'Share', onTap: onShare),
            ]),
          ),
          if (timeLeft != null && !g.filled)
            Text(timeLeft,
                maxLines: 1,
                style: TextStyle(
                    color: g.expiresAt.difference(clock.now()).inMinutes < 5 ? n.danger : n.mute,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
        ]),
      ]),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.item,
    required this.online,
    required this.viewerId,
    required this.onAccept,
    required this.onDecline,
    required this.onOpen,
    required this.onCancel,
    required this.onProfile,
  });
  final HuudItem item;
  final Set<String> online;
  final String? viewerId;
  final VoidCallback onAccept, onDecline, onOpen, onCancel;
  final void Function(HuudPerson) onProfile;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final g = item.game!;
    final forMe = g.target?.userId == viewerId;
    final rematch = g.lastOutcome != null;
    final lastLine = switch (g.lastOutcome) {
      'won' => forMe ? 'You won the last one.' : '${g.target?.firstName} won the last one.',
      'lost' => forMe ? '${item.actor.firstName} won the last one.' : 'You won the last one.',
      'tied' => 'The last one was a draw.',
      _ => null,
    };
    final timeLeft = huudTimeLeft(g.expiresAt);
    return NeonCard(
      glass: false,
      accent: forMe ? n.gold : null,
      selected: forMe,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Byline(person: item.actor, at: item.at, online: online.contains(item.actor.userId), onProfile: onProfile),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: forMe ? 'Challenged you to ' : 'You challenged ${g.target?.firstName ?? 'them'} to '),
            TextSpan(
                text: rematch ? 'a ${item.gameName} rematch' : item.gameName,
                style: TextStyle(color: n.gold, fontWeight: FontWeight.w800)),
            TextSpan(text: lastLine == null ? '.' : '. $lastLine'),
          ]),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.35),
        ),
        if (item.message != null) ...[
          const SizedBox(height: 6),
          Text('“${item.message!}”', style: TextStyle(color: n.mid, fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 12),
        if (forMe)
          Row(children: [
            Expanded(child: NeonButton('Accept', key: const ValueKey('huud-accept'), onPressed: onAccept)),
            const SizedBox(width: 10),
            Expanded(child: NeonButton('Not now', style: NeonStyle.ghost, onPressed: onDecline)),
          ])
        else
          Row(children: [
            _FeedPill('Open lobby', outlined: true, onTap: onOpen),
            const SizedBox(width: 6),
            _CardAction(icon: Icons.close_rounded, label: 'Cancel', onTap: onCancel),
            const Spacer(),
            Text('Waiting…', style: TextStyle(color: n.mute, fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
        if (timeLeft != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: _TimeLeftBar(expiresAt: g.expiresAt, ttl: _challengeTtl),
          ),
          const SizedBox(height: 4),
          Text(timeLeft, textAlign: TextAlign.right, style: TextStyle(color: n.mute, fontSize: 11)),
        ],
      ]),
    );
  }
}

class _WinCard extends StatelessWidget {
  const _WinCard({
    required this.item,
    required this.online,
    required this.mine,
    required this.onChallenge,
    required this.onProfile,
    required this.onShare,
  });
  final HuudItem item;
  final Set<String> online;
  final bool mine;
  final VoidCallback onChallenge, onShare;
  final void Function(HuudPerson) onProfile;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final w = item.win!;
    final headline = w.streak >= 3
        ? TextSpan(children: [
            const TextSpan(text: 'Won '),
            TextSpan(
                text: '${w.streak} ${item.gameName} games in a row',
                style: TextStyle(color: n.gold, fontWeight: FontWeight.w800)),
            const TextSpan(text: '.'),
          ])
        : TextSpan(children: [
            TextSpan(text: w.beaten.isEmpty ? 'Won at ' : 'Beat ${_names(w.beaten)} at '),
            TextSpan(text: item.gameName, style: TextStyle(color: n.gold, fontWeight: FontWeight.w800)),
            const TextSpan(text: '.'),
          ]);
    final shown = w.recent.reversed.toList(); // oldest → newest, left to right
    return NeonCard(
      glass: false,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Byline(person: item.actor, at: item.at, online: online.contains(item.actor.userId), onProfile: onProfile),
        const SizedBox(height: 10),
        Text.rich(headline, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.35)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: n.plate, borderRadius: BorderRadius.circular(16), border: Border.all(color: n.line)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.rating != null ? '${item.gameName} rating' : (w.ranked ? 'Ranked' : 'Casual'),
                    style: TextStyle(color: n.mute, fontSize: 11, fontWeight: FontWeight.w600)),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(w.rating != null ? huudGrouped(w.rating!) : (w.streak > 1 ? '${w.streak} wins' : 'Win'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
                  if (w.weekDelta != null && w.weekDelta!.round() != 0) ...[
                    const SizedBox(width: 6),
                    Text('${w.weekDelta! > 0 ? '+' : ''}${w.weekDelta!.round()}',
                        style: TextStyle(
                            color: w.weekDelta! > 0 ? n.jade : n.danger, fontWeight: FontWeight.w800, fontSize: 12)),
                  ],
                ]),
              ]),
            ),
            Semantics(
              label: 'Last ${shown.length} results: ${shown.reversed.join(', ')}',
              child: ExcludeSemantics(
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final r in shown)
                    Container(
                      margin: const EdgeInsets.only(left: 3),
                      width: 7,
                      height: r == 'won' ? 30 : (r == 'tied' ? 18 : 10),
                      decoration: BoxDecoration(
                        color: r == 'won' ? n.jade : (r == 'tied' ? n.mute : n.danger),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.verified_rounded, size: 14, color: n.jade),
          const SizedBox(width: 4),
          Text('Verified from match history',
              style: TextStyle(color: n.jade, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (!mine) _CardAction(icon: Icons.sports_kabaddi_rounded, label: 'Challenge', onTap: onChallenge),
          _CardAction(icon: Icons.person_outline_rounded, label: 'View profile', onTap: () => onProfile(item.actor)),
          _CardAction(icon: Icons.ios_share_rounded, tooltip: 'Share', onTap: onShare),
        ]),
      ]),
    );
  }

  static String _names(List<String> names) =>
      names.length <= 2 ? names.join(' and ') : '${names.first} and ${names.length - 1} others';
}

String _startsLabel(DateTime? at) {
  if (at == null) return 'starts soon';
  final local = at.toLocal();
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return 'starts ${days[local.weekday - 1]} ${local.day} ${months[local.month - 1]}';
}

class _TournamentCard extends StatelessWidget {
  const _TournamentCard({required this.item, required this.onOpen, required this.onShare});
  final HuudItem item;
  final VoidCallback onOpen, onShare;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = item.tournament!;
    return NeonCard(
      glass: false,
      accent: n.gold,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: n.gold, borderRadius: BorderRadius.circular(12), border: Border.all(color: kCabinetInk, width: 2)),
            child: const Icon(Icons.emoji_events_rounded, color: kCabinetInk, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: item.actor.name,
                    style: TextStyle(color: n.ink, fontWeight: FontWeight.w800, fontSize: 14)),
                TextSpan(text: '  opened a tournament · ${huudAgo(item.at)}'),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: n.mute, fontSize: 12.5),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text('Registration is open. ${t.size} spots, knockout.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.35)),
        const SizedBox(height: 10),
        _GamePanel(
          gameType: item.gameType,
          title: t.name,
          detail: Text('${t.joined}/${t.size} registered · ${_startsLabel(t.scheduledAt)}',
              style: TextStyle(color: n.mute, fontSize: 12, fontWeight: FontWeight.w600)),
          footer: InkWell(
            onTap: onOpen,
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: n.gold.withValues(alpha: 0.08), border: Border(top: BorderSide(color: n.line))),
              child: Text(t.viewerJoined ? 'You\'re in · View tournament' : 'View tournament',
                  style: TextStyle(color: n.gold, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: _CardAction(icon: Icons.ios_share_rounded, label: 'Share', onTap: onShare),
        ),
      ]),
    );
  }
}

class _ChampionCard extends StatelessWidget {
  const _ChampionCard({required this.item, required this.onOpen});
  final HuudItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final t = item.tournament!;
    return NeonCard(
      glass: false,
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: n.gold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.emoji_events_rounded, color: n.gold),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${item.actor.name} is the ${t.name} champion',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text([if (item.message != null) item.message!, huudAgo(item.at)].join(' · '),
                style: TextStyle(color: n.mute, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

/// Pick the game for a challenge. The game the card was about goes first.
class _GamePickerSheet extends StatelessWidget {
  const _GamePickerSheet({required this.title, this.suggested});
  final String title;
  final String? suggested;

  @override
  Widget build(BuildContext context) {
    final games = [
      if (suggested != null && _postableGames.contains(suggested)) suggested!,
      ..._postableGames.where((g) => g != suggested),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('They get 10 minutes to accept.', style: TextStyle(color: context.neon.mute)),
          const SizedBox(height: 12),
          for (final g in games)
            CompactListRow(
              key: ValueKey('huud-pick-$g'),
              onTap: () => Navigator.pop(context, g),
              leading: _GameArt(g, 32),
              title: Text(huudGameNames[g]!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              trailing: Icon(Icons.chevron_right_rounded, color: context.neon.mute),
            ),
        ]),
      ),
    );
  }
}
