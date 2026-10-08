import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/hangout_state.dart';
import '../calls/call_screen.dart';
import 'social_huud_controller.dart';
import 'social_huud_entry.dart';
import 'social_huud_models.dart';
import 'social_huud_game_screen.dart';

class SocialHuudScreen extends StatefulWidget {
  const SocialHuudScreen(
      {super.key, required this.initial, this.browseHuuds = const []});
  final SocialHuud initial;
  final List<SocialHuud> browseHuuds;
  @override
  State<SocialHuudScreen> createState() => _SocialHuudScreenState();
}

class _SocialHuudScreenState extends State<SocialHuudScreen> {
  SocialHuudController? _controller;
  bool _matchOpen = false;
  String? _lastOpened;
  bool _switching = false;
  bool get _canSwipe =>
      widget.browseHuuds.length > 1 &&
      !_controller!.huud.participant &&
      !_controller!.isHost;
  Future<void> _swipe(int direction) async {
    if (!_canSwipe || _switching) return;
    final index =
        widget.browseHuuds.indexWhere((h) => h.id == _controller!.huud.id);
    final next = index + direction;
    if (next < 0 || next >= widget.browseHuuds.length) return;
    _switching = true;
    if (_matchOpen) Navigator.of(context).pop();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => SocialHuudScreen(
            initial: widget.browseHuuds[next],
            browseHuuds: widget.browseHuuds)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final app = AppScope.of(context);
    _controller =
        SocialHuudController(app.api, app.user?.id ?? '', widget.initial);
    _controller!.addListener(_changed);
    _controller!.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  void _changed() {
    final c = _controller!;
    if (!mounted) return;
    setState(() {});
    if (c.huud.playing &&
        !_matchOpen &&
        c.huud.currentRoomId != _lastOpened &&
        !c.unavailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openMatch();
      });
    }
  }

  Future<void> _openMatch() async {
    final c = _controller!;
    if (_matchOpen || c.huud.currentRoomId == null) return;
    _matchOpen = true;
    _lastOpened = c.huud.currentRoomId;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SocialHuudGameScreen(
            controller: c,
            onBrowse: widget.browseHuuds.length > 1 ? _swipe : null)));
    _matchOpen = false;
    if (mounted) await c.refresh();
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller!;
    return SocialHuudScope(
        controller: c,
        child: Scaffold(
          appBar: AppBar(
              title: GestureDetector(
                  onVerticalDragEnd: _canSwipe
                      ? (details) {
                          final speed = details.primaryVelocity ?? 0;
                          if (speed.abs() > 250) _swipe(speed < 0 ? 1 : -1);
                        }
                      : null,
                  child: Text(c.huud.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              actions: [
                if (_canSwipe)
                  IconButton(
                      tooltip: 'Previous Huud',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: () => _swipe(-1)),
                if (_canSwipe)
                  IconButton(
                      tooltip: 'Next Huud',
                      icon: const Icon(Icons.arrow_downward),
                      onPressed: () => _swipe(1)),
                IconButton(
                    tooltip: 'Copy Huud link',
                    icon: const Icon(Icons.link),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                          text: 'https://playhuud.com/huuds/${c.huud.code}'));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Huud link copied')));
                    }),
                IconButton(
                    tooltip: 'Copy Huud code',
                    icon: const Icon(Icons.share_outlined),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: c.huud.code));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Huud code copied')));
                    }),
              ]),
          body: c.unavailable
              ? Center(child: Text(c.error ?? 'This Huud has ended.'))
              : HuudContents(controller: c, onOpenMatch: _openMatch),
        ));
  }
}

Future<void> huudAction(
    BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not complete that action. Try again.')));
    }
  }
}

Future<void> joinHuudVoice(BuildContext context, SocialHuudController c) async {
  await huudAction(context, () async {
    if (HangoutState.instance.roomName == 'huud-${c.huud.id}' &&
        HangoutState.instance.active) {
      HangoutState.instance.show();
      return;
    }
    // Fetch only after an explicit voice switch, so the previous session may be left first.
    if (HangoutState.instance.active) {
      final change = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Switch voice to this Huud?'),
                  content:
                      const Text('You will leave your current voice session.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Switch')),
                  ]));
      if (change != true) return;
      await HangoutState.instance.leave?.call();
      if (HangoutState.instance.active || !context.mounted) return;
    }
    final token = (await c.api.post('${c.path}/voice/token') as Map)
        .cast<String, dynamic>();
    if (!context.mounted) return;
    final opened = await CallScreen.open(
        context,
        CallScreen(
            roomName: token['roomName'] as String,
            token: token['token'] as String,
            livekitUrl: token['livekitUrl'] as String,
            title: c.huud.name,
            refreshToken: () async =>
                ((await c.api.post('${c.path}/voice/token') as Map)['token']
                    as String)));
    if (opened) HangoutState.instance.minimize();
  });
}

class HuudContents extends StatelessWidget {
  const HuudContents({super.key, required this.controller, this.onOpenMatch});
  final SocialHuudController controller;
  final VoidCallback? onOpenMatch;
  @override
  Widget build(BuildContext context) {
    final c = controller, h = c.huud;
    return RefreshIndicator(
        onRefresh: c.refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(
              '${h.viewerCount} watching · ${h.participantCount} in Huud${h.playing ? ' · ${h.playerCount} playing' : ''}'),
          if (h.description.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(h.description)),
          Text('Code ${h.code} · ${h.privacy}',
              style: Theme.of(context).textTheme.bodySmall),
          if (c.error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(c.error!)),
          const SizedBox(height: 16),
          if (!h.participant)
            FilledButton.icon(
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(h.joinRequestStatus == 'requested'
                    ? 'Join requested'
                    : 'Request to Join Huud'),
                onPressed: c.busy || h.joinRequestStatus == 'requested'
                    ? null
                    : () =>
                        huudAction(context, () => c.action('/join-request'))),
          if (h.participant)
            ListenableBuilder(
                listenable: HangoutState.instance,
                builder: (context, _) {
                  final voice = HangoutState.instance;
                  final connected =
                      voice.active && voice.roomName == 'huud-${h.id}';
                  return Row(children: [
                    Expanded(
                        child: OutlinedButton.icon(
                            icon: Icon(
                                connected ? Icons.graphic_eq : Icons.headset),
                            label: Text(connected
                                ? 'Open Huud voice'
                                : 'Join Huud voice'),
                            onPressed: () => joinHuudVoice(context, c))),
                    if (connected)
                      IconButton(
                          tooltip: voice.muted ? 'Unmute' : 'Mute',
                          icon: Icon(voice.muted ? Icons.mic_off : Icons.mic),
                          onPressed: voice.toggleMute),
                  ]);
                }),
          const Divider(height: 32),
          Text(h.gameType == null ? 'No game selected' : h.gameName,
              style: Theme.of(context).textTheme.titleLarge),
          Text(switch (h.activity) {
            'waiting' => 'Waiting for players',
            'playing' => 'Game in progress',
            'results' => 'Game finished — everyone stays in the Huud',
            _ => 'Hang out, talk and chat'
          }),
          if (c.isHost && !h.playing)
            OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: Text(
                    h.gameType == null ? 'Add Game' : 'Choose Another Game'),
                onPressed: c.busy ? null : () => chooseHuudGame(context, c)),
          if (h.waiting && c.isHost)
            TextButton(
                onPressed: c.busy ? null : () => chooseHuudMode(context, c),
                child: const Text('Game rules / mode')),
          if (h.waiting) ...[
            Text(
                '${h.selectedPlayers.length} / ${h.maxPlayers == 2147483647 ? 'open' : h.maxPlayers} players selected'
                '${h.allowedCounts.isNotEmpty ? ' · ${h.allowedCounts.join(', ')} players required' : ''}'),
            if (h.participant && !c.isHost)
              FilledButton(
                  onPressed: c.busy ||
                          ['requested', 'selected']
                              .contains(h.gameRequestStatus)
                      ? null
                      : () =>
                          huudAction(context, () => c.action('/game-request')),
                  child: Text(switch (h.gameRequestStatus) {
                    'requested' => 'Requested',
                    'selected' => "You're selected for the next game",
                    'not_selected' => 'Not selected · Request again',
                    _ => 'Request to Play'
                  })),
            if (c.isHost) ...[
              if (h.participant)
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Include me as a player'),
                    value: h.selectedPlayers.contains(c.userId),
                    onChanged: c.busy
                        ? null
                        : (v) => huudAction(
                            context,
                            () => c.action(
                                '/roster/${c.userId}', {'selected': v}))),
              for (final p in h.gameRequests.where((p) => p.userId != c.userId))
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.username),
                    subtitle: Text(p.status.replaceAll('_', ' ')),
                    value: h.selectedPlayers.contains(p.userId),
                    onChanged: c.busy
                        ? null
                        : (v) => huudAction(
                            context,
                            () => c.action(
                                '/roster/${p.userId}', {'selected': v}))),
              FilledButton(
                  onPressed: c.busy || !h.validRoster
                      ? null
                      : () => huudAction(context, () => c.action('/start')),
                  child: const Text('Start Game')),
            ],
          ],
          if (h.playing && onOpenMatch != null)
            FilledButton(
                onPressed: onOpenMatch,
                child: Text(h.selectedPlayers.contains(c.userId)
                    ? 'Return to Game'
                    : 'Watch Game')),
          if (h.results && c.isHost)
            FilledButton(
                onPressed: c.busy
                    ? null
                    : () => huudAction(context, () => c.action('/rematch')),
                child: const Text('Rematch')),
          if (c.isHost && h.gameType != null && !h.playing)
            TextButton(
                onPressed: c.busy
                    ? null
                    : () => huudAction(context, () => c.action('/hang-out')),
                child: const Text('Just Hang Out')),
          if (c.isHost && h.joinRequests.isNotEmpty) ...[
            const Divider(height: 32),
            Text('Huud join requests',
                style: Theme.of(context).textTheme.titleMedium),
            for (final p in h.joinRequests)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.username),
                  subtitle: const Text('Joining gives voice and chat access'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        tooltip: 'Reject',
                        icon: const Icon(Icons.close),
                        onPressed: c.busy
                            ? null
                            : () => huudAction(
                                context,
                                () => c.action('/join-requests/${p.userId}',
                                    {'accepted': false}))),
                    IconButton(
                        tooltip: 'Accept',
                        icon: const Icon(Icons.check),
                        onPressed: c.busy
                            ? null
                            : () => huudAction(
                                context,
                                () => c.action('/join-requests/${p.userId}',
                                    {'accepted': true}))),
                    PopupMenuButton<String>(
                        onSelected: (action) =>
                            moderateHuud(context, c, p, action),
                        itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'report', child: Text('Report')),
                              PopupMenuItem(
                                  value: 'block', child: Text('Block')),
                              PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Ban From Huud')),
                            ]),
                  ])),
          ],
          const Divider(height: 32),
          Text('In Huud', style: Theme.of(context).textTheme.titleMedium),
          for (final p in h.participants)
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ListenableBuilder(
                    listenable: HangoutState.instance,
                    builder: (context, _) {
                      final speaking = HangoutState.instance.roomName ==
                              'huud-${h.id}' &&
                          HangoutState.instance.participants.any(
                              (v) => v.identity == p.userId && v.isSpeaking);
                      return Icon(
                          speaking ? Icons.graphic_eq : Icons.person_outline);
                    }),
                title: Text(p.username),
                subtitle: Text(p.userId == h.ownerId
                    ? 'Admin'
                    : h.selectedPlayers.contains(p.userId) && h.playing
                        ? 'Playing'
                        : 'Participant'),
                trailing: p.userId == c.userId
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (action) =>
                            moderateHuud(context, c, p, action),
                        itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'report', child: Text('Report')),
                              const PopupMenuItem(
                                  value: 'block', child: Text('Block')),
                              const PopupMenuItem(
                                  value: 'friend', child: Text('Add Friend')),
                              if (c.isHost)
                                const PopupMenuItem(
                                    value: 'mute', child: Text('Mute Mic')),
                              if (c.isHost)
                                const PopupMenuItem(
                                    value: 'remove',
                                    child: Text('Remove From Huud')),
                              if (c.isHost &&
                                  (h.waiting || h.playing) &&
                                  h.selectedPlayers.contains(p.userId))
                                const PopupMenuItem(
                                    value: 'game',
                                    child: Text('Remove From Game')),
                            ])),
          const Divider(height: 32),
          Text('Huud Chat', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 220, child: HuudChat(controller: c)),
          if (c.isHost)
            Wrap(spacing: 8, children: [
              TextButton(
                  onPressed: () => inviteHuudFriend(context, c),
                  child: const Text('Invite Friend')),
              TextButton(
                  onPressed: () => huudAction(context, () async {
                        final body =
                            await showCreateHuudPrompt(context, edit: h);
                        if (body != null) {
                          await c.api.patch(c.path, body);
                          await c.refresh();
                        }
                      }),
                  child: const Text('Edit Huud')),
              TextButton(
                  onPressed: c.busy ? null : () => endHuud(context, c),
                  child: const Text('End Huud')),
            ]),
          if (h.participant)
            TextButton(
                onPressed: c.busy
                    ? null
                    : () => huudAction(context, () async {
                          await c.action('/leave');
                          if (HangoutState.instance.roomName ==
                              'huud-${h.id}') {
                            await HangoutState.instance.leave?.call();
                          }
                          if (context.mounted) Navigator.of(context).pop();
                        }),
                child: const Text('Leave Huud')),
          const SizedBox(height: 48),
        ]));
  }
}

Future<void> chooseHuudGame(
    BuildContext context, SocialHuudController c) async {
  await huudAction(context, () async {
    final games = await c.api.get('/huuds/sessions/games') as List;
    if (!context.mounted) return;
    final type = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (ctx) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('Choose a game')),
              for (final game in games)
                ListTile(
                    title: Text(socialGameName(game['gameType'] as String)),
                    onTap: () => Navigator.pop(ctx, game['gameType'])),
            ])));
    if (type != null) await c.action('/game', {'gameType': type});
  });
}

Future<void> endHuud(BuildContext context, SocialHuudController c) async {
  final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
              title: const Text('End Huud?'),
              content: Text(c.huud.playing
                  ? 'This will cancel the current match without a competitive result and end voice for everyone.'
                  : 'Everyone will leave this session and its code will expire.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('End Huud')),
              ]));
  if (yes == true && context.mounted) {
    await huudAction(context, () => c.action('/end'));
  }
}

Future<void> inviteHuudFriend(
    BuildContext context, SocialHuudController c) async {
  await huudAction(context, () async {
    final allFriends = await c.api.get('/friends') as List;
    final friends =
        allFriends.where((f) => f['agentGameType'] == null).toList();
    if (!context.mounted) return;
    final id = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (ctx) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('Invite a friend')),
              if (friends.isEmpty)
                const ListTile(
                    title: Text('Add friends or share your Huud code.')),
              for (final friend in friends)
                ListTile(
                    title: Text(friend['username'] as String? ??
                        friend['displayName'] as String? ??
                        'Friend'),
                    onTap: () => Navigator.pop(ctx, friend['userId'])),
            ])));
    if (id != null) await c.action('/invites/$id');
  });
}

Future<void> moderateHuud(BuildContext context, SocialHuudController c,
    HuudParticipant p, String action,
    {String? messageId}) async {
  await huudAction(context, () async {
    if (action == 'mute') {
      await c.action('/participants/${p.userId}/mute');
    }
    if (action == 'remove') {
      await c.action('/participants/${p.userId}', null, true);
    }
    if (action == 'game') {
      await c.action('/game-players/${p.userId}/remove');
    }
    if (action == 'block') {
      await c.action('/blocks/${p.userId}');
    }
    if (action == 'friend') {
      await c.api.post('/friends/requests/user/${p.userId}');
    }
    if (action == 'report') {
      if (!context.mounted) return;
      final reason = TextEditingController();
      final text = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: Text('Report ${p.username}'),
                  content: TextField(
                      controller: reason,
                      maxLength: 1000,
                      decoration:
                          const InputDecoration(labelText: 'What happened?')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () {
                          if (reason.text.trim().isNotEmpty) {
                            Navigator.pop(ctx, reason.text.trim());
                          }
                        },
                        child: const Text('Report'))
                  ]));
      Future<void>.delayed(const Duration(seconds: 1), reason.dispose);
      if (text != null) {
        await c.action('/reports', {
          'userId': p.userId,
          'reason': text,
          if (messageId != null) 'messageId': messageId
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Report submitted')));
        }
      }
    }
  });
}

class HuudChat extends StatefulWidget {
  const HuudChat({super.key, required this.controller});
  final SocialHuudController controller;
  @override
  State<HuudChat> createState() => _HuudChatState();
}

class _HuudChatState extends State<HuudChat> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_input.text.trim().isEmpty) return;
    final text = _input.text.trim();
    await huudAction(context, () async {
      await widget.controller.action('/chat', {'text': text});
      _input.clear();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        return Column(children: [
          Expanded(
              child: c.messages.isEmpty
                  ? const Center(child: Text('Start the conversation.'))
                  : ListView.builder(
                      reverse: true,
                      itemCount: c.messages.length,
                      itemBuilder: (context, i) {
                        final m = c.messages[i];
                        return ListTile(
                            dense: true,
                            title: Text(m['text'] as String),
                            subtitle: Text(m['username'] as String),
                            onLongPress: m['userId'] == c.userId
                                ? null
                                : () => moderateHuud(
                                    context,
                                    c,
                                    HuudParticipant(
                                        userId: m['userId'] as String,
                                        username: m['username'] as String),
                                    'report',
                                    messageId: m['id'] as String));
                      })),
          if (c.huud.participant)
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _input,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                          hintText: 'Message your Huud', counterText: ''),
                      onSubmitted: (_) => _send())),
              IconButton(
                  tooltip: 'Send',
                  icon: const Icon(Icons.send),
                  onPressed: c.busy ? null : _send)
            ]),
          if (!c.huud.participant)
            const Text('Join the Huud to chat and use voice.'),
        ]);
      });
}

Future<void> chooseHuudMode(
    BuildContext context, SocialHuudController c) async {
  await huudAction(context, () async {
    final type = c.huud.gameType;
    final options = <String, Map<String, dynamic>>{};
    switch (type) {
      case 'goosi':
        options.addAll({
          'Relay Four': {'mode': 'relay'},
          'Oware Abapa': {'mode': 'oware'}
        });
      case 'whot':
        options.addAll({
          'Classic Whot': {'mode': 'classic'},
          'The Tell · 4, 6 or 8 players': {'mode': 'tell'}
        });
      case 'draughts':
        options.addAll({
          'Casual captures': {'mandatoryCapture': false},
          'Mandatory captures': {'mandatoryCapture': true}
        });
      case 'chess':
        options.addAll({
          '5 minutes': {'initialSeconds': 300, 'incrementSeconds': 0},
          '10 minutes + 5 seconds': {
            'initialSeconds': 600,
            'incrementSeconds': 5
          }
        });
      case 'ludo':
        options.addAll({
          'Four pieces': {'twoPlayerPieces': 4},
          'Eight pieces in 1v1': {'twoPlayerPieces': 8}
        });
      case 'wordbluff':
        options.addAll({
          'Voice clues': {'textMode': false},
          'Text clues': {'textMode': true}
        });
      case 'truearena':
        final presets = await c.api.get('/config/presets') as List;
        for (final p in presets) {
          options[p['name'] as String] =
              (p['config'] as Map).cast<String, dynamic>();
        }
    }
    if (!context.mounted) return;
    final config = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (ctx) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              ListTile(
                  title: Text('${c.huud.gameName} rules / mode'),
                  subtitle: const Text(
                      'Changing rules opens a fresh roster request stage.')),
              for (final option in options.entries)
                ListTile(
                    title: Text(option.key),
                    onTap: () => Navigator.pop(ctx, option.value)),
            ])));
    if (config != null) {
      await c.action('/game', {'gameType': type, 'gameConfig': config});
    }
  });
}
