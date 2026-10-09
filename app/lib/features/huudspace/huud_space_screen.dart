import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/hangout_state.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../calls/call_screen.dart';
import '../lobby/joined_room_screen.dart';
import '../spectate/watch_live.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';

Future<void> openHuudSpace(BuildContext context, String id, {HuudSpace? initial}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => HuudSpaceScreen(id: id, initial: initial)));

/// Inside a Huud: who's here, what's being played, and the next game.
///
/// Two tabs — **Play** and **People** — under a big orange card with the
/// Huud's name, host and code, and a row of round buttons for the things you
/// do most: talk, invite, see people, leave. Everything refreshes by itself
/// (server events, plus a gentle poll as a safety net).
class HuudSpaceScreen extends StatefulWidget {
  const HuudSpaceScreen({super.key, required this.id, this.initial});

  final String id;
  final HuudSpace? initial;

  @override
  State<HuudSpaceScreen> createState() => _HuudSpaceScreenState();
}

enum _Tab { play, people }

class _HuudSpaceScreenState extends State<HuudSpaceScreen> {
  late HuudSpace? _huud = widget.initial;
  String? _error;
  _Tab _tab = _Tab.play;
  String? _busy;
  Timer? _poll;
  StreamSubscription? _events;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final app = AppScope.of(context);
    _events = app.huudSpaceEvents.listen(_onEvent);
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load());
    HangoutState.instance.addListener(_onVoice);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _events?.cancel();
    _poll?.cancel();
    HangoutState.instance.removeListener(_onVoice);
    super.dispose();
  }

  void _onVoice() {
    if (mounted) setState(() {});
  }

  void _onEvent(Map<String, dynamic> event) {
    final data = (event['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (data['huudSpaceId'] != widget.id || !mounted) return;
    if (data['event'] == 'removed') {
      huudSnack(context, 'The host took you out of this Huud.');
      Navigator.of(context).maybePop();
      return;
    }
    if (data['event'] == 'host' && data['by'] != AppScope.of(context).user?.id) {
      _load(thenSay: (huud) => huud.youAreHost ? "You're the host now! 👑" : null);
      return;
    }
    _load();
  }

  Future<void> _load({String? Function(HuudSpace)? thenSay}) async {
    try {
      final raw = await AppScope.of(context).api.get('/huud-spaces/${widget.id}') as Map<String, dynamic>;
      if (!mounted) return;
      final huud = HuudSpace.fromJson(raw);
      setState(() {
        _huud = huud;
        _error = null;
      });
      final say = thenSay?.call(huud);
      if (say != null) huudSnack(context, say);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && _huud == null) setState(() => _error = "We couldn't reach PlayHuud. Pull down to try again.");
    }
  }

  // ---------------------------------------------------------------- actions

  Future<T?> _run<T>(String what, Future<T> Function(ApiClient api) call) async {
    if (_busy != null) return null;
    setState(() => _busy = what);
    try {
      return await call(AppScope.of(context).api);
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, "That didn't work — check your internet and try again.");
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    return null;
  }

  Future<void> _join() async {
    final raw = await _run('join', (api) => api.post('/huud-spaces/${widget.id}/join'));
    if (raw is Map && mounted) {
      setState(() => _huud = HuudSpace.fromJson(raw.cast<String, dynamic>()));
      huudSnack(context, 'You joined! Say hi 👋');
    }
  }

  Future<void> _enterRoom(RoomView room) async {
    final app = AppScope.of(context);
    await app.rememberActiveRoom(room.id);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => JoinedRoomScreen(room: room)));
    if (mounted) _load();
  }

  Future<void> _pickGame(String gameType) async {
    final raw =
        await _run('game-$gameType', (api) => api.post('/huud-spaces/${widget.id}/game', {'gameType': gameType}));
    if (raw is Map && mounted) {
      await _enterRoom(RoomView.fromJson(raw.cast<String, dynamic>()));
    }
  }

  Future<void> _openGame(HuudGame game) async {
    if (_busy != null) return;
    setState(() => _busy = 'open');
    final app = AppScope.of(context);
    try {
      final raw = await app.api.post('/rooms/join', {'code': game.code});
      if (!mounted) return;
      setState(() => _busy = null);
      await _enterRoom(RoomView.fromJson((raw as Map).cast<String, dynamic>()));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      if (isAlreadyPlaying(e)) {
        await watchHuudByCode(app, game.code, context: context);
      } else {
        huudSnack(context, e.message);
        _load();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = null);
        huudSnack(context, "That didn't work — check your internet and try again.");
      }
    }
  }

  Future<void> _putGameAway() async {
    final raw = await _run('clear', (api) => api.delete('/huud-spaces/${widget.id}/game'));
    if (raw is Map && mounted) setState(() => _huud = HuudSpace.fromJson(raw.cast<String, dynamic>()));
  }

  Future<void> _talk(HuudSpace huud) async {
    final hangout = HangoutState.instance;
    if (hangout.roomName == huud.voiceRoom) {
      hangout.show();
      return;
    }
    final path = '/calls/rooms/${huud.voiceRoom}/token';
    final token = await _run('talk', (api) => api.post(path));
    if (token is! Map || !mounted) return;
    final api = AppScope.of(context).api;
    await CallScreen.open(
      context,
      CallScreen(
        roomName: huud.voiceRoom,
        token: token['token'] as String,
        livekitUrl: token['livekitUrl'] as String,
        title: huud.name,
        refreshToken: () async => ((await api.post(path) as Map<String, dynamic>)['token'] as String),
      ),
    );
  }

  void _invite(HuudSpace huud) {
    final code = huud.code;
    if (code == null) return;
    Share.share('Come hang out with me in "${huud.name}" on PlayHuud! 🎮\nOpen the Huud tab and type the code: $code');
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) huudSnack(context, 'Code copied! Send it to a friend.');
  }

  Future<void> _leave(HuudSpace huud) async {
    final others = huud.members.length > 1;
    final ok = await confirmHuud(
      context,
      emoji: '👋',
      title: 'Leave ${huud.name}?',
      message: huud.youAreHost
          ? (others
              ? "${_nextHost(huud)?.firstName ?? 'The next person'} will become the host so everyone can keep playing."
              : "You're the only one here, so the Huud will close.")
          : 'You can come back later with the code.',
      yes: 'Yes, leave',
      danger: true,
    );
    if (!ok || !mounted) return;
    final done = await _run('leave', (api) async {
      await api.post('/huud-spaces/${widget.id}/leave');
      return true;
    });
    if (done == true && mounted) {
      if (HangoutState.instance.roomName == huud.voiceRoom) await HangoutState.instance.leave?.call();
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  HuudMember? _nextHost(HuudSpace huud) =>
      huud.members.where((m) => !m.host).isEmpty ? null : huud.members.firstWhere((m) => !m.host);

  Future<void> _end(HuudSpace huud) async {
    final ok = await confirmHuud(
      context,
      emoji: '🛑',
      title: 'End ${huud.name}?',
      message: 'This closes the Huud for everyone. It will stay in your history.',
      yes: 'End it for everyone',
      danger: true,
    );
    if (!ok || !mounted) return;
    final done = await _run('end', (api) async {
      await api.post('/huud-spaces/${widget.id}/end');
      return true;
    });
    if (done == true && mounted) {
      if (HangoutState.instance.roomName == huud.voiceRoom) await HangoutState.instance.leave?.call();
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _removePerson(HuudMember person) async {
    final ok = await confirmHuud(
      context,
      emoji: '🚪',
      title: 'Take ${person.firstName} out?',
      message: "${person.firstName} will leave this Huud and won't be able to come back in.",
      yes: 'Take them out',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _run('remove', (api) => api.post('/huud-spaces/${widget.id}/members/${person.userId}/remove'));
    _load();
  }

  Future<void> _settings(HuudSpace huud) async {
    final changed = await showHuudSheet<HuudSpace>(
      context,
      builder: (_) => _SettingsSheet(huud: huud),
    );
    if (changed != null && mounted) setState(() => _huud = changed);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final huud = _huud;
    return Scaffold(
      body: SafeArea(
        // The top bar stays put so Back and End are always one tap away.
        child: Column(children: [
          _topBar(n, huud),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (huud == null)
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverToBoxAdapter(
                        child: _error == null
                            ? const Padding(
                                padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                            : HuudFriendlyState(
                                emoji: '🙈',
                                title: "We can't open this Huud",
                                message: _error!,
                                action: HuudButton(
                                    label: 'Try again', icon: Icons.refresh_rounded, onPressed: () => _load()),
                              ),
                      ),
                    )
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      sliver: SliverToBoxAdapter(child: _hero(huud)),
                    ),
                    if (!huud.active)
                      SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: SliverToBoxAdapter(
                          child: HuudFriendlyState(
                            emoji: '👋',
                            title: 'This Huud has ended',
                            message: 'Thanks for hanging out! You can find it in Your Huuds any time.',
                            action: HuudButton(
                                label: 'Back',
                                icon: Icons.arrow_back_rounded,
                                onPressed: () => Navigator.of(context).maybePop()),
                          ),
                        ),
                      )
                    else if (!huud.youAreIn)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        sliver: SliverToBoxAdapter(
                          child: HuudButton(
                            key: const ValueKey('huud-join'),
                            label: 'Join this Huud',
                            icon: Icons.login_rounded,
                            big: true,
                            expand: true,
                            busy: _busy == 'join',
                            onPressed: _join,
                          ),
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(8, 18, 8, 0),
                        sliver: SliverToBoxAdapter(child: _actions(huud)),
                      ),
                    ],
                    if (huud.active) ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                        sliver: SliverToBoxAdapter(child: _tabs(n, huud)),
                      ),
                      if (_tab == _Tab.play) ..._play(n, huud) else ..._people(n, huud),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 120)),
                  ],
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _topBar(NeonColors n, HuudSpace? huud) {
    final h = HuudColors.of(context);
    Widget circle(IconData icon, String label, VoidCallback onTap, {Key? key}) => Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: Bouncy(
            key: key,
            onTap: onTap,
            child: Container(
              width: 48,
              height: 48,
              decoration:
                  BoxDecoration(color: n.panel, shape: BoxShape.circle, border: Border.all(color: n.line, width: 1.4)),
              child: Icon(icon, color: n.ink),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(children: [
        circle(Icons.arrow_back_rounded, 'Back', () => Navigator.of(context).maybePop(),
            key: const ValueKey('huud-back')),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Huud', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: n.ink)),
        ),
        if (huud != null && huud.youAreHost && huud.active)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: circle(Icons.tune_rounded, 'Huud settings', () => _settings(huud),
                key: const ValueKey('huud-settings')),
          ),
        if (huud != null && huud.youAreHost && huud.active)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Semantics(
              button: true,
              label: 'End Huud',
              excludeSemantics: true,
              child: Bouncy(
                key: const ValueKey('huud-end'),
                onTap: () => _end(huud),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: n.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: n.danger.withValues(alpha: 0.5), width: 1.4),
                  ),
                  child: Row(children: [
                    Icon(Icons.stop_circle_rounded, color: n.danger, size: 20),
                    const SizedBox(width: 6),
                    Text('End', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: n.danger)),
                  ]),
                ),
              ),
            ),
          ),
        if (huud == null) Icon(Icons.groups_rounded, color: h.orangeText),
      ]),
    );
  }

  Widget _hero(HuudSpace huud) {
    final me = AppScope.of(context).user?.id;
    final host = huud.host;
    final hostLine = huud.youAreHost
        ? "You're the host"
        : (host == null ? 'Looking for a host' : 'Host: ${host.userId == me ? 'you' : host.firstName}');
    return HuudHeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (huud.active)
            const HuudChip('Live', emoji: '🟢', onOrange: true)
          else
            const HuudChip('Ended', emoji: '🌙', onOrange: true),
          HuudChip(huud.privacy.label, emoji: huud.privacy.emoji, onOrange: true),
        ]),
        const SizedBox(height: 12),
        Text(huud.name,
            key: const ValueKey('huud-title'),
            style: const TextStyle(fontSize: 28, height: 1.1, fontWeight: FontWeight.w900, color: kCabinetInk)),
        const SizedBox(height: 6),
        Text('👑 $hostLine', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kCabinetInk)),
        const SizedBox(height: 14),
        Row(children: [
          HuudAvatarStack(people: huud.members, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              huud.members.length == 1 ? '1 person in here' : '${huud.members.length} people in here',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kCabinetInk),
            ),
          ),
        ]),
        if (huud.code != null) ...[
          const SizedBox(height: 14),
          _codeBox(huud.code!),
        ],
      ]),
    );
  }

  Widget _codeBox(String code) => Semantics(
        button: true,
        label: 'Huud code ${code.split('').join(' ')}. Tap to copy.',
        excludeSemantics: true,
        child: GestureDetector(
          key: const ValueKey('huud-code'),
          onTap: () => _copyCode(code),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kCabinetInk.withValues(alpha: 0.4), width: 1.4),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('HUUD CODE',
                      style:
                          TextStyle(fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w900, color: kCabinetInk)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(code,
                        style: const TextStyle(
                            fontSize: 28, letterSpacing: 6, fontWeight: FontWeight.w900, color: kCabinetInk)),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: kCabinetInk, borderRadius: BorderRadius.circular(14)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.copy_rounded, size: 18, color: Colors.white),
                  SizedBox(width: 6),
                  Text('Copy', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                ]),
              ),
            ]),
          ),
        ),
      );

  Widget _actions(HuudSpace huud) {
    final inVoice = HangoutState.instance.roomName == huud.voiceRoom;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      HuudRoundAction(
        key: const ValueKey('huud-talk'),
        icon: inVoice ? Icons.graphic_eq_rounded : Icons.mic_rounded,
        label: inVoice ? 'Talking' : 'Talk',
        active: inVoice,
        onTap: () => _talk(huud),
      ),
      HuudRoundAction(
        key: const ValueKey('huud-invite'),
        icon: Icons.person_add_alt_1_rounded,
        label: 'Invite',
        onTap: () => _invite(huud),
      ),
      HuudRoundAction(
        icon: Icons.groups_rounded,
        label: 'People',
        active: _tab == _Tab.people,
        onTap: () => setState(() => _tab = _Tab.people),
      ),
      HuudRoundAction(
        key: const ValueKey('huud-leave'),
        icon: Icons.logout_rounded,
        label: 'Leave',
        danger: true,
        onTap: () => _leave(huud),
      ),
    ]);
  }

  Widget _tabs(NeonColors n, HuudSpace huud) {
    final h = HuudColors.of(context);
    Widget tab(_Tab tab, String emoji, String label) {
      final active = _tab == tab;
      return Expanded(
        child: Semantics(
          selected: active,
          button: true,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('huud-tab-${tab.name}'),
            onTap: () => setState(() => _tab = tab),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? h.orange : Colors.transparent,
                borderRadius: BorderRadius.circular(25),
                border: active ? Border.all(color: kCabinetInk, width: 2.2) : null,
              ),
              child: Text('$emoji  $label',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: active ? h.onOrange : n.mid)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: n.panel,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: n.line, width: 1.4),
      ),
      child: Row(children: [
        tab(_Tab.play, '🎮', 'Play'),
        tab(_Tab.people, '👥', 'People ${huud.members.length}'),
      ]),
    );
  }

  // ---------------------------------------------------------------- play tab

  List<Widget> _play(NeonColors n, HuudSpace huud) {
    final game = huud.currentGame;
    const pad = EdgeInsets.symmetric(horizontal: 16);
    if (game == null) {
      if (!huud.youAreHost) {
        return [
          SliverPadding(
            padding: pad,
            sliver: SliverToBoxAdapter(
              child: HuudFriendlyState(
                emoji: '🎲',
                title: 'No game yet',
                message:
                    '${huud.host?.firstName ?? 'The host'} will pick a game soon. Hang out and chat while you wait!',
              ),
            ),
          ),
        ];
      }
      return _picker(n, huud, title: 'Pick a game to play');
    }

    final name = huudGameName(game.gameType);
    final h = HuudColors.of(context);
    final (String emoji, String title, String line) = game.playing
        ? ('🔥', '$name is on!', '${game.players} playing right now')
        : game.waiting
            ? ('⏳', 'Get ready for $name', game.players == 1 ? '1 player is in' : '${game.players} players are in')
            : ('🏆', '$name is over!', 'Good game, everyone');
    final card = HuudCard(
      highlight: !game.finished,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          HuudGameArt(game.gameType, size: 72),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (game.playing)
                const HuudLiveChip(label: 'Playing')
              else
                Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 6),
              Text(title, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: n.ink)),
              const SizedBox(height: 2),
              Text(line, style: TextStyle(fontSize: 15, color: n.mid)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        if (game.waiting)
          HuudButton(
            key: const ValueKey('huud-open-game'),
            label: 'Join the game',
            icon: Icons.sports_esports_rounded,
            big: true,
            expand: true,
            busy: _busy == 'open',
            onPressed: () => _openGame(game),
          )
        else if (game.playing)
          HuudButton(
            key: const ValueKey('huud-open-game'),
            label: 'Go to the game',
            icon: Icons.visibility_rounded,
            big: true,
            expand: true,
            busy: _busy == 'open',
            onPressed: () => _openGame(game),
          )
        else if (huud.youAreHost)
          HuudButton(
            key: const ValueKey('huud-play-again'),
            label: 'Play $name again',
            icon: Icons.replay_rounded,
            big: true,
            expand: true,
            busy: _busy == 'game-${game.gameType}',
            onPressed: () => _pickGame(game.gameType),
          )
        else
          Text('${huud.host?.firstName ?? 'The host'} is picking the next game…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: h.orangeText)),
        if (huud.youAreHost && !game.playing) ...[
          const SizedBox(height: 10),
          HuudButton(
            key: const ValueKey('huud-put-away'),
            label: game.finished ? 'Pick a different game' : 'Put this game away',
            icon: game.finished ? Icons.grid_view_rounded : Icons.close_rounded,
            kind: HuudButtonKind.plain,
            expand: true,
            busy: _busy == 'clear',
            onPressed: _putGameAway,
          ),
        ],
      ]),
    );
    return [SliverPadding(padding: pad, sliver: SliverToBoxAdapter(child: card))];
  }

  List<Widget> _picker(NeonColors n, HuudSpace huud, {required String title}) => [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(child: HuudSectionTitle(title, emoji: '🎮')),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 140,
            ),
            delegate: SliverChildListDelegate([
              for (final g in huudGameOrder)
                HuudGameTile(
                  key: ValueKey('huud-pick-$g'),
                  gameType: g,
                  busy: _busy == 'game-$g',
                  onTap: _busy == null ? () => _pickGame(g) : null,
                ),
            ]),
          ),
        ),
      ];

  // ---------------------------------------------------------------- people tab

  List<Widget> _people(NeonColors n, HuudSpace huud) {
    final me = AppScope.of(context).user?.id;
    final h = HuudColors.of(context);
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 130,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 160,
          ),
          delegate: SliverChildListDelegate([
            for (final p in huud.members)
              HuudCard(
                key: ValueKey('huud-person-${p.userId}'),
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
                highlight: p.host,
                onTap: huud.youAreHost && p.userId != me ? () => _removePerson(p) : null,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Stack(clipBehavior: Clip.none, children: [
                    Avatar(p.name, size: 58, imageUrl: p.avatarUrl),
                    if (p.here)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                              color: h.live, shape: BoxShape.circle, border: Border.all(color: n.panel, width: 3)),
                        ),
                      ),
                    if (p.host)
                      const Positioned(top: -12, right: -6, child: Text('👑', style: TextStyle(fontSize: 22))),
                  ]),
                  const SizedBox(height: 8),
                  Text(p.userId == me ? 'You' : p.firstName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: n.ink)),
                  const SizedBox(height: 2),
                  Text(p.host ? 'Host' : (p.here ? 'Here now' : 'Away'),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: p.host ? h.orangeText : (p.here ? h.live : n.mute))),
                ]),
              ),
          ]),
        ),
      ),
      if (huud.youAreHost && huud.members.length > 1)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Text('Tip: tap someone to take them out of the Huud.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: n.mute)),
          ),
        ),
      if (huud.code != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: HuudButton(
              label: 'Invite a friend',
              icon: Icons.person_add_alt_1_rounded,
              kind: HuudButtonKind.soft,
              expand: true,
              onPressed: () => _invite(huud),
            ),
          ),
        ),
    ];
  }
}

/// Host only: rename the Huud or change who can join.
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.huud});
  final HuudSpace huud;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final _name = TextEditingController(text: widget.huud.name);
  late HuudPrivacy _privacy = widget.huud.privacy;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final raw = await AppScope.of(context).api.patch('/huud-spaces/${widget.huud.id}', {
        'name': _name.text.trim(),
        'privacy': _privacy.wire,
      }) as Map<String, dynamic>;
      if (mounted) Navigator.of(context).pop(HuudSpace.fromJson(raw));
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, "That didn't work — try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Huud settings',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: n.ink)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: n.ink),
              decoration: InputDecoration(
                counterText: '',
                labelText: 'Name',
                prefixIcon: Icon(Icons.edit_rounded, color: h.orangeText),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: h.orange, width: 2.4)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Who can join?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: n.ink)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in HuudPrivacy.values)
                ChoiceChip(
                  label: Text('${p.emoji}  ${p.label}',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800, color: _privacy == p ? h.onOrange : n.ink)),
                  selected: _privacy == p,
                  selectedColor: h.orange,
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  onSelected: (_) => setState(() => _privacy = p),
                ),
            ]),
            const SizedBox(height: 6),
            Text(_privacy.explain, style: TextStyle(fontSize: 14, color: n.mid)),
            const SizedBox(height: 20),
            HuudButton(
                label: 'Save', icon: Icons.check_rounded, expand: true, big: true, busy: _busy, onPressed: _save),
          ]),
        ),
      ),
    );
  }
}
