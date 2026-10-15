import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/hangout_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../spectate/spectate_screen.dart';
import 'huud_kit.dart';
import 'huud_preview_voice.dart';
import 'huud_voice.dart';
import 'huud_space_models.dart';
import 'huud_space_screen.dart';

/// Live Huuds one screen at a time: swipe up for the next, down for the
/// last. Each page looks in without joining (it counts as watching while it's
/// on screen) and offers one big button to come in.
class HuudSwipeScreen extends StatefulWidget {
  const HuudSwipeScreen(
      {super.key,
      required this.huuds,
      this.start = 0,
      this.previewVoiceFactory});

  @visibleForTesting
  final HuudPreviewVoice Function(ApiClient)? previewVoiceFactory;

  final List<LiveHuud> huuds;
  final int start;

  @override
  State<HuudSwipeScreen> createState() => _HuudSwipeScreenState();
}

class _HuudSwipeScreenState extends State<HuudSwipeScreen>
    with WidgetsBindingObserver {
  late final _pages = PageController(initialPage: widget.start);
  late int _page = widget.start;
  HuudPreviewVoice? _voice;
  Animation<double>? _cover;
  bool _foreground = true,
      _covered = false,
      _navigating = false,
      _soundOn = true;
  String? _unavailable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HangoutState.instance.addListener(_callChanged);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_voice == null) {
      final api = AppScope.of(context).api;
      _voice = widget.previewVoiceFactory?.call(api) ?? HuudPreviewVoice(api);
      _voice!.addListener(_audioChanged);
      // Previewing replaces the previous Huud's listening, but preserves a call.
      if (HangoutState.instance.active &&
          HangoutState.instance.onOpen != null) {
        unawaited(HuudVoice.instance.leave().whenComplete(_syncAudio));
      }
    }
    final next = ModalRoute.of(context)?.secondaryAnimation;
    if (_cover != next) {
      _cover?.removeListener(_routeChanged);
      _cover = next;
      _cover?.addListener(_routeChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncAudio();
    });
  }

  bool get _visible => _foreground && !_covered && !_navigating;

  void _audioChanged() {
    if (mounted) setState(() {});
  }

  void _callChanged() {
    if (!mounted) return;
    setState(() {});
    _syncAudio();
  }

  void _routeChanged() {
    final covered = (_cover?.value ?? 0) > 0;
    if (!mounted || covered == _covered) return;
    setState(() => _covered = covered);
    _syncAudio();
  }

  void _syncAudio() {
    if (!mounted || _voice == null) return;
    final id = widget.huuds.isEmpty ? null : widget.huuds[_page].id;
    unawaited(_voice!.watch(_visible &&
            _soundOn &&
            !HangoutState.instance.active &&
            id != _unavailable
        ? id
        : null));
  }

  void _availability(String id, bool allowed) {
    if (!mounted || widget.huuds[_page].id != id) return;
    if (!allowed && _unavailable != id) {
      setState(() => _unavailable = id);
      _syncAudio();
    } else if (allowed && _unavailable == id) {
      setState(() => _unavailable = null);
      _syncAudio();
    }
  }

  Future<void> _navigate(Future<void> Function() open) async {
    setState(() => _navigating = true);
    await _voice?.watch(null);
    try {
      if (mounted) await open();
    } finally {
      if (mounted) {
        setState(() => _navigating = false);
        _syncAudio();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() => _foreground = state == AppLifecycleState.resumed);
    _syncAudio();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HangoutState.instance.removeListener(_callChanged);
    _cover?.removeListener(_routeChanged);
    _voice?.removeListener(_audioChanged);
    _voice?.dispose();
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
          onPageChanged: (i) {
            setState(() => _page = i);
            _syncAudio();
          },
          itemBuilder: (context, i) => _WatchPage(
            key: ValueKey('watch-${widget.huuds[i].id}'),
            live: widget.huuds[i],
            active: i == _page && _visible,
            audioStatus: _voice?.status ?? PreviewVoiceStatus.connecting,
            available: _unavailable != widget.huuds[i].id,
            soundOn: _soundOn,
            callActive: HangoutState.instance.active,
            onSound: () {
              setState(() => _soundOn = !_soundOn);
              _syncAudio();
            },
            navigate: _navigate,
            onAvailability: (allowed) =>
                _availability(widget.huuds[i].id, allowed),
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
                        color: n.panel,
                        shape: BoxShape.circle,
                        border: Border.all(color: n.line, width: 1.4)),
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
  const _WatchPage(
      {super.key,
      required this.live,
      required this.active,
      required this.last,
      required this.audioStatus,
      required this.available,
      required this.soundOn,
      required this.callActive,
      required this.onSound,
      required this.navigate,
      required this.onAvailability});
  final PreviewVoiceStatus audioStatus;
  final bool soundOn, callActive, available;
  final VoidCallback onSound;
  final Future<void> Function(Future<void> Function()) navigate;
  final ValueChanged<bool> onAvailability;
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
      final raw = await api.post('/huud-spaces/${widget.live.id}/watch')
          as Map<String, dynamic>;
      if (!mounted || !widget.active) return;
      final huud = HuudSpace.fromJson(raw);
      setState(() => _huud = huud);
      widget.onAvailability(huud.live);
    } on ApiException catch (e) {
      if (mounted && widget.active && (e.status == 403 || e.status == 404)) {
        widget.onAvailability(false);
      }
    } catch (_) {
      // Keeps showing what the Live card already knew.
    }
  }

  Future<void> _enter() => widget.navigate(_enterRoom);

  Future<void> _enterRoom() async {
    final huud = _huud;
    if (huud != null && (huud.youAreIn || huud.joinRequest == 'pending')) {
      await openHuudSpace(context, huud.id, initial: huud);
      return;
    }
    setState(() => _busy = true);
    try {
      final raw = await AppScope.of(context)
          .api
          .post('/huud-spaces/${widget.live.id}/join') as Map<String, dynamic>;
      if (!mounted) return;
      final joined = HuudSpace.fromJson(raw);
      if (!joined.youAreIn)
        huudSnack(
            context, "Asked the host — you'll get in when they say yes ⏳");
      await openHuudSpace(context, joined.id, initial: joined);
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, userErrorMessage);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (widget.active) _load();
      }
    }
  }

  Future<void> _watchGame(HuudGame game) => widget.navigate(() async {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SpectateScreen(
                roomId: game.roomId,
                gameType: game.gameType,
                title: 'Watching ${huudGameName(game.gameType)}')));
      });

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
    // A championship on in the Huud (the card's word for it; gone once the host puts it away).
    final cup =
        huud != null && huud.championshipId == null ? null : live.championship;
    final gameType = cup?.gameType ?? game?.gameType ?? live.gameType;
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
    final doing = cup != null
        ? cup.text
        : gameType == null
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
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                      child: Avatar(host?.name ?? live.name,
                          size: 96, imageUrl: host?.avatarUrl)),
                  const SizedBox(height: 14),
                  Text(live.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 30,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          color: n.ink)),
                  const SizedBox(height: 6),
                  Text(host == null ? '' : '👑 Host: ${host.handle}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: n.mid)),
                  const SizedBox(height: 14),
                  Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        const HuudLiveChip(),
                        HuudChip(live.privacy.label, emoji: live.privacy.emoji),
                        HuudChip(people == 1 ? '1 in here' : '$people in here',
                            emoji: '👥'),
                        if (watching > 0)
                          HuudChip('$watching watching', emoji: '👀'),
                      ]),
                  const SizedBox(height: 8),
                  if (widget.active)
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(
                        key: ValueKey('swipe-sound-${live.id}'),
                        tooltip: widget.soundOn
                            ? 'Mute preview audio'
                            : 'Unmute preview audio',
                        onPressed: widget.onSound,
                        icon: Icon(
                            widget.soundOn && !widget.callActive
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            color: n.ink),
                      ),
                      Flexible(
                          child: Text(
                        !widget.available
                            ? 'This Huud is no longer available'
                            : widget.callActive
                                ? 'Preview audio paused during your call'
                                : !widget.soundOn
                                    ? 'Sound off · your mic stays off'
                                    : switch (widget.audioStatus) {
                                        PreviewVoiceStatus.listening =>
                                          'Listening live · your mic is off',
                                        PreviewVoiceStatus.reconnecting =>
                                          'Reconnecting audio…',
                                        PreviewVoiceStatus.unavailable =>
                                          'Preview audio unavailable',
                                        _ => 'Connecting audio…',
                                      },
                        key: ValueKey('swipe-audio-${live.id}'),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: n.mid),
                      )),
                    ]),
                  const SizedBox(height: 12),
                  HuudCard(
                    highlight: status == 'playing',
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            gameType == null
                                ? const SizedBox(
                                    width: 72,
                                    height: 72,
                                    child: Center(
                                        child: Text('💬',
                                            style: TextStyle(fontSize: 40))))
                                : HuudGameArt(gameType, size: 72),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (status == 'playing')
                                      const HuudLiveChip(label: 'Playing'),
                                    const SizedBox(height: 4),
                                    Text(doing,
                                        style: TextStyle(
                                            fontSize: 19,
                                            fontWeight: FontWeight.w900,
                                            color: n.ink)),
                                    if (game != null && !game.finished)
                                      Text(
                                          '${game.players} / ${game.seats} seats taken',
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: n.mid)),
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
                    HuudAvatarStack(
                        people: members, total: people, size: 40, max: 6),
                  ]),
                  const Spacer(),
                  HuudButton(
                    key: ValueKey('swipe-enter-${live.id}'),
                    label: label,
                    kind: HuudButtonKind.lightOrange,
                    icon: icon,
                    big: true,
                    expand: true,
                    busy: _busy,
                    onPressed: _enter,
                  ),
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(
                        widget.last
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        color: n.mute),
                    const SizedBox(width: 4),
                    Flexible(
                        child: Text(
                            widget.last
                                ? 'That was the last one — swipe down to go back'
                                : 'Swipe up for the next Huud',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: n.mute))),
                  ]),
                ]),
          ),
        ),
      ),
    );
  }
}
