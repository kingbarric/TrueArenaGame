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
import '../spectate/spectate_screen.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';
import 'huud_roster.dart';
import 'safety_sheet.dart';

Future<void> openHuudSpace(BuildContext context, String id, {HuudSpace? initial}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => HuudSpaceScreen(id: id, initial: initial)));

/// Inside a Huud: who's here, what's being played, and the chat.
///
/// Being in the Huud is listening, chatting and watching. A seat in the game
/// and the mic are the host's to hand out — people ask, and the host says yes
/// or no from the orange "asking" box at the top. Three tabs — **Play**,
/// **Chat**, **People** — sit under the Huud's card; Back and End stay pinned.
/// Everything refreshes by itself (server events, plus a gentle poll).
class HuudSpaceScreen extends StatefulWidget {
  const HuudSpaceScreen({super.key, required this.id, this.initial});

  final String id;
  final HuudSpace? initial;

  @override
  State<HuudSpaceScreen> createState() => _HuudSpaceScreenState();
}

enum _Tab { play, chat, people }

class _HuudSpaceScreenState extends State<HuudSpaceScreen> {
  late HuudSpace? _huud = widget.initial;
  String? _error;
  _Tab _tab = _Tab.play;
  String? _busy;
  Timer? _poll;
  StreamSubscription? _events;
  bool _started = false;

  List<HuudChatMessage>? _chat;
  int _unread = 0;
  final _say = TextEditingController();
  final _scroll = ScrollController();

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
    _say.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onVoice() {
    if (mounted) setState(() {});
  }

  String? get _me => AppScope.of(context).user?.id;

  void _onEvent(Map<String, dynamic> event) {
    final data = (event['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (data['huudSpaceId'] != widget.id || !mounted) return;
    final kind = data['event'] as String?;
    switch (kind) {
      case 'chat':
        final raw = (data['message'] as Map?)?.cast<String, dynamic>();
        if (raw == null) return;
        final message = HuudChatMessage.fromJson(raw);
        setState(() {
          if (_chat != null && !_chat!.any((m) => m.id == message.id)) _chat = [..._chat!, message];
          if (_tab != _Tab.chat && message.from.userId != _me) _unread++;
        });
        _toBottom();
        return;
      case 'removed':
        huudSnack(context, 'The host took you out of this Huud.');
        Navigator.of(context).maybePop();
        return;
      case 'accepted-join':
        huudSnack(context, "You're in! Say hi 👋");
      case 'declined-join':
        huudSnack(context, 'The host said not right now.');
      case 'accepted-play':
        huudSnack(context, "You're in the game! 🎮");
      case 'declined-play':
        huudSnack(context, 'Not this time — you can watch and ask again next game.');
      case 'accepted-mic':
        huudSnack(context, 'You can talk now! Tap Talk 🎙️');
      case 'mic-off':
        huudSnack(context, 'The host turned your mic off.');
      case 'picked':
        huudSnack(context, "You're playing! Open the game and press Ready 🎮");
      case 'unpicked':
        huudSnack(context, 'The host changed the players — you can watch this one.');
      case 'request':
        if (_huud?.youAreHost == true) huudSnack(context, 'Someone is asking you something ✋');
      case 'host':
        if (data['by'] != _me) {
          _load(thenSay: (huud) => huud.youAreHost ? "You're the host now! 👑" : null);
          return;
        }
    }
    _load();
  }

  Future<void> _load({String? Function(HuudSpace)? thenSay}) async {
    try {
      final api = AppScope.of(context).api;
      // Looking in without joining counts as watching while the screen is open.
      final watching = _huud != null && _huud!.active && !_huud!.youAreIn && _huud!.joinRequest != 'pending';
      final raw = (watching
          ? await api.post('/huud-spaces/${widget.id}/watch')
          : await api.get('/huud-spaces/${widget.id}')) as Map<String, dynamic>;
      if (!mounted) return;
      final huud = HuudSpace.fromJson(raw);
      setState(() {
        _huud = huud;
        _error = null;
      });
      if (huud.youAreIn && _chat == null) _loadChat();
      if (!watching && huud.active && !huud.youAreIn && huud.joinRequest != 'pending') {
        api.post('/huud-spaces/${widget.id}/watch').catchError((Object _) => null);
      }
      if (!huud.youAreIn && _tab == _Tab.chat) setState(() => _tab = _Tab.play);
      final say = thenSay?.call(huud);
      if (say != null) huudSnack(context, say);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && _huud == null) setState(() => _error = "We couldn't reach PlayHuud. Pull down to try again.");
    }
  }

  Future<void> _loadChat() async {
    try {
      final raw = await AppScope.of(context).api.get('/huud-spaces/${widget.id}/messages') as List;
      if (!mounted) return;
      setState(() => _chat = [for (final m in raw) HuudChatMessage.fromJson((m as Map).cast<String, dynamic>())]);
    } catch (_) {
      if (mounted && _chat == null) setState(() => _chat = const []);
    }
  }

  void _toBottom() {
    if (_tab != _Tab.chat) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _openTab(_Tab tab) {
    setState(() {
      _tab = tab;
      if (tab == _Tab.chat) _unread = 0;
    });
    if (tab == _Tab.chat) {
      if (_chat == null) _loadChat();
      _toBottom();
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

  /// Run something that answers with the Huud, and show the answer.
  Future<void> _update(String what, Future<dynamic> Function(ApiClient api) call, {String? say}) async {
    final raw = await _run(what, call);
    if (raw is Map && mounted) {
      setState(() => _huud = HuudSpace.fromJson(raw.cast<String, dynamic>()));
      if (say != null) huudSnack(context, say);
    }
  }

  Future<void> _join() async {
    final raw = await _run('join', (api) => api.post('/huud-spaces/${widget.id}/join'));
    if (raw is Map && mounted) {
      final huud = HuudSpace.fromJson(raw.cast<String, dynamic>());
      setState(() => _huud = huud);
      huudSnack(
          context, huud.youAreIn ? 'You joined! Say hi 👋' : "Asked the host — you'll get in when they say yes ⏳");
      if (huud.youAreIn) _loadChat();
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

  /// The same game, the same players back in their seats.
  Future<void> _rematch(String gameType) async {
    final raw = await _run(
        'rematch', (api) => api.post('/huud-spaces/${widget.id}/game', {'gameType': gameType, 'rematch': true}));
    if (raw is Map && mounted) {
      await _enterRoom(RoomView.fromJson(raw.cast<String, dynamic>()));
    }
  }

  /// Players go to their seat; everyone else watches once it's on.
  Future<void> _openGame(HuudGame game) async {
    if (_busy != null) return;
    setState(() => _busy = 'open');
    final app = AppScope.of(context);
    try {
      if (!game.youArePlaying) {
        setState(() => _busy = null);
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SpectateScreen(
                roomId: game.roomId, gameType: game.gameType, title: 'Watching ${huudGameName(game.gameType)}')));
        return;
      }
      final raw = await app.api.get('/rooms/${game.roomId}');
      if (!mounted) return;
      setState(() => _busy = null);
      await _enterRoom(RoomView.fromJson((raw as Map).cast<String, dynamic>()));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      huudSnack(context, e.message);
      _load();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = null);
        huudSnack(context, "That didn't work — check your internet and try again.");
      }
    }
  }

  Future<void> _askToPlay() => _update('play', (api) => api.post('/huud-spaces/${widget.id}/play'),
      say: _huud?.youAreHost == true ? null : 'Asked to play ✋');

  Future<void> _askForMic() =>
      _update('mic', (api) => api.post('/huud-spaces/${widget.id}/mic'), say: 'Asked the host for the mic ✋');

  Future<void> _answer(HuudRequest request, bool yes) => _update('answer-${request.from.userId}-${request.kind}',
      (api) => api.post('/huud-spaces/${widget.id}/requests/${request.from.userId}/${request.kind}', {'accept': yes}));

  Future<void> _setMic(HuudMember person, bool allowed) => _update('mic-${person.userId}',
      (api) => api.post('/huud-spaces/${widget.id}/members/${person.userId}/mic', {'allowed': allowed}),
      say: allowed ? '${person.firstName} can talk now 🎙️' : "${person.firstName}'s mic is off");

  Future<void> _putGameAway() => _update('clear', (api) => api.delete('/huud-spaces/${widget.id}/game'));

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
        onAskToSpeak: () async {
          await api.post('/huud-spaces/${widget.id}/mic').catchError((Object _) => null);
          if (mounted) _load();
        },
      ),
    );
  }

  Future<void> _invite(HuudSpace huud) async {
    if (huud.youAreHost) {
      await showHuudSheet<void>(context, builder: (_) => _InviteSheet(huud: huud));
      if (mounted) _load();
      return;
    }
    _shareCode(huud);
  }

  void _shareCode(HuudSpace huud) {
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
          : 'You can come back later.',
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

  Future<void> _personSheet(HuudSpace huud, HuudMember person) => showHuudSheet<void>(
        context,
        builder: (sheet) {
          final n = sheet.neon;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: Avatar(person.name, size: 64, imageUrl: person.avatarUrl)),
                const SizedBox(height: 8),
                Text(person.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: n.ink)),
                const SizedBox(height: 16),
                if (huud.youAreHost) ...[
                  HuudButton(
                    key: const ValueKey('person-mic'),
                    label: person.canSpeak ? 'Turn their mic off' : 'Let them talk',
                    icon: person.canSpeak ? Icons.mic_off_rounded : Icons.mic_rounded,
                    expand: true,
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      _setMic(person, !person.canSpeak);
                    },
                  ),
                  const SizedBox(height: 10),
                  HuudButton(
                    key: const ValueKey('person-remove'),
                    label: 'Take out of the Huud',
                    icon: Icons.logout_rounded,
                    kind: HuudButtonKind.plain,
                    expand: true,
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      _removePerson(person);
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                HuudButton(
                  key: const ValueKey('person-safety'),
                  label: 'Report or block',
                  icon: Icons.flag_rounded,
                  kind: HuudButtonKind.danger,
                  expand: true,
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    showSafetySheet(context, userId: person.userId, name: person.name, huudSpaceId: widget.id);
                  },
                ),
              ]),
            ),
          );
        },
      );

  Future<void> _settings(HuudSpace huud) async {
    final changed = await showHuudSheet<HuudSpace>(context, builder: (_) => _SettingsSheet(huud: huud));
    if (changed != null && mounted) setState(() => _huud = changed);
  }

  Future<void> _send() async {
    final text = _say.text.trim();
    if (text.isEmpty || _busy == 'send') return;
    setState(() => _busy = 'send');
    try {
      final raw = await AppScope.of(context).api.post('/huud-spaces/${widget.id}/messages', {'body': text});
      if (!mounted) return;
      final message = HuudChatMessage.fromJson((raw as Map).cast<String, dynamic>());
      _say.clear();
      setState(() {
        if (!(_chat ?? const []).any((m) => m.id == message.id)) _chat = [...?_chat, message];
      });
      _toBottom();
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, "That didn't send — try again.");
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final huud = _huud;
    return Scaffold(
      body: HuudBackdrop(
        background: huud?.background,
        child: SafeArea(
          // The top bar stays put so Back and End are always one tap away.
          child: Column(children: [
            _topBar(n, huud),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: CustomScrollView(
                  controller: _scroll,
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
                        _box(HuudFriendlyState(
                          emoji: '👋',
                          title: 'This Huud has ended',
                          message: 'Thanks for hanging out! You can find it in Your Huuds any time.',
                          action: HuudButton(
                              label: 'Back',
                              icon: Icons.arrow_back_rounded,
                              onPressed: () => Navigator.of(context).maybePop()),
                        ))
                      else if (!huud.youAreIn) ...[
                        _box(_door(n, huud)),
                        // Watching: see the game and who's here; chat and voice are for people inside.
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                          sliver: SliverToBoxAdapter(child: _tabs(n, huud)),
                        ),
                        ...(_tab == _Tab.people ? _people(n, huud) : _play(n, huud)),
                      ] else ...[
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(8, 18, 8, 0),
                          sliver: SliverToBoxAdapter(child: _actions(huud)),
                        ),
                        if (huud.youAreHost && huud.requests.isNotEmpty) _box(_asking(n, huud), top: 16),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                          sliver: SliverToBoxAdapter(child: _tabs(n, huud)),
                        ),
                        ...switch (_tab) {
                          _Tab.play => _play(n, huud),
                          _Tab.chat => _chatSlivers(n, huud),
                          _Tab.people => _people(n, huud),
                        },
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: 120)),
                    ],
                  ],
                ),
              ),
            ),
            if (huud != null && huud.youAreIn && huud.active && _tab == _Tab.chat) _chatInput(n),
          ]),
        ),
      ),
    );
  }

  Widget _box(Widget child, {double top = 16}) => SliverPadding(
        padding: EdgeInsets.fromLTRB(16, top, 16, 0),
        sliver: SliverToBoxAdapter(child: child),
      );

  Widget _topBar(NeonColors n, HuudSpace? huud) {
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
    final hosting = huud != null && huud.youAreHost && huud.active;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(children: [
        circle(Icons.arrow_back_rounded, 'Back', () => Navigator.of(context).maybePop(),
            key: const ValueKey('huud-back')),
        const SizedBox(width: 12),
        Image.asset(huudIcon, width: 30, height: 30),
        const SizedBox(width: 8),
        Expanded(child: Text('Huud', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: n.ink))),
        if (hosting)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: circle(Icons.tune_rounded, 'Huud settings', () => _settings(huud),
                key: const ValueKey('huud-settings')),
          ),
        if (hosting)
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
      ]),
    );
  }

  Widget _hero(HuudSpace huud) {
    final host = huud.host;
    final hostLine = huud.youAreHost
        ? "You're the host"
        : (host == null ? 'Looking for a host' : 'Host: ${host.userId == _me ? 'you' : host.firstName}');
    return HuudHeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (huud.active)
            const HuudChip('Live', emoji: '🟢', onOrange: true)
          else
            const HuudChip('Ended', emoji: '🌙', onOrange: true),
          HuudChip(huud.privacy.label, emoji: huud.privacy.emoji, onOrange: true),
          if (huud.shared && huud.active) const HuudChip('On the feed', emoji: '📣', onOrange: true),
          if (huud.watching > 0 && huud.active) HuudChip('${huud.watching} watching', emoji: '👀', onOrange: true),
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

  /// Outside the Huud: walk in, ask to come in, or wait for the answer.
  Widget _door(NeonColors n, HuudSpace huud) {
    if (huud.joinRequest == 'pending') {
      return HuudFriendlyState(
        key: const ValueKey('huud-waiting'),
        emoji: '⏳',
        title: 'Waiting for the host',
        message: "You asked to come in. You'll get in as soon as ${huud.host?.firstName ?? 'the host'} says yes.",
      );
    }
    if (huud.joinRequest == 'declined') {
      return HuudFriendlyState(
        emoji: '🙅',
        title: 'Not right now',
        message: "The host didn't let you in this time. You can ask again in a few minutes.",
        action: HuudButton(label: 'Ask again', icon: Icons.front_hand_rounded, busy: _busy == 'join', onPressed: _join),
      );
    }
    return HuudButton(
      key: const ValueKey('huud-join'),
      label: huud.privacy == HuudPrivacy.private ? 'Ask to join' : 'Join this Huud',
      icon: huud.privacy == HuudPrivacy.private ? Icons.front_hand_rounded : Icons.login_rounded,
      big: true,
      expand: true,
      busy: _busy == 'join',
      onPressed: _join,
    );
  }

  Widget _actions(HuudSpace huud) {
    final inVoice = HangoutState.instance.roomName == huud.voiceRoom;
    final canSpeak = huud.youCanSpeak;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      HuudRoundAction(
        key: const ValueKey('huud-talk'),
        icon: inVoice ? Icons.graphic_eq_rounded : (canSpeak ? Icons.mic_rounded : Icons.headphones_rounded),
        label: inVoice ? (canSpeak ? 'Talking' : 'Listening') : (canSpeak ? 'Talk' : 'Listen'),
        active: inVoice,
        onTap: () => _talk(huud),
      ),
      if (!canSpeak)
        HuudRoundAction(
          key: const ValueKey('huud-ask-mic'),
          icon: Icons.front_hand_rounded,
          label: huud.micRequest == 'pending' ? 'Mic asked' : 'Ask mic',
          active: huud.micRequest == 'pending',
          onTap: huud.micRequest == 'pending' ? null : _askForMic,
        ),
      HuudRoundAction(
        key: const ValueKey('huud-invite'),
        icon: Icons.person_add_alt_1_rounded,
        label: 'Invite',
        onTap: () => _invite(huud),
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

  /// The host's to-do list: who wants in, who wants to play, who wants to talk.
  Widget _asking(NeonColors n, HuudSpace huud) {
    final h = HuudColors.of(context);
    return Container(
      key: const ValueKey('huud-asking'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: h.orangeSoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: h.orange, width: 2.4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(huud.requests.length == 1 ? '✋ 1 person is asking' : '✋ ${huud.requests.length} people are asking',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: n.ink)),
        const SizedBox(height: 8),
        for (final r in huud.requests)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Avatar(r.from.name, size: 42, imageUrl: r.from.avatarUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.from.firstName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: n.ink)),
                  Text('${r.emoji} ${r.ask}', style: TextStyle(fontSize: 14, color: n.mid)),
                ]),
              ),
              _answerButton(r, false),
              const SizedBox(width: 8),
              _answerButton(r, true),
            ]),
          ),
      ]),
    );
  }

  Widget _answerButton(HuudRequest r, bool yes) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final busy = _busy == 'answer-${r.from.userId}-${r.kind}';
    return Semantics(
      button: true,
      label: '${yes ? 'Yes' : 'No'} to ${r.from.firstName}',
      excludeSemantics: true,
      child: Bouncy(
        key: ValueKey('answer-${r.kind}-${r.from.userId}-${yes ? 'yes' : 'no'}'),
        onTap: busy ? null : () => _answer(r, yes),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: yes ? h.orange : n.panel,
            border: Border.all(color: yes ? kCabinetInk : n.line, width: yes ? 2.2 : 1.4),
          ),
          child: Icon(yes ? Icons.check_rounded : Icons.close_rounded, size: 28, color: yes ? h.onOrange : n.mid),
        ),
      ),
    );
  }

  Widget _tabs(NeonColors n, HuudSpace huud) {
    final h = HuudColors.of(context);
    Widget tab(_Tab tab, String emoji, String label, {int badge = 0}) {
      final active = _tab == tab;
      return Expanded(
        child: Semantics(
          selected: active,
          button: true,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('huud-tab-${tab.name}'),
            onTap: () => _openTab(tab),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? h.orange : Colors.transparent,
                borderRadius: BorderRadius.circular(25),
                border: active ? Border.all(color: kCabinetInk, width: 2.2) : null,
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('$emoji $label',
                        style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: active ? h.onOrange : n.mid)),
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: n.danger, borderRadius: BorderRadius.circular(10)),
                    child: Text('$badge',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                ],
              ]),
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
        if (huud.youAreIn) tab(_Tab.chat, '💬', 'Chat', badge: _unread),
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
                message: '${huud.host?.firstName ?? 'The host'} will pick a game soon. Chat while you wait!',
              ),
            ),
          ),
        ];
      }
      return _picker(n, huud, title: 'Pick a game to play');
    }

    final name = huudGameName(game.gameType);
    final h = HuudColors.of(context);
    final (String emoji, String title) = game.playing
        ? ('🔥', '$name is on!')
        : game.waiting
            ? ('⏳', 'Get ready for $name')
            : ('🏆', '$name is over!');
    final players = huud.members.where((m) => game.playerIds.contains(m.userId)).toList();
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
              Text(game.finished ? 'Good game, everyone' : '${game.players} / ${game.seats} seats taken',
                  key: const ValueKey('huud-seats'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: n.mid)),
            ]),
          ),
        ]),
        if (game.waiting) ...[
          const SizedBox(height: 14),
          HuudRoster(huud: huud, roomId: game.roomId, seated: game.table, seats: game.seats, onChanged: _load),
        ] else if (players.isNotEmpty && !game.finished) ...[
          const SizedBox(height: 12),
          Row(children: [
            HuudAvatarStack(people: players, size: 30, max: 6),
            const SizedBox(width: 8),
            Expanded(
              child: Text(players.map((p) => p.userId == _me ? 'You' : p.firstName).join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: n.mid)),
            ),
          ]),
        ],
        const SizedBox(height: 16),
        ..._gameButtons(n, h, huud, game, name),
      ]),
    );
    return [SliverPadding(padding: pad, sliver: SliverToBoxAdapter(child: card))];
  }

  List<Widget> _gameButtons(NeonColors n, HuudColors h, HuudSpace huud, HuudGame game, String name) {
    Widget note(String text) => Text(text,
        textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: h.orangeText));
    if (game.finished) {
      if (!huud.youAreHost) return [note('${huud.host?.firstName ?? 'The host'} is picking the next game…')];
      return [
        HuudButton(
          key: const ValueKey('huud-rematch'),
          label: 'Rematch — same players',
          icon: Icons.replay_rounded,
          big: true,
          expand: true,
          busy: _busy == 'rematch',
          onPressed: () => _rematch(game.gameType),
        ),
        const SizedBox(height: 10),
        HuudButton(
          key: const ValueKey('huud-play-again'),
          label: 'Play $name with new players',
          icon: Icons.group_add_rounded,
          kind: HuudButtonKind.soft,
          expand: true,
          busy: _busy == 'game-${game.gameType}',
          onPressed: () => _pickGame(game.gameType),
        ),
        const SizedBox(height: 10),
        HuudButton(
          key: const ValueKey('huud-put-away'),
          label: 'Pick a different game',
          icon: Icons.grid_view_rounded,
          kind: HuudButtonKind.plain,
          expand: true,
          busy: _busy == 'clear',
          onPressed: _putGameAway,
        ),
      ];
    }
    if (!huud.youAreIn) {
      return [
        game.playing
            ? HuudButton(
                key: const ValueKey('huud-watch'),
                label: 'Watch',
                icon: Icons.visibility_rounded,
                big: true,
                expand: true,
                busy: _busy == 'open',
                onPressed: () => _openGame(game),
              )
            : note('Join the Huud to ask to play'),
      ];
    }
    final ready = game.readyIds.contains(_me);
    final main = game.youArePlaying
        ? HuudButton(
            key: const ValueKey('huud-open-game'),
            label: game.playing
                ? 'Back to the game'
                : huud.youAreHost
                    ? 'Open the game to start'
                    : (ready ? 'Open the game' : 'Open the game & ready up'),
            icon: Icons.sports_esports_rounded,
            big: true,
            expand: true,
            busy: _busy == 'open',
            onPressed: () => _openGame(game),
          )
        : game.playing
            ? HuudButton(
                key: const ValueKey('huud-watch'),
                label: 'Watch',
                icon: Icons.visibility_rounded,
                big: true,
                expand: true,
                busy: _busy == 'open',
                onPressed: () => _openGame(game),
              )
            : huud.playRequest == 'pending'
                ? note("✋ You asked to play — waiting for ${huud.host?.firstName ?? 'the host'}")
                : game.full
                    ? note('All the seats are taken — you can watch when it starts')
                    : HuudButton(
                        key: const ValueKey('huud-ask-play'),
                        label: huud.playRequest == 'declined' ? 'Ask to play again' : 'Ask to play',
                        icon: Icons.front_hand_rounded,
                        big: true,
                        expand: true,
                        busy: _busy == 'play',
                        onPressed: _askToPlay,
                      );
    return [
      if (game.youArePlaying && game.waiting && !huud.youAreHost && ready) ...[
        note('You\'re ready ✅ — waiting for ${huud.host?.firstName ?? 'the host'} to start'),
        const SizedBox(height: 10),
      ],
      main,
      if (huud.youAreHost && game.waiting) ...[
        const SizedBox(height: 10),
        HuudButton(
          key: const ValueKey('huud-put-away'),
          label: 'Put this game away',
          icon: Icons.close_rounded,
          kind: HuudButtonKind.plain,
          expand: true,
          busy: _busy == 'clear',
          onPressed: _putGameAway,
        ),
      ],
    ];
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

  // ---------------------------------------------------------------- chat tab

  List<Widget> _chatSlivers(NeonColors n, HuudSpace huud) {
    final chat = _chat;
    if (chat == null) {
      return [
        const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())))
      ];
    }
    if (chat.isEmpty) {
      return [
        _box(
            const HuudFriendlyState(
                emoji: '💬', title: 'Say hi!', message: 'Chat stays here the whole time, game after game.'),
            top: 0),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.builder(
          itemCount: chat.length,
          itemBuilder: (context, i) =>
              _bubble(n, chat[i], showName: i == 0 || chat[i - 1].from.userId != chat[i].from.userId),
        ),
      ),
    ];
  }

  Widget _bubble(NeonColors n, HuudChatMessage m, {required bool showName}) {
    final h = HuudColors.of(context);
    final mine = m.from.userId == _me;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? h.orange : n.panel,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(mine ? 20 : 6),
          bottomRight: Radius.circular(mine ? 6 : 20),
        ),
        border: Border.all(color: mine ? kCabinetInk : n.line, width: mine ? 1.8 : 1.2),
      ),
      child: Text(m.body, style: TextStyle(fontSize: 16, height: 1.3, color: mine ? h.onOrange : n.ink)),
    );
    return Padding(
      key: ValueKey('chat-${m.id}'),
      padding: EdgeInsets.only(top: showName ? 10 : 3),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            showName ? Avatar(m.from.name, size: 30, imageUrl: m.from.avatarUrl) : const SizedBox(width: 30),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
              if (showName && !mine)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 3),
                  child: Text(m.from.firstName,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: n.mute)),
                ),
              mine
                  ? bubble
                  : GestureDetector(
                      onLongPress: () => showSafetySheet(context,
                          userId: m.from.userId, name: m.from.name, huudSpaceId: widget.id, messageId: m.id),
                      child: bubble,
                    ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _chatInput(NeonColors n) {
    final h = HuudColors.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.viewInsetsOf(context).bottom * 0),
      decoration: BoxDecoration(color: n.bg, border: Border(top: BorderSide(color: n.line))),
      child: Row(children: [
        Expanded(
          child: TextField(
            key: const ValueKey('chat-input'),
            controller: _say,
            maxLength: 300,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            style: TextStyle(fontSize: 16, color: n.ink),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Say something nice…',
              filled: true,
              fillColor: n.panel,
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide(color: n.line)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26), borderSide: BorderSide(color: h.orange, width: 2)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: 'Send',
          excludeSemantics: true,
          child: Bouncy(
            key: const ValueKey('chat-send'),
            onTap: _send,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: h.orange, shape: BoxShape.circle, border: Border.all(color: kCabinetInk, width: 2.2)),
              child: _busy == 'send'
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: h.onOrange))
                  : Icon(Icons.send_rounded, color: h.onOrange),
            ),
          ),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- people tab

  List<Widget> _people(NeonColors n, HuudSpace huud) {
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
                onTap: p.userId == _me ? null : () => _personSheet(huud, p),
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
                    if (p.canSpeak && !p.host)
                      const Positioned(top: -10, left: -6, child: Text('🎙️', style: TextStyle(fontSize: 18))),
                  ]),
                  const SizedBox(height: 8),
                  Text(p.userId == _me ? 'You' : p.firstName,
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
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        sliver: SliverToBoxAdapter(
          child: Text(
              huud.youAreHost
                  ? 'Tip: tap someone to let them talk, or take them out.'
                  : 'Tip: tap someone if they are being unkind.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: n.mute)),
        ),
      ),
      if (huud.code != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: HuudButton(
              label: huud.youAreHost ? 'Invite friends' : 'Share the code',
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

/// Host only: invite friends straight in, or share the code.
class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.huud});
  final HuudSpace huud;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  List<HuudMember>? _friends;
  final Set<String> _invited = {};
  String? _busy;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_friends != null) return;
    _friends = const [];
    AppScope.of(context).api.get('/friends').then((raw) {
      if (!mounted) return;
      final inside = widget.huud.members.map((m) => m.userId).toSet();
      setState(() => _friends = [
            for (final f in (raw as List).cast<Map>())
              if (f['agentGameType'] == null && !inside.contains(f['userId'].toString()))
                HuudMember.fromJson(f.cast<String, dynamic>()),
          ]);
    }).catchError((Object _) {});
  }

  Future<void> _invite(HuudMember friend) async {
    setState(() => _busy = friend.userId);
    try {
      await AppScope.of(context).api.post('/huud-spaces/${widget.huud.id}/invite', {'userId': friend.userId});
      if (mounted) setState(() => _invited.add(friend.userId));
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, "That didn't work — try again.");
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final friends = _friends ?? const [];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text('Invite friends',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: n.ink)),
            const SizedBox(height: 4),
            Text('They can come straight in.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: n.mid)),
            const SizedBox(height: 14),
            if (friends.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No friends to invite yet — share the code instead.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: n.mute)),
              ),
            for (final f in friends)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Avatar(f.name, size: 42, imageUrl: f.avatarUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: n.ink)),
                  ),
                  _invited.contains(f.userId)
                      ? const HuudChip('Invited', emoji: '✅')
                      : HuudButton(
                          key: ValueKey('invite-${f.userId}'),
                          label: 'Invite',
                          icon: Icons.add_rounded,
                          busy: _busy == f.userId,
                          onPressed: () => _invite(f),
                        ),
                ]),
              ),
            const SizedBox(height: 14),
            if (widget.huud.code != null)
              HuudButton(
                label: 'Share the code',
                icon: Icons.ios_share_rounded,
                kind: HuudButtonKind.soft,
                expand: true,
                onPressed: () => Share.share(
                    'Come hang out with me in "${widget.huud.name}" on PlayHuud! 🎮\nOpen the Huud tab and type the code: ${widget.huud.code}'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Host only: rename the Huud, change who can join, and put it on the feed.
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.huud});
  final HuudSpace huud;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final _name = TextEditingController(text: widget.huud.name);
  late final _message = TextEditingController(text: widget.huud.feedMessage ?? '');
  late HuudPrivacy _privacy = widget.huud.privacy;
  late bool _shared = widget.huud.shared;
  late String? _background = widget.huud.background;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final api = AppScope.of(context).api;
    try {
      var raw = await api.patch('/huud-spaces/${widget.huud.id}', {
        'name': _name.text.trim(),
        'privacy': _privacy.wire,
        'background': _background ?? 'default',
      }) as Map<String, dynamic>;
      if (_shared) {
        raw = await api.post('/huud-spaces/${widget.huud.id}/share', {
          if (_message.text.trim().isNotEmpty) 'message': _message.text.trim(),
        }) as Map<String, dynamic>;
      } else if (widget.huud.shared) {
        raw = await api.delete('/huud-spaces/${widget.huud.id}/share') as Map<String, dynamic>;
      }
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
            const SizedBox(height: 16),
            Text('Background', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: n.ink)),
            const SizedBox(height: 8),
            SizedBox(
              height: 128,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final (wire, label, asset) in huudBackgrounds)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Semantics(
                      button: true,
                      selected: _background == wire,
                      label: '$label background',
                      excludeSemantics: true,
                      child: GestureDetector(
                        key: ValueKey('bg-${wire ?? 'default'}'),
                        onTap: () => setState(() => _background = wire),
                        child: Column(children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 70,
                            height: 96,
                            decoration: BoxDecoration(
                              color: n.plate,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: _background == wire ? h.orange : n.line, width: _background == wire ? 3 : 1.4),
                              image:
                                  asset == null ? null : DecorationImage(image: AssetImage(asset), fit: BoxFit.cover),
                            ),
                            alignment: Alignment.center,
                            child: asset == null ? Icon(Icons.block_rounded, color: n.mute) : null,
                          ),
                          const SizedBox(height: 4),
                          Text(label,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: _background == wire ? FontWeight.w900 : FontWeight.w700,
                                  color: _background == wire ? h.orangeText : n.mid)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              key: const ValueKey('settings-share'),
              contentPadding: EdgeInsets.zero,
              value: _shared,
              activeThumbColor: h.onOrange,
              activeTrackColor: h.orange,
              title: Text('📣 Show it on the feed',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: n.ink)),
              onChanged: (v) => setState(() => _shared = v),
            ),
            if (_shared)
              TextField(
                controller: _message,
                maxLength: 140,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(fontSize: 16, color: n.ink),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Who wants to play?',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            const SizedBox(height: 20),
            HuudButton(
                label: 'Save', icon: Icons.check_rounded, expand: true, big: true, busy: _busy, onPressed: _save),
          ]),
        ),
      ),
    );
  }
}
