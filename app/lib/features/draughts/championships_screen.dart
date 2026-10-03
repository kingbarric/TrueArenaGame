import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_state.dart';
import '../../core/game_socket.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../onboarding/guest_gate.dart';
import 'draughts_game_screen.dart';

const _serverError = 'Server error';

/// Championship discovery, invitations, roster, live bracket and history.
class ChampionshipsScreen extends StatefulWidget {
  const ChampionshipsScreen({super.key, this.inviteCode});
  final String? inviteCode;

  @override
  State<ChampionshipsScreen> createState() => _ChampionshipsScreenState();
}

class _ChampionshipsScreenState extends State<ChampionshipsScreen> {
  List<Map<String, dynamic>> _mine = [];
  List<Map<String, dynamic>> _public = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (widget.inviteCode != null && mounted) {
        _openInvite(widget.inviteCode!);
      }
    });
  }

  Future<void> _load() async {
    try {
      final api = AppScope.of(context).api;
      final mine = await api.get('/championships/mine') as List;
      final public = await api.get('/championships/discover') as List;
      if (!mounted) return;
      setState(() {
        _mine = mine.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _public = public.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = _serverError; });
    }
  }

  Future<void> _openInvite(String code) async {
    try {
      final data = (await AppScope.of(context).api.get('/championships/invite/${code.trim().toUpperCase()}') as Map)
          .cast<String, dynamic>();
      if (!mounted) return;
      AppScope.of(context).pendingChampionshipCode = null;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChampionshipDetailScreen(id: data['id'] as String, preview: data),
      ));
      if (mounted) _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(_serverError)));
    }
  }

  Future<void> _enterCode() async {
    final input = TextEditingController();
    final code = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Join a championship'),
      content: TextField(controller: input, autofocus: true, textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Invitation code')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, input.text), child: const Text('Continue'))],
    ));
    input.dispose();
    if (code != null && code.trim().isNotEmpty && mounted) _openInvite(code);
  }

  Future<void> _create() async {
    if (!await canHostOrPromptToVerify(context) || !mounted) return;
    final name = TextEditingController();
    int size = 8;
    bool isPublic = true;
    DateTime start = DateTime.now().add(const Duration(hours: 1));
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Create Draft Championship'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, maxLength: 80, decoration: const InputDecoration(labelText: 'Championship name')),
          DropdownButtonFormField<int>(initialValue: size, decoration: const InputDecoration(labelText: 'Players'),
            items: [4, 8, 16, 32].map((n) => DropdownMenuItem(value: n, child: Text('$n players'))).toList(),
            onChanged: (n) => setDialogState(() => size = n ?? size)),
          SwitchListTile(value: isPublic, title: Text(isPublic ? 'Public' : 'Private'),
            subtitle: Text(isPublic ? 'Discoverable and watchable' : 'Only entrants can see the bracket'),
            onChanged: (v) => setDialogState(() => isPublic = v)),
          ListTile(title: const Text('Scheduled start'), subtitle: Text(_date(start)),
            trailing: const Icon(Icons.event), onTap: () async {
              final date = await showDatePicker(context: context, initialDate: start,
                firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
              if (date == null || !context.mounted) return;
              final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
              if (time != null) setDialogState(() => start = DateTime(date.year, date.month, date.day, time.hour, time.minute));
            }),
          const Text('Starts when the time arrives and every slot is filled.'),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, {
            'name': name.text.trim(), 'size': size, 'visibility': isPublic ? 'public' : 'private',
            'scheduledAt': start.toUtc().toIso8601String(),
          }), child: const Text('Create'))],
      ),
    ));
    name.dispose();
    if (result == null || !mounted) return;
    try {
      final created = (await AppScope.of(context).api.post('/championships', result) as Map).cast<String, dynamic>();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChampionshipDetailScreen(id: created['id'] as String)));
      if (mounted) _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(_serverError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: const Text('Draft Championships')),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        NeonButton('Create Championship', onPressed: _create),
        const SizedBox(height: 8),
        NeonButton('Enter invitation code', style: NeonStyle.ghost, onPressed: _enterCode),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: n.danger)))
        else ...[
          const SizedBox(height: 24),
          Text('YOUR CHAMPIONSHIPS', style: TextStyle(color: n.gold, fontWeight: FontWeight.bold)),
          if (_mine.isEmpty && !_loading) const Padding(padding: EdgeInsets.all(12), child: Text('No championships joined yet.')),
          ..._mine.map(_tile),
          const SizedBox(height: 24),
          Text('PUBLIC CHAMPIONSHIPS', style: TextStyle(color: n.gold, fontWeight: FontWeight.bold)),
          ..._public.where((c) => !_mine.any((m) => m['id'] == c['id'])).map(_tile),
        ],
      ])),
    );
  }

  Widget _tile(Map<String, dynamic> c) => Card(child: ListTile(
    title: Text(c['name']?.toString() ?? 'Championship'),
    subtitle: Text('${c['joined']}/${c['size']} players · ${c['status']} · ${_date(DateTime.parse(c['scheduledAt'] as String).toLocal())}'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () async {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChampionshipDetailScreen(id: c['id'] as String)));
      if (mounted) _load();
    },
  ));
}

String _date(DateTime d) => '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class ChampionshipDetailScreen extends StatefulWidget {
  const ChampionshipDetailScreen({super.key, required this.id, this.preview});
  final String id;
  final Map<String, dynamic>? preview;

  @override
  State<ChampionshipDetailScreen> createState() => _ChampionshipDetailScreenState();
}

class _ChampionshipDetailScreenState extends State<ChampionshipDetailScreen> {
  Map<String, dynamic>? _data;
  Timer? _poll;
  String? _error;
  bool _joining = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _data = widget.preview;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load(silent: true));
  }

  @override
  void dispose() { _poll?.cancel(); super.dispose(); }

  Future<void> _load({bool silent = false}) async {
    try {
      final data = (await AppScope.of(context).api.get('/championships/${widget.id}') as Map).cast<String, dynamic>();
      if (mounted) setState(() { _data = data; _error = null; });
    } catch (_) {
      if (mounted && !silent && widget.preview == null) setState(() => _error = _serverError);
    }
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      final data = (await AppScope.of(context).api.post('/championships/${widget.id}/join') as Map).cast<String, dynamic>();
      if (mounted) setState(() { _data = data; _error = null; });
    } catch (_) {
      if (mounted) setState(() => _error = _serverError);
    } finally { if (mounted) setState(() => _joining = false); }
  }

  Future<void> _startNow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start championship now?'),
        content: const Text('The bracket will be created and the first matches will begin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Start now')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _starting = true);
    try {
      final data = (await AppScope.of(context).api.post('/championships/${widget.id}/start') as Map)
          .cast<String, dynamic>();
      if (mounted) setState(() { _data = data; _error = null; });
    } catch (_) {
      if (mounted) setState(() => _error = _serverError);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _openMatch(Map<String, dynamic> match, bool playing) async {
    final roomId = match['roomId']?.toString();
    if (roomId == null) return;
    final app = AppScope.of(context);
    final people = (( _data?['participants'] as List?) ?? const []).whereType<Map>();
    final names = {for (final p in people) p['id'].toString(): p['name'].toString()};
    final socket = GameSocket.connect(app.api, roomId, spectate: !playing);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DraughtsGameScreen(
      socket: socket, selfId: app.user?.id ?? '', nicknames: names,
      championshipId: widget.id, tournamentSpectator: !playing)));
    if (mounted) _load();
  }

  Future<void> _endBothAbsent(String id) async {
    try {
      await AppScope.of(context).api.post('/championships/matches/$id/end-both-absent');
      _load();
    } catch (_) {
      if (mounted) setState(() => _error = _serverError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final c = _data;
    if (c == null) return Scaffold(appBar: AppBar(title: const Text('Championship')), body: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!)));
    final people = ((c['participants'] as List?) ?? const []).whereType<Map>().toList();
    final names = {for (final p in people) p['id'].toString(): p['name'].toString()};
    final self = AppScope.of(context).user?.id;
    final joined = names.containsKey(self);
    final isCreator = c['creatorId'] == self;
    final full = c['joined'] is num && c['size'] is num && c['joined'] == c['size'];
    final start = DateTime.tryParse(c['scheduledAt']?.toString() ?? '')?.toLocal();
    final left = start == null ? Duration.zero : start.difference(DateTime.now());
    final bracket = ((c['matches'] as List?) ?? const []).whereType<Map>().toList();
    final eliminated = <String>{};
    for (final match in bracket) {
      if (match['status'] == 'completed' || match['status'] == 'no_winner') {
        for (final id in [match['playerA'], match['playerB']]) {
          if (id != null && id != match['winnerId']) eliminated.add(id.toString());
        }
      }
    }
    return Scaffold(appBar: AppBar(title: Text(c['name']?.toString() ?? 'Championship')),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Draft · single elimination · one game per pairing; draws replay'),
        const SizedBox(height: 8),
        Text('${c['joined']}/${c['size']} players · ${c['visibility']} · ${c['status']}',
          style: TextStyle(color: n.gold, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (c['status'] == 'lobby') ...[
          Text(start == null ? '' : 'Scheduled start: ${_date(start)} (your time)'),
          Text(full
              ? 'Roster full. The creator can start now, or it will start at the scheduled time.'
              : left.isNegative ? 'Waiting for the full roster'
                  : 'Starts when full in ${left.inHours}h ${left.inMinutes.remainder(60)}m ${left.inSeconds.remainder(60)}s'),
        ],
        if (c['status'] == 'completed') Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(c['championId'] == null ? 'Finished without a champion' : '🏆 ${names[c['championId']] ?? 'Champion'} · permanent badge',
            style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(height: 16),
        if (!joined && c['status'] == 'lobby') NeonButton(_joining ? 'Joining…' : 'Join Championship', onPressed: _joining ? null : _join),
        if (isCreator && full && c['status'] == 'lobby') NeonButton(
          _starting ? 'Starting…' : 'Start now', onPressed: _starting ? null : _startNow),
        if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: n.danger))),
        if (joined) ...[
          NeonButton('Invite Friends', onPressed: () => Share.share('${c['name']} · Draft knockout championship\n${c['inviteLink']}\nCode: ${c['code']}')),
          TextButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: c['code'].toString()));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied'))); },
            icon: const Icon(Icons.copy), label: Text('Code ${c['code']}')),
        ],
        const SizedBox(height: 20),
        Text('PLAYERS', style: TextStyle(color: n.gold, fontWeight: FontWeight.bold)),
        if (people.isEmpty) const Text('Join to see the roster.'),
        Wrap(spacing: 8, children: people.map((p) => Chip(
          label: Text('${p['name']}${eliminated.contains(p['id'].toString()) ? ' · out' : ''}'),
        )).toList()),
        if (bracket.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('BRACKET · ROUND ${c['currentRound']}', style: TextStyle(color: n.gold, fontWeight: FontWeight.bold)),
          ...bracket.map((m) {
            final a = m['playerA']?.toString(), b = m['playerB']?.toString();
            final active = m['status'] == 'active';
            final playing = self == a || self == b;
            final aLeft = (m['aReconnectMs'] as num?)?.toInt() ?? 0;
            final bLeft = (m['bReconnectMs'] as num?)?.toInt() ?? 0;
            final bothExpired = aLeft == 0 && bLeft == 0;
            return Card(child: Column(children: [ListTile(
              title: Text('${names[a] ?? (a == null && m['status'] == 'pending' ? 'TBD' : 'Bye')} vs ${names[b] ?? (b == null && m['status'] == 'pending' ? 'TBD' : 'Bye')}'),
              subtitle: Text('Round ${m['round']} · ${m['status']}${m['winnerId'] == null ? '' : ' · ${names[m['winnerId']] ?? 'Winner'} advances'}${active ? ' · Game ${m['gameNumber']}' : ''}'),
              trailing: active ? TextButton(onPressed: () => _openMatch(m.cast<String, dynamic>(), playing),
                child: Text(playing ? 'Play' : 'Watch')) : null,
            ), if (active && isCreator && bothExpired) TextButton(onPressed: () => _endBothAbsent(m['id'].toString()),
              child: const Text('End pairing: both absent'))]));
          }),
        ],
      ])),
    );
  }
}
