import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/hangout_state.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../lobby/joined_room_screen.dart';
import '../spectate/spectate_screen.dart';
import 'go_live_sheet.dart';
import 'huud_kit.dart';
import 'huud_link.dart';
import 'huud_voice.dart';
import 'huud_space_models.dart';
import 'huud_roster.dart';
import 'safety_sheet.dart';
import '../../core/keep_awake.dart';
import '../competitive/player_profile_screen.dart';

Future<void> openHuudSpace(BuildContext context, String id, {HuudSpace? initial}) =>
    Navigator.of(context).push(huudRoute(id, initial: initial));

/// Named so a finished game can find its way back to the Huud (`leaveGame`).
String huudRouteName(String id) => 'huud/$id';

Route<void> huudRoute(String id, {HuudSpace? initial}) => MaterialPageRoute(
    settings: RouteSettings(name: huudRouteName(id)), builder: (_) => HuudSpaceScreen(id: id, initial: initial));

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

  /// Your friends, so a person's card can say "Add friend" or "Friends".
  Set<String> _friendIds = const {};
  final _friendAsked = <String>{};
  int _unread = 0;
  final _say = TextEditingController();
  final _scroll = ScrollController();

  /// The chat box scrolls on its own, inside the page.
  final _chatScroll = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // While this screen is on top, its own mic button stands in for the call bar.
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    final room = _huud?.voiceRoom;
    final hangout = HangoutState.instance;
    if (onTop && room != null) {
      hangout.foreground = room;
    } else if (!onTop && hangout.foreground == room) {
      hangout.foreground = null;
    }
    if (_started) return;
    _started = true;
    // Inside a Huud the screen stays on — chat, voice and games keep going.
    KeepAwake.hold(this);
    final app = AppScope.of(context);
    _events = app.huudSpaceEvents.listen(_onEvent);
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load());
    HangoutState.instance.addListener(_onVoice);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadFriends();
    });
  }

  Future<void> _loadFriends() async {
    try {
      final rows = await AppScope.of(context).api.get('/friends') as List;
      if (mounted) {
        setState(() => _friendIds = {for (final f in rows) (f as Map)['userId'].toString()});
      }
    } catch (_) {
      // Unknown — the card just offers "Add friend" and the server says if you already are.
    }
  }

  Future<void> _addFriend(HuudMember person) async {
    try {
      await AppScope.of(context).api.post('/friends/requests/user/${person.userId}');
      if (!mounted) return;
      setState(() => _friendAsked.add(person.userId));
      huudSnack(context, 'Friend request sent to ${person.handle} 🤝');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.message.contains('already friends')) setState(() => _friendIds = {..._friendIds, person.userId});
      huudSnack(context, e.message.contains('already friends') ? "You're already friends 💛" : e.message);
    } catch (_) {
      if (mounted) huudSnack(context, "That didn't work — check your internet and try again.");
    }
  }

  /// Three of your coins to them; they see a little splash wherever they are.
  Future<void> _giftCoins(HuudMember person) async {
    try {
      final raw = await AppScope.of(context).api.post('/players/${person.userId}/gift') as Map;
      if (!mounted) return;
      huudSnack(context, '🎁 You gave ${person.handle} ${raw['coins'] ?? 3} coins! You have ${raw['balance']} left.');
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, "That didn't work — check your internet and try again.");
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    _poll?.cancel();
    HangoutState.instance.removeListener(_onVoice);
    KeepAwake.release(this);
    final room = _huud?.voiceRoom;
    if (room != null) {
      if (HangoutState.instance.foreground == room) HangoutState.instance.foreground = null;
      // Back out of the Huud: its voice goes quiet too. (Games on top keep it.)
      if (HuudVoice.instance.isIn(room) || HuudVoice.instance.isConnecting(room)) HuudVoice.instance.leave();
    }
    _say.dispose();
    _scroll.dispose();
    _chatScroll.dispose();
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
        final reading = _tab == _Tab.chat && _chatAtBottom;
        setState(() {
          if (_chat != null && !_chat!.any((m) => m.id == message.id)) _chat = [..._chat!, message];
          if (!reading && message.from.userId != _me) _unread++;
        });
        if (reading || message.from.userId == _me) _toBottom();
        return;
      case 'removed':
        huudSnack(context, 'The host took you out of this Huud.');
        Navigator.of(context).maybePop();
        return;
      case 'deleted':
        huudSnack(context, 'This Huud was deleted by its owner.');
        Navigator.of(context).maybePop();
        return;
      case 'live':
        if (data['by'] != _me) huudSnack(context, '${_huud?.name ?? 'The Huud'} is Live! 🔴');
      case 'live-ended':
        if (data['by'] != _me) huudSnack(context, 'Live has ended — the Huud is still here.');
        if (HangoutState.instance.roomName == _huud?.voiceRoom) HangoutState.instance.leave?.call();
      case 'accepted-join':
        huudSnack(context, "You're in! Say hi 👋");
      case 'declined-join':
        huudSnack(context, 'The host said not right now.');
      case 'accepted-play':
        huudSnack(context, "You're in the game! 🎮");
      case 'declined-play':
        huudSnack(context, 'Not this time — you can watch and ask again next game.');
      case 'accepted-mic':
        huudSnack(context, 'You can talk now! Tap the mic 🎙️');
      case 'mic-off':
        huudSnack(context, 'The host turned your mic off.');
      case 'picked':
        huudSnack(context, "You're playing! Open the game 🎮");
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
      final watching =
          _huud != null && _huud!.active && _huud!.live && !_huud!.youAreIn && _huud!.joinRequest != 'pending';
      final raw = (watching
          ? await api.post('/huud-spaces/${widget.id}/watch')
          : await api.get('/huud-spaces/${widget.id}')) as Map<String, dynamic>;
      if (!mounted) return;
      final huud = HuudSpace.fromJson(raw);
      setState(() {
        _huud = huud;
        _error = null;
      });
      _syncVoice(huud);
      if (huud.youAreIn && _chat == null) _loadChat();
      if (!watching && huud.active && huud.live && !huud.youAreIn && huud.joinRequest != 'pending') {
        api.post('/huud-spaces/${widget.id}/watch').catchError((Object _) => null);
      }
      if (!huud.youAreIn && _tab == _Tab.chat) setState(() => _tab = _Tab.play);
      // No Play tab while offline.
      if (!huud.live && _tab == _Tab.play) setState(() => _tab = huud.youAreIn ? _Tab.chat : _Tab.people);
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

  /// Looking at the newest messages (or the box isn't up yet). The box's list
  /// runs newest-first from the bottom, so "at the bottom" is offset 0.
  bool get _chatAtBottom => !_chatScroll.hasClients || _chatScroll.position.pixels < 48;

  void _toBottom() {
    if (_tab != _Tab.chat && !(_huud != null && !_huud!.live)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _readNewest() {
    setState(() => _unread = 0);
    _toBottom();
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
      say: allowed ? '${person.handle} can talk now 🎙️' : "${person.handle}'s mic is off");

  Future<void> _putGameAway() => _update('clear', (api) => api.delete('/huud-spaces/${widget.id}/game'));

  /// In a Live Huud you're always connected — muted until you tap the mic.
  void _syncVoice(HuudSpace huud) {
    final voice = HuudVoice.instance;
    final room = huud.voiceRoom;
    if (ModalRoute.of(context)?.isCurrent ?? true) HangoutState.instance.foreground = room;
    final belong = huud.active && huud.live && huud.youAreIn;
    if (belong && !voice.isIn(room) && !voice.isConnecting(room)) {
      voice.join(
        api: AppScope.of(context).api,
        roomName: room,
        title: huud.name,
        openHuud: () => _backToHuud(huud.id),
      );
    } else if (!belong && (voice.isIn(room) || voice.isConnecting(room))) {
      voice.leave();
    }
  }

  void _backToHuud(String id) {
    final nav = HangoutState.instance.navigationKey.currentState ?? Navigator.maybeOf(context);
    nav?.popUntil((r) => r.settings.name == huudRouteName(id) || r.isFirst);
  }

  /// The mic button: muted ↔ talking, right here — no call screen.
  Future<void> _talk(HuudSpace huud) async {
    final voice = HuudVoice.instance;
    if (!voice.isIn(huud.voiceRoom)) {
      if (voice.isConnecting(huud.voiceRoom)) return;
      _syncVoice(huud);
      huudSnack(context, 'Connecting to the Huud…');
      return;
    }
    if (!voice.canSpeak && !huud.youCanSpeak) {
      huudSnack(
          context,
          huud.micRequest == 'pending'
              ? 'You asked for the mic — wait for the host ✋'
              : 'Tap Ask mic — the host hands out the mic ✋');
      return;
    }
    final result = await voice.setMuted(!HangoutState.instance.muted);
    if (!mounted) return;
    switch (result) {
      case MicResult.ok:
        break;
      case MicResult.noPermission:
        huudSnack(context, 'Turn on the microphone for PlayHuud in your phone settings.');
      case MicResult.noMic:
        huudSnack(context, "The host hasn't handed you the mic yet ✋");
      case MicResult.notConnected:
      case MicResult.failed:
        huudSnack(context, "Your mic didn't switch on — try again in a moment.");
        _syncVoice(huud);
    }
    setState(() {});
  }

  Future<void> _invite(HuudSpace huud) async {
    if (huud.youAreHost) {
      await showHuudSheet<void>(context, builder: (_) => _InviteSheet(huud: huud));
      if (mounted) _load();
      return;
    }
    // Members: share the link (the host also invites friends and posts it).
    await showHuudSheet<void>(context, builder: (_) => _ShareLinkSheet(huud: huud));
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) huudSnack(context, 'Code copied! Send it to a friend.');
  }

  /// Leaving the Huud for good — not just stepping out. No more notifications from it.
  Future<void> _leave(HuudSpace huud) async {
    final ok = await confirmHuud(
      context,
      emoji: '👋',
      title: 'Leave ${huud.name}?',
      message: "You won't be a member any more and you'll stop getting notifications from it. "
          'You can join again with the code.',
      yes: 'Yes, leave the Huud',
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

  /// End the Live hangout. The Huud stays — members, chat, code, background.
  Future<void> _end(HuudSpace huud) async {
    final ok = await confirmHuud(
      context,
      emoji: '🌙',
      title: 'End Live?',
      message: 'The Huud stays — its members, chat and code are kept. The game and voice stop for now.',
      yes: 'End Live',
      danger: true,
    );
    if (!ok || !mounted) return;
    if (HangoutState.instance.roomName == huud.voiceRoom) await HangoutState.instance.leave?.call();
    if (!mounted) return;
    await _update('end', (api) => api.delete('/huud-spaces/${widget.id}/live'),
        say: 'Live has ended. Your Huud is still here 🏠');
    if (mounted) setState(() => _tab = _Tab.chat);
  }

  Future<void> _goLive() async {
    final live = await goLive(context, widget.id);
    if (live != null && mounted) {
      setState(() {
        _huud = live;
        _tab = _Tab.play;
      });
    }
  }

  Future<void> _toggleMute(HuudSpace huud) =>
      _update('mute', (api) => api.post('/huud-spaces/${widget.id}/mute', {'muted': !huud.muted}),
          say: huud.muted ? "You'll hear when it goes Live 🔔" : 'Muted — no notifications from this Huud 🔕');

  Future<void> _removePerson(HuudMember person) async {
    final ok = await confirmHuud(
      context,
      emoji: '🚪',
      title: 'Take ${person.handle} out?',
      message: "${person.handle} will leave this Huud and won't be able to come back in.",
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
                // Their card: the one place the full name shows.
                Text(person.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: n.ink)),
                if (person.username.isNotEmpty && person.username != person.name)
                  Text('@${person.username}',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: n.mute)),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  HuudRoundAction(
                    key: const ValueKey('person-profile'),
                    icon: Icons.person_rounded,
                    label: 'Profile',
                    onTap: person.username.isEmpty
                        ? null
                        : () {
                            Navigator.of(sheet).pop();
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => PlayerProfileScreen(username: person.username)));
                          },
                  ),
                  if (_friendIds.contains(person.userId))
                    const HuudRoundAction(
                        key: ValueKey('person-friends'), icon: Icons.favorite_rounded, label: 'Friends', active: true, onTap: null)
                  else if (_friendAsked.contains(person.userId))
                    const HuudRoundAction(
                        key: ValueKey('person-friend-asked'), icon: Icons.hourglass_top_rounded, label: 'Asked', onTap: null)
                  else
                    HuudRoundAction(
                      key: const ValueKey('person-add-friend'),
                      icon: Icons.person_add_alt_1_rounded,
                      label: 'Add friend',
                      onTap: () {
                        Navigator.of(sheet).pop();
                        _addFriend(person);
                      },
                    ),
                  HuudRoundAction(
                    key: const ValueKey('person-gift'),
                    icon: Icons.card_giftcard_rounded,
                    label: 'Gift 3 coins',
                    onTap: () {
                      Navigator.of(sheet).pop();
                      _giftCoins(person);
                    },
                  ),
                ]),
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
    final changed = await showHuudSheet<Object>(context, builder: (_) => _SettingsSheet(huud: huud));
    if (!mounted) return;
    if (changed is HuudSpace) setState(() => _huud = changed);
    if (changed == _SettingsSheet.deleted) {
      if (HangoutState.instance.roomName == huud.voiceRoom) await HangoutState.instance.leave?.call();
      if (!mounted) return;
      huudSnack(context, '${huud.name} was deleted');
      Navigator.of(context).maybePop();
    }
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
                          title: 'This Huud was deleted',
                          message: 'Its owner deleted it. Thanks for hanging out!',
                          action: HuudButton(
                              label: 'Back',
                              icon: Icons.arrow_back_rounded,
                              onPressed: () => Navigator.of(context).maybePop()),
                        ))
                      else if (!huud.youAreIn) ...[
                        _box(_door(n, huud)),
                        // Watching: see the game and who's here; chat and voice are for people inside.
                        if (huud.live) ...[
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                            sliver: SliverToBoxAdapter(child: _tabs(n, huud)),
                          ),
                          ...(_tab == _Tab.people ? _people(n, huud) : _play(n, huud)),
                        ],
                      ] else if (!huud.live) ...[
                        // Offline: the Huud is still home — chat and people, and Go Live for the owner.
                        _box(_offline(n, huud)),
                        if (huud.youAreHost && huud.requests.isNotEmpty) _box(_asking(n, huud), top: 16),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                          sliver: SliverToBoxAdapter(child: _tabs(n, huud)),
                        ),
                        ...(_tab == _Tab.people ? _people(n, huud) : _chatSlivers(n, huud)),
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
            if (huud != null &&
                huud.youAreIn &&
                huud.active &&
                (_tab == _Tab.chat || (!huud.live && _tab != _Tab.people)))
              _chatInput(n),
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
    final live = huud?.live ?? false;
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
        // Members: the bell — mute or unmute "it's Live" notifications.
        if (huud != null && huud.active && huud.youAreIn && !huud.youOwn)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: circle(huud.muted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded,
                huud.muted ? 'Unmute notifications' : 'Mute notifications', () => _toggleMute(huud),
                key: const ValueKey('huud-mute')),
          ),
        if (hosting && live)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Semantics(
              button: true,
              label: 'End Live',
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
                    Text('End Live', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: n.danger)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  /// Whoever is speaking right now, in a small dark box beside the chips.
  Widget? _talkingNow(HuudSpace huud) {
    final call = HangoutState.instance;
    if (call.roomName != huud.voiceRoom) return null;
    final me = call.room?.localParticipant;
    final names = [
      for (final p in call.participants)
        if (p.isSpeaking) p == me ? 'You' : (p.name.isEmpty ? 'Someone' : p.name),
    ];
    if (names.isEmpty) return null;
    final text = switch (names) {
      ['You'] => "You're talking",
      [final one] => '$one is talking',
      [final a, final b] => '$a & $b are talking',
      _ => '${names.first} +${names.length - 1} talking',
    };
    return Container(
      key: const ValueKey('huud-talking'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: kCabinetInk, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.graphic_eq_rounded, size: 16, color: HuudColors.of(context).orange),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white)),
      ]),
    );
  }

  Widget _hero(HuudSpace huud) {
    final host = huud.host;
    final hostLine = huud.youAreHost
        ? (huud.youOwn && !huud.live ? "It's your Huud" : "You're the host")
        : (host == null
            ? 'Looking for a host'
            : '${huud.live ? 'Host' : 'Owner'}: ${host.userId == _me ? 'you' : host.handle}');
    return HuudHeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (huud.active)
            huud.live
                ? const HuudChip('Live', emoji: '🔴', onOrange: true)
                : const HuudChip('Offline', emoji: '🌙', onOrange: true)
          else
            const HuudChip('Ended', emoji: '🌙', onOrange: true),
          HuudChip(huud.privacy.label, emoji: huud.privacy.emoji, onOrange: true),
          if (huud.shared && huud.active) const HuudChip('On the feed', emoji: '📣', onOrange: true),
          if (huud.watching > 0 && huud.active) HuudChip('${huud.watching} watching', emoji: '👀', onOrange: true),
          if (_talkingNow(huud) case final talking?) talking,
          if (_unread > 0 && huud.youAreIn)
            HuudGlow(
              child: GestureDetector(
                key: const ValueKey('huud-unread-chip'),
                onTap: () => _openTab(_Tab.chat),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: kCabinetInk, borderRadius: BorderRadius.circular(999)),
                  child: Text(_unread == 1 ? '💬 1 new message' : '💬 $_unread new messages',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              ),
            ),
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
              huud.live
                  ? '${huud.liveCount} in Huud · ${huud.memberCount} ${huud.memberCount == 1 ? 'member' : 'members'}'
                  : (huud.memberCount == 1 ? '1 member' : '${huud.memberCount} members'),
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
        message: "You asked to come in. You'll get in as soon as ${huud.host?.handle ?? 'the host'} says yes.",
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

  /// The Huud between hangouts: Go Live for the owner; for members, a note that they'll hear.
  Widget _offline(NeonColors n, HuudSpace huud) {
    final h = HuudColors.of(context);
    if (huud.youOwn) {
      return HuudCard(
        key: const ValueKey('huud-offline-owner'),
        highlight: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('🌙 Your Huud is offline', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: n.ink)),
          const SizedBox(height: 4),
          Text('Go Live to hang out, talk and play. Your members, chat and code are all still here.',
              style: TextStyle(fontSize: 15, height: 1.35, color: n.mid)),
          const SizedBox(height: 14),
          HuudButton(
              key: const ValueKey('huud-go-live'),
              label: 'Go Live',
              icon: Icons.sensors_rounded,
              big: true,
              expand: true,
              onPressed: _goLive),
        ]),
      );
    }
    return HuudCard(
      key: const ValueKey('huud-offline-member'),
      child: Row(children: [
        const Text('🌙', style: TextStyle(fontSize: 30)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Not Live right now', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: n.ink)),
            const SizedBox(height: 2),
            Text(
                huud.muted
                    ? "You've muted it — tap the bell to hear when it goes Live."
                    : "You'll get a notification when ${huud.host?.handle ?? 'the owner'} goes Live.",
                style: TextStyle(fontSize: 14, height: 1.3, color: huud.muted ? n.mute : h.orangeText)),
          ]),
        ),
      ]),
    );
  }

  Widget _actions(HuudSpace huud) {
    final voice = HuudVoice.instance;
    final connected = voice.isIn(huud.voiceRoom);
    final canSpeak = huud.youCanSpeak || voice.canSpeak;
    final talking = connected && !HangoutState.instance.muted;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      HuudMicButton(
        key: const ValueKey('huud-talk'),
        talking: talking,
        label: voice.isConnecting(huud.voiceRoom)
            ? 'Joining…'
            : talking
                ? 'Talking'
                : 'Muted',
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
      if (!huud.youOwn)
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
                  Text(r.from.handle,
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
      label: '${yes ? 'Yes' : 'No'} to ${r.from.handle}',
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
                  HuudGlow(
                    child: Container(
                      key: ValueKey('huud-tab-${tab.name}-unread'),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: h.orange, borderRadius: BorderRadius.circular(10)),
                      child: Text('$badge',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: h.onOrange)),
                    ),
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
        if (huud.live) tab(_Tab.play, '🎮', 'Play'),
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
                message: '${huud.host?.handle ?? 'The host'} will pick a game soon. Chat while you wait!',
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
              child: Text(players.map((p) => p.userId == _me ? 'You' : p.handle).join(', '),
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
      if (!huud.youAreHost) return [note('${huud.host?.handle ?? 'The host'} is picking the next game…')];
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
    final main = game.youArePlaying
        ? HuudButton(
            key: const ValueKey('huud-open-game'),
            label: game.playing
                ? 'Back to the game'
                : huud.youAreHost
                    ? 'Open the game to start'
                    : 'Open the game',
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
                ? note("✋ You asked to play — waiting for ${huud.host?.handle ?? 'the host'}")
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
      if (game.youArePlaying && game.waiting && !huud.youAreHost) ...[
        note('You\'re playing 🎮 — waiting for ${huud.host?.handle ?? 'the host'} to start'),
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
    // A box of its own: a fixed height (about four to six messages), scrolling
    // inside the page, newest at the bottom.
    final height = (MediaQuery.sizeOf(context).height * 0.4).clamp(240.0, 380.0);
    final h = HuudColors.of(context);
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: Container(
            key: const ValueKey('huud-chat-box'),
            height: height,
            decoration: BoxDecoration(
              color: n.panel,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: n.line, width: 1.4),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              NotificationListener<ScrollNotification>(
                onNotification: (_) {
                  if (_unread > 0 && _chatAtBottom) setState(() => _unread = 0);
                  return false;
                },
                // Newest at the bottom and always in view: the list is laid out
                // from the bottom up, so it opens on the last message and a new
                // one lands right there — no dragging to find it.
                child: ListView.builder(
                  controller: _chatScroll,
                  reverse: true,
                  padding: EdgeInsets.fromLTRB(14, 14, 14, _unread > 0 ? 54 : 14),
                  itemCount: chat.length,
                  itemBuilder: (context, j) {
                    final i = chat.length - 1 - j;
                    // A new header when someone else speaks, or after a 5-minute pause.
                    return _bubble(n, chat[i],
                        showName: i == 0 ||
                            chat[i - 1].from.userId != chat[i].from.userId ||
                            chat[i].at.difference(chat[i - 1].at).inMinutes >= 5);
                  },
                ),
              ),
              if (_unread > 0)
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: HuudGlow(
                      child: Material(
                        color: h.orange,
                        shape: const StadiumBorder(),
                        child: InkWell(
                          key: const ValueKey('huud-chat-newest'),
                          customBorder: const StadiumBorder(),
                          onTap: _readNewest,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            child: Text('New messages ↓',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: h.onOrange)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ];
  }

  /// One chat message, kept small so plenty fit on screen. Each run of
  /// messages from the same person starts with their face, username and when.
  Widget _bubble(NeonColors n, HuudChatMessage m, {required bool showName}) {
    final h = HuudColors.of(context);
    final mine = m.from.userId == _me;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: mine ? h.orange : n.panel,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: mine ? kCabinetInk : n.line, width: mine ? 1.4 : 1),
      ),
      child: Text(m.body, style: TextStyle(fontSize: 14.5, height: 1.25, color: mine ? h.onOrange : n.ink)),
    );
    return Padding(
      key: ValueKey('chat-${m.id}'),
      padding: EdgeInsets.only(top: showName ? 9 : 3),
      child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        if (showName)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Avatar(m.from.name, size: 20, imageUrl: m.from.avatarUrl),
              const SizedBox(width: 6),
              Text(mine ? 'You' : m.from.handle,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: mine ? h.orangeText : n.ink)),
              const SizedBox(width: 6),
              Text(huudChatTime(m.at),
                  key: ValueKey('chat-time-${m.id}'), style: TextStyle(fontSize: 12, color: n.mute)),
            ]),
          ),
        Padding(
          padding: EdgeInsets.only(left: mine ? 0 : 26),
          child: mine
              ? bubble
              : GestureDetector(
                  onLongPress: () => showSafetySheet(context,
                      userId: m.from.userId, name: m.from.handle, huudSpaceId: widget.id, messageId: m.id),
                  child: bubble,
                ),
        ),
      ]),
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
                  Text(p.userId == _me ? 'You' : p.handle,
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
              label: huud.youAreHost ? 'Invite friends' : 'Share the link',
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

  /// Put the Huud on the feed, for friends to see and join.
  Future<void> _postOnFeed() async {
    setState(() => _busy = 'feed');
    try {
      await AppScope.of(context).api.post('/huud-spaces/${widget.huud.id}/share', {'message': 'Come join my Huud! 🎉'});
      if (mounted) huudSnack(context, 'Posted on the feed 📣');
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, "That didn't work — check your internet and try again.");
    } finally {
      if (mounted) setState(() => _busy = null);
    }
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
                    child: Text(f.handle,
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
            if (widget.huud.code != null) ...[
              _LinkActions(huud: widget.huud),
              const SizedBox(height: 10),
              HuudButton(
                key: const ValueKey('invite-post-feed'),
                label: 'Post on feed',
                icon: Icons.campaign_rounded,
                kind: HuudButtonKind.soft,
                expand: true,
                busy: _busy == 'feed',
                onPressed: _postOnFeed,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Huud's link, ready to copy or share: playhuud.com/huud/CODE.
class _LinkActions extends StatelessWidget {
  const _LinkActions({required this.huud});
  final HuudSpace huud;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: h.orangeSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: h.orange.withValues(alpha: 0.6)),
        ),
        child: Row(children: [
          const Text('🔗', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(huudLink(huud.code!).replaceFirst('https://', ''),
                key: const ValueKey('huud-link'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: n.ink)),
          ),
          TextButton(
            key: const ValueKey('huud-link-copy'),
            onPressed: () => copyHuudLink(context, huud),
            child: Text('Copy', style: TextStyle(fontWeight: FontWeight.w900, color: h.orangeText)),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Builder(
        builder: (button) => HuudButton(
          key: const ValueKey('huud-link-share'),
          label: 'Share link',
          icon: Icons.ios_share_rounded,
          expand: true,
          onPressed: () => shareHuud(button, huud),
        ),
      ),
    ]);
  }
}

/// For members: the Huud's link to pass on.
class _ShareLinkSheet extends StatelessWidget {
  const _ShareLinkSheet({required this.huud});
  final HuudSpace huud;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Invite to ${huud.name}',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: n.ink)),
          const SizedBox(height: 4),
          Text('Anyone with the link can open the Huud in PlayHuud — or get the app first.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: n.mid)),
          const SizedBox(height: 16),
          if (huud.code != null) _LinkActions(huud: huud),
        ]),
      ),
    );
  }
}

/// Host only: rename the Huud, change who can join, and put it on the feed.
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.huud});

  /// What the sheet hands back when the owner deleted the Huud.
  static const deleted = 'deleted';
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

  Future<void> _delete() async {
    final ok = await confirmHuud(
      context,
      emoji: '🗑️',
      title: 'Delete ${widget.huud.name}?',
      message: 'This removes the Huud for everyone — its members, chat and code. You can\'t undo this.',
      yes: 'Delete forever',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).api.delete('/huud-spaces/${widget.huud.id}');
      if (mounted) Navigator.of(context).pop(_SettingsSheet.deleted);
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, "That didn't work — try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            if (widget.huud.youOwn) ...[
              const SizedBox(height: 22),
              Divider(color: n.line),
              const SizedBox(height: 10),
              HuudButton(
                key: const ValueKey('settings-delete'),
                label: 'Delete Huud',
                icon: Icons.delete_forever_rounded,
                kind: HuudButtonKind.danger,
                expand: true,
                onPressed: _busy ? null : _delete,
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
