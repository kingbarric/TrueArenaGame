import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../spectate/spectate_screen.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';
import 'huud_space_screen.dart';

/// Live Huuds one screen at a time: swipe up for the next, down for the
/// last. Each page looks in without joining (it counts as watching while it's
/// on screen) and offers one big button to come in.
class HuudSwipeScreen extends StatefulWidget {
  const HuudSwipeScreen({super.key, required this.huuds, this.start = 0});

  final List<LiveHuud> huuds;
  final int start;

  @override
  State<HuudSwipeScreen> createState() => _HuudSwipeScreenState();
}

class _HuudSwipeScreenState extends State<HuudSwipeScreen> {
  late final _pages = PageController(initialPage: widget.start);
  late int _page = widget.start;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      backgroundColor: n.bg,
      body: Stack(children: [
        PageView.builder(
          key: const ValueKey('huud-swipe'),
          controller: _pages,
          scrollDirection: Axis.vertical,
          itemCount: widget.huuds.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (context, i) => _WatchPage(
            key: ValueKey('watch-${widget.huuds[i].id}'),
            live: widget.huuds[i],
            active: i == _page,
            last: i == widget.huuds.length - 1,
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              Semantics(
                button: true,
                label: 'Close',
                excludeSemantics: true,
                child: Bouncy(
                  key: const ValueKey('swipe-close'),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: n.panel, shape: BoxShape.circle, border: Border.all(color: n.line, width: 1.4)),
                    child: Icon(Icons.close_rounded, color: n.ink),
                  ),
                ),
              ),
              const Spacer(),
              HuudChip('${_page + 1} of ${widget.huuds.length}', emoji: '📺'),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _WatchPage extends StatefulWidget {
  const _WatchPage({super.key, required this.live, required this.active, required this.last});
  final LiveHuud live;
  final bool active;
  final bool last;

  @override
  State<_WatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends State<_WatchPage> {
  HuudSpace? _huud;
  Timer? _poll;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant _WatchPage old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) _sync();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Only the page on screen keeps "watching".
  void _sync() {
    _poll?.cancel();
    if (!widget.active) return;
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    try {
      final raw = (widget.live.youAreIn
          ? await api.get('/huud-spaces/${widget.live.id}')
          : await api.post('/huud-spaces/${widget.live.id}/watch')) as Map<String, dynamic>;
      if (mounted) setState(() => _huud = HuudSpace.fromJson(raw));
    } catch (_) {
      // Keeps showing what the Live card already knew.
    }
  }

  Future<void> _enter() async {
    final huud = _huud;
    if (huud != null && (huud.youAreIn || huud.joinRequest == 'pending')) {
      await openHuudSpace(context, huud.id, initial: huud);
      return;
    }
    setState(() => _busy = true);
    try {
      final raw = await AppScope.of(context).api.post('/huud-spaces/${widget.live.id}/join') as Map<String, dynamic>;
      if (!mounted) return;
      final joined = HuudSpace.fromJson(raw);
      if (!joined.youAreIn) huudSnack(context, "Asked the host — you'll get in when they say yes ⏳");
      await openHuudSpace(context, joined.id, initial: joined);
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, "That didn't work — check your internet and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
      _load();
    }
  }

  void _watchGame(HuudGame game) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SpectateScreen(
          roomId: game.roomId, gameType: game.gameType, title: 'Watching ${huudGameName(game.gameType)}')));

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final live = widget.live;
    final huud = _huud;
    final host = huud?.host ?? live.host;
    final members = huud?.members ?? live.members;
    final people = huud?.members.length ?? live.memberCount;
    final watching = huud?.watching ?? live.watching;
    final game = huud?.currentGame;
    final gameType = game?.gameType ?? live.gameType;
    final status = game?.status ?? live.gameStatus;
    final inIt = huud?.youAreIn ?? live.youAreIn;
    final asked = huud?.joinRequest == 'pending';
    final (label, icon) = inIt
        ? ('Go in', Icons.arrow_forward_rounded)
        : asked
            ? ('Waiting for the host', Icons.hourglass_top_rounded)
            : live.privacy == HuudPrivacy.private
                ? ('Ask to join', Icons.front_hand_rounded)
                : ('Join Huud', Icons.login_rounded);
    final doing = gameType == null
        ? 'Hanging out 💬'
        : switch (status) {
            'playing' => 'Playing ${huudGameName(gameType)}',
            'waiting' => 'Getting ready for ${huudGameName(gameType)}',
            _ => 'Just played ${huudGameName(gameType)}',
          };

    return HuudBackdrop(
      background: huud?.background,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: huud?.background == null
                ? [h.orange.withValues(alpha: 0.35), n.bg, n.bg]
                : [Colors.transparent, Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 72, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Avatar(host?.name ?? live.name, size: 96, imageUrl: host?.avatarUrl)),
              const SizedBox(height: 14),
              Text(live.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 30, height: 1.1, fontWeight: FontWeight.w900, color: n.ink)),
              const SizedBox(height: 6),
              Text(host == null ? '' : '👑 Host: ${host.handle}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: n.mid)),
              const SizedBox(height: 14),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                const HuudLiveChip(),
                HuudChip(live.privacy.label, emoji: live.privacy.emoji),
                HuudChip(people == 1 ? '1 in here' : '$people in here', emoji: '👥'),
                if (watching > 0) HuudChip('$watching watching', emoji: '👀'),
              ]),
              const SizedBox(height: 20),
              HuudCard(
                highlight: status == 'playing',
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    gameType == null
                        ? const SizedBox(
                            width: 72, height: 72, child: Center(child: Text('💬', style: TextStyle(fontSize: 40))))
                        : HuudGameArt(gameType, size: 72),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (status == 'playing') const HuudLiveChip(label: 'Playing'),
                        const SizedBox(height: 4),
                        Text(doing, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: n.ink)),
                        if (game != null && !game.finished)
                          Text('${game.players} / ${game.seats} seats taken',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: n.mid)),
                      ]),
                    ),
                  ]),
                  if (game != null && game.playing) ...[
                    const SizedBox(height: 14),
                    HuudButton(
                      key: ValueKey('swipe-watch-${live.id}'),
                      label: 'Watch the game',
                      icon: Icons.visibility_rounded,
                      kind: HuudButtonKind.soft,
                      expand: true,
                      onPressed: () => _watchGame(game),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                HuudAvatarStack(people: members, total: people, size: 40, max: 6),
              ]),
              const Spacer(),
              HuudButton(
                key: ValueKey('swipe-enter-${live.id}'),
                label: label,
                icon: icon,
                big: true,
                expand: true,
                busy: _busy,
                onPressed: _enter,
              ),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(widget.last ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded, color: n.mute),
                const SizedBox(width: 4),
                Flexible(
                    child: Text(
                        widget.last ? 'That was the last one — swipe down to go back' : 'Swipe up for the next Huud',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: n.mute))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
