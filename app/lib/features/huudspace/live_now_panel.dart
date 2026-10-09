import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../spectate/spectate_screen.dart';
import '../spectate/spectator_discovery_screen.dart' show DiscoverableRoom;
import 'create_huud_sheet.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';
import 'huud_space_screen.dart';
import 'huud_swipe_screen.dart';

/// The Live tab's first page: Huuds going on right now (yours, your friends'
/// and public ones) and games you can watch.
class LiveNowPanel extends StatefulWidget {
  const LiveNowPanel({super.key, this.bottomPadding = 130});
  final double bottomPadding;

  @override
  State<LiveNowPanel> createState() => _LiveNowPanelState();
}

class _LiveNowPanelState extends State<LiveNowPanel> {
  List<LiveHuud>? _huuds;
  List<DiscoverableRoom> _games = const [];
  String? _error;
  String? _joining;
  StreamSubscription? _events;
  Timer? _poll;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _events = AppScope.of(context).huudSpaceEvents.listen(_onEvent);
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load());
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _onEvent(Map<String, dynamic> event) {
    _load();
    final data = (event['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (data['event'] != 'invited' || !mounted) return;
    final id = data['huudSpaceId'] as String;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("You're invited to a Huud! 🎉", style: TextStyle(fontSize: 15)),
      action: SnackBarAction(label: 'Open', onPressed: () => openHuudSpace(context, id)),
    ));
  }

  @override
  void dispose() {
    _events?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    if (api.bearer == null) return;
    try {
      final results = await Future.wait([
        api.get('/huud-spaces/live'),
        // Watching games needs an account; a guest just sees Huuds.
        api.get('/rooms/discoverable').catchError((Object _) => const []),
      ]);
      if (!mounted) return;
      setState(() {
        _huuds = (results[0] as List).map((e) => LiveHuud.fromJson((e as Map).cast<String, dynamic>())).toList();
        _games = ((results[1] as List?) ?? const [])
            .map((e) => DiscoverableRoom.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "We couldn't reach PlayHuud. Pull down to try again.");
    }
  }

  Future<void> _enter(LiveHuud huud) async {
    if (huud.youAreIn) {
      await openHuudSpace(context, huud.id);
      if (mounted) _load();
      return;
    }
    setState(() => _joining = huud.id);
    try {
      final raw = await AppScope.of(context).api.post('/huud-spaces/${huud.id}/join') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _joining = null);
      final joined = HuudSpace.fromJson(raw);
      if (!joined.youAreIn) huudSnack(context, "Asked the host — you'll get in when they say yes ⏳");
      await openHuudSpace(context, joined.id, initial: joined);
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, "That didn't work — check your internet and try again.");
    } finally {
      if (mounted) {
        setState(() => _joining = null);
        _load();
      }
    }
  }

  void _watch(DiscoverableRoom room) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SpectateScreen(
            roomId: room.roomId, gameType: room.gameType, title: "${room.hostName}'s ${huudGameName(room.gameType)}"),
      ));

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final huuds = _huuds;
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: HuudSectionTitle('Huuds on now',
                  emoji: '🔴',
                  trailing: huuds == null || huuds.isEmpty ? null : HuudLiveChip(label: '${huuds.length} live')),
            ),
          ),
          if (huuds == null)
            SliverToBoxAdapter(
              child: _error == null
                  ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: HuudFriendlyState(
                        emoji: '📡',
                        title: 'Hmm, no connection',
                        message: _error!,
                        action: HuudButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: _load),
                      ),
                    ),
            )
          else if (huuds.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: HuudFriendlyState(
                  emoji: '😴',
                  title: "Nobody's live right now",
                  message: 'Start a Huud and invite your friends to hang out and play.',
                  action: HuudButton(
                    key: const ValueKey('live-make-huud'),
                    label: 'Make a Huud',
                    icon: Icons.add_rounded,
                    onPressed: () async {
                      await startHuud(context);
                      if (mounted) _load();
                    },
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 440,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  mainAxisExtent: 196,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _LiveHuudCard(
                    huud: huuds[i],
                    busy: _joining == huuds[i].id,
                    onEnter: () => _enter(huuds[i]),
                    onPeek: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => HuudSwipeScreen(huuds: huuds, start: i)))
                        .then((_) => _load()),
                  ),
                  childCount: huuds.length,
                ),
              ),
            ),
          if (_games.isNotEmpty) ...[
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 28, 16, 0),
              sliver: SliverToBoxAdapter(child: HuudSectionTitle('Games to watch', emoji: '👀')),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: _games.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final g = _games[i];
                  return HuudCard(
                    key: ValueKey('live-game-${g.roomId}'),
                    onTap: () => _watch(g),
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      HuudGameArt(g.gameType, size: 52),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text("${g.hostName}'s ${huudGameName(g.gameType)}",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: n.ink)),
                          const SizedBox(height: 2),
                          Text('${g.connectedCount} playing', style: TextStyle(fontSize: 14, color: n.mid)),
                        ]),
                      ),
                      HuudButton(
                        label: 'Watch',
                        icon: Icons.visibility_rounded,
                        kind: HuudButtonKind.soft,
                        onPressed: () => _watch(g),
                      ),
                    ]),
                  );
                },
              ),
            ),
          ],
          SliverToBoxAdapter(child: SizedBox(height: widget.bottomPadding)),
        ],
      ),
    );
  }
}

class _LiveHuudCard extends StatelessWidget {
  const _LiveHuudCard({required this.huud, required this.busy, required this.onEnter, required this.onPeek});
  final LiveHuud huud;
  final bool busy;
  final VoidCallback onEnter;
  final VoidCallback onPeek;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final game = huud.gameType;
    final doing = game == null
        ? 'Hanging out 💬'
        : switch (huud.gameStatus) {
            'playing' => 'Playing ${huudGameName(game)}',
            'waiting' => 'Getting ready for ${huudGameName(game)}',
            _ => 'Just played ${huudGameName(game)}',
          };
    return HuudCard(
      key: ValueKey('live-huud-${huud.id}'),
      onTap: onPeek,
      highlight: huud.youAreIn,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Avatar(huud.host?.name ?? huud.name, size: 44, imageUrl: huud.host?.avatarUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(huud.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: n.ink)),
              Text(huud.host == null ? '' : 'Host: ${huud.host!.firstName}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: n.mid)),
            ]),
          ),
          const HuudLiveChip(),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          if (game != null) ...[HuudGameArt(game, size: 34), const SizedBox(width: 10)],
          Expanded(
            child: Text(doing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: h.orangeText)),
          ),
          HuudChip(huud.privacy.label, emoji: huud.privacy.emoji),
        ]),
        const Spacer(),
        Row(children: [
          HuudAvatarStack(people: huud.members, total: huud.memberCount, size: 30, max: 4),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                (huud.memberCount == 1 ? '1 in here' : '${huud.memberCount} in here') +
                    (huud.watching > 0 ? ' · ${huud.watching} 👀' : ''),
                maxLines: 1,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: n.mid)),
          ),
          HuudButton(
            key: ValueKey('live-enter-${huud.id}'),
            label: huud.youAreIn ? 'Go in' : 'Join',
            icon: huud.youAreIn ? Icons.arrow_forward_rounded : Icons.login_rounded,
            busy: busy,
            onPressed: onEnter,
          ),
        ]),
      ]),
    );
  }
}
