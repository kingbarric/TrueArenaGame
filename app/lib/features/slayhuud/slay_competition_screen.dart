import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_state.dart';
import '../../core/game_socket.dart';
import 'slay_models.dart';
import 'slay_theme.dart';
import '../../theme/neon_theme.dart';
import 'slay_studio_screen.dart';
import 'slay_game_menu.dart';

class SlayCompetitionScreen extends StatefulWidget {
  const SlayCompetitionScreen({super.key, this.competitionId, this.roomId})
      : assert(competitionId != null || roomId != null);
  final String? competitionId, roomId;
  @override
  State<SlayCompetitionScreen> createState() => _SlayCompetitionScreenState();
}

class _SlayCompetitionScreenState extends State<SlayCompetitionScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _state, _catalog, _profile, _ballot;
  String? _error;
  bool _busy = false, _refreshing = false;
  String _body = 'female';
  Timer? _timer;
  GameSocket? _socket;
  StreamSubscription? _events;
  Duration _offset = Duration.zero;
  bool _suspended = false;
  SlayApi get _api => SlayApi(AppScope.of(context).api);
  String get _id => _state?['id'] ?? widget.competitionId ?? widget.roomId!;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _events?.cancel();
    _socket?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _suspended = state != AppLifecycleState.resumed;
    if (!_suspended) _refresh();
  }

  Future<void> _load() async {
    try {
      final api = _api;
      final data = await Future.wait([
        api.catalog(),
        api.profile(),
        widget.competitionId != null
            ? api.competition(widget.competitionId!)
            : api.room(widget.roomId!)
      ]);
      if (!mounted) return;
      setState(() {
        _catalog = data[0];
        _profile = data[1];
        _apply(data[2]);
      });
      final room = _state!['roomId'];
      if (room != null) {
        _socket = GameSocket.connect(api.client, room,
            spectate: _state!['role'] == 'spectator');
        _events = _socket!.envelopes.listen((event) {
          if (event['type'] == 'EVENT' &&
              (event['payload'] as Map?)?['type'] == 'SLAY_CHANGED') {
            _refresh();
          }
        });
      }
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!_suspended) _refresh();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _apply(Map<String, dynamic> value) {
    _state = value;
    if (value['body'] != null) _body = value['body'];
    _error = null;
    final server = DateTime.tryParse(value['serverTime'] ?? '');
    if (server != null) _offset = server.difference(DateTime.now().toUtc());
  }

  Future<void> _refresh() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      final value = await _api.competition(_id);
      if (mounted) setState(() => _apply(value));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _action(String action, [Map<String, dynamic>? data]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final value = await _api.action(_id, action, data);
      if (mounted) setState(() => _apply(value));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join(String role) async {
    final elimination = _state!['mode'] == 'slay_or_pass';
    final pool = _state!['contestantBody'];
    if (elimination) {
      _body = role == 'judge' ? (pool == 'male' ? 'female' : 'male') : pool;
    }
    if (!elimination) {
      final body = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: context.neon.bg,
          builder: (c) => SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SlayLabel('Your avatar for this challenge'),
                    const SizedBox(height: 16),
                    Row(children: [
                      if ((_state!['theme']['bodyEligibility'] as List)
                          .contains('female'))
                        Expanded(
                            child: SlayButton.tonal(
                                onPressed: () => Navigator.pop(c, 'female'),
                                child: const Text('Female avatar'))),
                      const SizedBox(width: 12),
                      if ((_state!['theme']['bodyEligibility'] as List)
                          .contains('male'))
                        Expanded(
                            child: SlayButton.tonal(
                                onPressed: () => Navigator.pop(c, 'male'),
                                child: const Text('Male avatar')))
                    ]),
                    const SizedBox(height: 8)
                  ]))));
      if (body == null || !mounted) return;
      _body = body;
    }
    await _action('join', {'role': role, 'body': _body});
  }

  Future<void> _style() async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => SlayStudioScreen(
                catalog: _catalog!,
                theme: Map<String, dynamic>.from(_state!['theme']),
                owned: Set<String>.from(_profile!['owned']),
                competitionId: _id,
                deadline: DateTime.tryParse(_state!['deadline'] ?? '')
                    ?.subtract(_offset),
                initialBody: _state!['mode'] == 'slay_or_pass'
                    ? _state!['contestantBody']
                    : _body)));
    if (mounted) _refresh();
  }

  Future<void> _nextBallot() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ballot = await _api.ballot(_id);
      if (mounted) {
        setState(() {
          _ballot = ballot;
          _error = ballot == null
              ? 'You have voted on all available pairs. Thank you.'
              : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report(String look) async {
    final reason = await showModalBottomSheet<String>(
        context: context,
        builder: (sheet) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Report this look',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700))),
              for (final reason in [
                'Inappropriate image',
                'Harassment',
                'Cheating or misleading submission',
                'Other concern'
              ])
                ListTile(
                    title: Text(reason),
                    onTap: () => Navigator.pop(sheet, reason)),
            ])));
    if (reason == null || !mounted) return;
    try {
      await _api.report(look, reason);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Report received.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _block(String user) async {
    try {
      await _api.block(user);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Player blocked from future rooms and voting.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _vote(String entry) async {
    if (_busy || _ballot == null) return;
    setState(() => _busy = true);
    try {
      await _api.vote(_ballot!['id'], entry);
      if (mounted) setState(() => _ballot = null);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && _ballot == null) _nextBallot();
  }

  Future<void> _post() async {
    try {
      await _api.client.post('/huud/posts', {
        'gameType': 'slayhuud',
        'seats': _state!['seats'],
        'ranked': true,
        'message':
            '${_state!['theme']['title']} · ${_state!['mode'] == 'slay_or_pass' ? 'Slay or Pass' : _state!['mode'] == 'group' ? 'Group competition' : 'Style Battle'}. Join my runway.'
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your game request is on Huud.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String get _remaining {
    final deadline = DateTime.tryParse(_state?['deadline'] ?? '');
    if (deadline == null) return '';
    final seconds = deadline
        .difference(DateTime.now().toUtc().add(_offset))
        .inSeconds
        .clamp(0, 999999);
    return seconds >= 3600
        ? '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m'
        : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: slayTheme(context),
      child: Builder(
          builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('The runway'), actions: [
                if (_state?['roomCode'] != null)
                  TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: _state!['roomCode']));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Room code copied')));
                      },
                      icon: const Icon(Icons.copy, size: 15),
                      label: Text(_state!['roomCode'])),
                SlayGameMenu(
                    onExit: () => leaveSlayScreen(context),
                    exitLabel: 'Back to SlayHuud'),
              ]),
              body: SafeArea(
                  child: _state == null
                      ? Center(
                          child: _error == null
                              ? const CircularProgressIndicator()
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                      Text(_error!),
                                      TextButton(
                                          onPressed: _load,
                                          child: const Text('Try again'))
                                    ]))
                      : ListView(padding: const EdgeInsets.all(20), children: [
                          Row(children: [
                            Expanded(
                                child: SlayLabel(_state!['mode']
                                    .toString()
                                    .replaceAll('_', ' '))),
                            if (_remaining.isNotEmpty)
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                      color: context.neon.plate,
                                      borderRadius: BorderRadius.circular(30)),
                                  child: Text(_remaining,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)))
                          ]),
                          const SizedBox(height: 12),
                          Text(_state!['theme']['title'],
                              style: Theme.of(context).textTheme.displaySmall),
                          const SizedBox(height: 8),
                          Text(_state!['theme']['description'],
                              style: TextStyle(color: context.neon.mute)),
                          const SizedBox(height: 12),
                          Wrap(spacing: 7, runSpacing: 5, children: [
                            for (final category in _state!['theme']
                                ['requiredCategories'] as List)
                              Chip(
                                  label: Text(category,
                                      style: const TextStyle(fontSize: 11)),
                                  avatar: const Icon(Icons.checkroom, size: 13))
                          ]),
                          const SizedBox(height: 20),
                          if (_error != null)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(_error!,
                                    style: const TextStyle(color: Colors.red))),
                          ..._content(context),
                          if (_state!['developmentAssets'] == true) ...[
                            const SizedBox(height: 20),
                            Center(
                                child: Text(
                                    'Practice competition · Slay rating stays unchanged',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: context.neon.mute)))
                          ],
                        ])))));
  List<Widget> _content(BuildContext context) {
    final s = _state!, role = s['role'], status = s['status'];
    if (status == 'lobby') {
      return [
        SlayPanel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SlayLabel('The room is open'),
          const SizedBox(height: 16),
          Text('${s['contestants']} / ${s['seats']}',
              style: Theme.of(context).textTheme.displaySmall),
          Text('Contestants on the guest list',
              style: TextStyle(color: context.neon.mute)),
          if (s['mode'] == 'slay_or_pass') ...[
            const SizedBox(height: 12),
            Text('${s['judges']} / 6 judges · 3 required',
                style: TextStyle(color: context.neon.brand))
          ],
          const SizedBox(height: 24),
          if (role == 'spectator') ...[
            SizedBox(
                width: double.infinity,
                child: SlayButton(
                    onPressed: _busy ? null : () => _join('contestant'),
                    child: const Text('Take a contestant seat'))),
            if (s['mode'] == 'slay_or_pass')
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                          onPressed: _busy ? null : () => _join('judge'),
                          child: const Text('Join as a judge'))))
          ] else
            Text(
                role == 'judge'
                    ? 'You are on the judging panel.'
                    : 'Your contestant seat is reserved.',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          if (s['host'] == true && role != 'spectator') ...[
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: SlayButton(
                    onPressed: _busy ? null : () => _action('start'),
                    child: const Text('Start the challenge')))
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: _busy ? null : _post,
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('Invite through Huud')),
          if (s['host'] == true)
            TextButton(
                onPressed: _busy ? null : () => _action('cancel'),
                child: const Text('Cancel waiting room')),
        ]))
      ];
    }
    if (status == 'styling') {
      return [
        if (role == 'spectator' && ['daily', 'weekly'].contains(s['mode']))
          SlayPanel(
              child: Column(children: [
            const Text('Enter whenever inspiration strikes.'),
            const SizedBox(height: 16),
            SlayButton(
                onPressed: _busy ? null : () => _join('contestant'),
                child: const Text('Enter this challenge'))
          ]))
        else
          SlayPanel(
              child: Column(children: [
            Icon(role == 'judge' ? Icons.visibility_outlined : Icons.checkroom,
                size: 48, color: context.neon.brand),
            const SizedBox(height: 18),
            Text(
                s['submitted'] == true
                    ? 'Your look is on the runway.'
                    : s['eliminated'] == true
                        ? 'Your runway run has ended.'
                        : role == 'contestant'
                            ? 'This is your moment.'
                            : 'The contestants are styling.',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
                s['submitted'] == true
                    ? 'Voting opens when the other looks arrive.'
                    : s['eliminated'] == true
                        ? 'Stay to see who takes the crown.'
                        : 'Round ${s['round']} · the same brief for everyone.',
                style: TextStyle(color: context.neon.mute)),
            if (role == 'contestant' &&
                s['submitted'] != true &&
                s['eliminated'] != true) ...[
              const SizedBox(height: 24),
              SizedBox(
                  width: double.infinity,
                  child: SlayButton(
                      onPressed: _busy ? null : _style,
                      child: const Text('Open my wardrobe')))
            ]
          ]))
      ];
    }
    if (status == 'voting') {
      if (s['mode'] == 'slay_or_pass') {
        final entries = (s['entries'] as List).cast<Map>();
        if (entries.isEmpty) {
          return [const Text('The next look is being revealed…')];
        }
        if (s['finalRound'] == true) {
          return [
            const Center(
                child: SlayLabel('Final two · choose who slayed the theme')),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final entry in entries)
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Column(children: [
                          AspectRatio(
                              aspectRatio: 2 / 3,
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: SlayImage(
                                      url: _api.imageUrl(entry['image']),
                                      headers: _api.imageHeaders,
                                      onReport: () =>
                                          _report(entry['lookId'])))),
                          const SizedBox(height: 12),
                          if (role == 'judge' && s['judged'] != true)
                            SlayButton(
                                onPressed: _busy
                                    ? null
                                    : () => _action(
                                        'final-vote', {'entryId': entry['id']}),
                                child:
                                    Text('Look ${entries.indexOf(entry) + 1}')),
                        ])))
            ]),
            if (s['judged'] == true)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Your final vote is in. Waiting for the other judges.')),
          ];
        }
        final entry = entries.first;
        return [
          const SlayLabel('Judge the style · theme fit · creativity'),
          const SizedBox(height: 12),
          AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: SlayImage(
                      url: _api.imageUrl(entry['image']),
                      onReport: () => _report(entry['lookId']),
                      headers: _api.imageHeaders))),
          const SizedBox(height: 20),
          if (role == 'judge' && s['judged'] != true)
            Row(children: [
              Expanded(
                  child: SlayButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _action(
                              'judge', {'entryId': entry['id'], 'slay': true}),
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('SLAY'))),
              const SizedBox(width: 12),
              Expanded(
                  child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _action(
                              'judge', {'entryId': entry['id'], 'slay': false}),
                      child: const Text('PASS')))
            ])
          else
            Center(
                child: Text('The judging panel is deciding.',
                    style: TextStyle(color: context.neon.mute)))
        ];
      }
      if (role == 'contestant') {
        return [
          SlayPanel(
              child: Column(children: [
            Icon(Icons.how_to_vote_outlined,
                size: 48, color: context.neon.brand),
            const SizedBox(height: 16),
            const Text('Let your look do the talking.',
                style: TextStyle(fontSize: 27), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
                'Community voting is open. Contestants cannot vote in their own challenge.',
                style: TextStyle(color: context.neon.mute),
                textAlign: TextAlign.center)
          ]))
        ];
      }
      if (_ballot == null) {
        return [
          SlayPanel(
              child: Column(children: [
            Icon(Icons.how_to_vote_outlined,
                size: 48, color: context.neon.brand),
            const SizedBox(height: 16),
            Text('Who slayed the theme?',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text('Two looks. No names. Your eye for style.',
                style: TextStyle(color: context.neon.mute)),
            const SizedBox(height: 24),
            SizedBox(
                width: double.infinity,
                child: SlayButton(
                    onPressed: _busy ? null : _nextBallot,
                    child: const Text('Start voting')))
          ]))
        ];
      }
      return [
        const Center(child: SlayLabel('Who slayed the theme better?')),
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final side in ['A', 'B'])
            Expanded(
                child: Padding(
                    padding: EdgeInsets.only(
                        right: side == 'A' ? 6 : 0, left: side == 'B' ? 6 : 0),
                    child: Column(children: [
                      AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: SlayImage(
                                  url: _api.imageUrl(_ballot!['image$side']),
                                  onReport: () => _report(
                                      (_ballot!['image$side'] as String)
                                          .split('/')[3]),
                                  headers: _api.imageHeaders))),
                      const SizedBox(height: 12),
                      SizedBox(
                          width: double.infinity,
                          child: SlayButton(
                              onPressed: _busy
                                  ? null
                                  : () => _vote(_ballot!['entry$side']),
                              child: Text('Look $side')))
                    ])))
        ]),
        const SizedBox(height: 14),
        Center(
            child: Text('Choose the outfit, creativity and theme fit.',
                style: TextStyle(color: context.neon.mute, fontSize: 12)))
      ];
    }
    if (status == 'round_result') {
      return [
        SlayPanel(
            child: Column(children: [
          Icon(Icons.auto_awesome, color: context.neon.gold, size: 44),
          const SizedBox(height: 16),
          Text('A new round awaits.',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 10),
          Text('Remaining contestants will style a fresh theme.',
              style: TextStyle(color: context.neon.mute))
        ]))
      ];
    }
    if (status == 'results') {
      return [
        const SlayLabel('The final edit'),
        if (s['communityUsed'] == false)
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                  'Not enough community votes arrived. Results use the system style score.',
                  style: TextStyle(color: context.neon.mute))),
        if ((s['resultCount'] as int? ?? 0) > 100)
          const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                  'Top 100 · your look is also shown if it placed outside the top 100.')),
        const SizedBox(height: 14),
        for (final e in s['entries'] as List)
          Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SlayPanel(
                  padding: const EdgeInsets.all(14),
                  colour: e['placement'] == 1
                      ? context.neon.gold.withValues(alpha: .12)
                      : context.neon.panel,
                  child: Row(children: [
                    SizedBox(
                        width: 75,
                        height: 110,
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SlayImage(
                                url: _api.imageUrl(e['image']),
                                onReport: () => _report(e['lookId']),
                                onBlock: e['mine'] == true
                                    ? null
                                    : () => _block(e['userId']),
                                headers: _api.imageHeaders))),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          SlayLabel(s['draw'] == true
                              ? 'Draw'
                              : e['placement'] == 1
                                  ? 'The winner'
                                  : 'Place ${e['placement']}'),
                          const SizedBox(height: 6),
                          Text(e['username'] ?? 'Player',
                              style: Theme.of(context).textTheme.titleLarge),
                          Text('${e['score']} points',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: context.neon.brand)),
                          const SizedBox(height: 6),
                          Text(
                              'System ${e['system']['overall']} · Community ${e['community']}',
                              style: TextStyle(
                                  color: context.neon.mute, fontSize: 10))
                        ])),
                    if (e['placement'] == 1)
                      Icon(Icons.workspace_premium_outlined,
                          color: context.neon.gold, size: 30)
                  ]))),
        const SizedBox(height: 8),
        if (!['daily', 'weekly'].contains(s['mode']))
          SlayButton(
              onPressed: _busy
                  ? null
                  : () async {
                      try {
                        final next = await _api.create(
                            s['mode'] == 'battle'
                                ? 'battle'
                                : s['mode'] == 'group'
                                    ? 'group'
                                    : 'slay_or_pass',
                            s['theme']['id'],
                            s['seats'],
                            s['contestantBody']);
                        if (context.mounted) {
                          Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => SlayCompetitionScreen(
                                      competitionId: next['id'])));
                        }
                      } catch (e) {
                        if (mounted) setState(() => _error = e.toString());
                      }
                    },
              child: const Text('Run it back'))
      ];
    }
    return [const SlayPanel(child: Text('This competition has closed.'))];
  }
}
