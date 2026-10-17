import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import 'slay_theme.dart';
import '../../theme/neon_theme.dart';
import 'slay_competition_screen.dart';
import 'slay_game_menu.dart';

class SlayCupsScreen extends StatefulWidget {
  const SlayCupsScreen({super.key});
  @override
  State<SlayCupsScreen> createState() => _SlayCupsScreenState();
}

class _SlayCupsScreenState extends State<SlayCupsScreen> {
  List<Map<String, dynamic>>? _cups;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final client = AppScope.of(context).api;
      final data = await Future.wait([
        client.get('/championships/mine'),
        client.get('/championships/discover')
      ]);
      final cups = <String, Map<String, dynamic>>{};
      for (final list in data) {
        for (final raw in list as List) {
          final cup = Map<String, dynamic>.from(raw);
          if (cup['gameType'] == 'slayhuud') cups[cup['id']] = cup;
        }
      }
      if (mounted) {
        setState(() {
          _cups = cups.values.toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _create() async {
    final name = TextEditingController(text: 'SlayHuud Fashion Cup');
    int size = 8;
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, update) => AlertDialog(
                    title: const Text('Create a Fashion Cup'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration:
                              const InputDecoration(labelText: 'Cup name')),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                          initialValue: size,
                          decoration:
                              const InputDecoration(labelText: 'Players'),
                          items: [
                            for (final n in [4, 8, 16, 32, 64, 128])
                              DropdownMenuItem(
                                  value: n, child: Text('$n players'))
                          ],
                          onChanged: (v) => update(() => size = v!)),
                      const SizedBox(height: 12),
                      Text(
                          'Registration opens now. Matches start when all seats are filled after the scheduled time, 10 minutes from now.',
                          style:
                              TextStyle(color: context.neon.mute, fontSize: 12))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Cancel')),
                      SlayButton(
                          onPressed: () => Navigator.pop(c, {
                                'name': name.text,
                                'size': size,
                                'gameType': 'slayhuud',
                                'visibility': 'public',
                                'scheduledAt': DateTime.now()
                                    .toUtc()
                                    .add(const Duration(minutes: 10))
                                    .toIso8601String()
                              }),
                          child: const Text('Create'))
                    ])));
    name.dispose();
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).api.post('/championships', result);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join(Map cup) async {
    try {
      await AppScope.of(context).api.post('/championships/${cup['id']}/join');
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _detail(Map cup) async {
    try {
      final detail = Map<String, dynamic>.from(
          await AppScope.of(context).api.get('/championships/${cup['id']}'));
      if (!mounted) return;
      final self = AppScope.of(context).user?.id;
      await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: context.neon.bg,
          builder: (c) => SafeArea(
              child: DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: .65,
                  builder: (c, scroll) => ListView(
                          controller: scroll,
                          padding: const EdgeInsets.all(24),
                          children: [
                            const SlayLabel('The bracket'),
                            const SizedBox(height: 10),
                            Text(detail['name'],
                                style:
                                    Theme.of(context).textTheme.headlineMedium),
                            const SizedBox(height: 16),
                            for (final match
                                in detail['matches'] as List? ?? [])
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                      'Round ${match['round']} · pairing ${match['position']}'),
                                  subtitle: Text(match['status']),
                                  trailing: match['roomId'] != null &&
                                          [match['playerA'], match['playerB']]
                                              .contains(self)
                                      ? SlayButton(
                                          onPressed: () {
                                            Navigator.pop(c);
                                            Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                    builder: (_) =>
                                                        SlayCompetitionScreen(
                                                            roomId: match[
                                                                'roomId'])));
                                          },
                                          child: const Text('Enter'))
                                      : null)
                          ]))));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: slayTheme(context),
      child: Builder(
          builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('Fashion Cups'), actions: [
                SlayGameMenu(
                    onExit: () => leaveSlayScreen(context),
                    exitLabel: 'Back to SlayHuud')
              ]),
              body: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(20), children: [
                    const SlayLabel('A different theme every round'),
                    const SizedBox(height: 12),
                    Text('Dress for the crown.',
                        style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: 10),
                    Text(
                        'Knockout Style Battles, permanent badges and a place in PlayHuud history.',
                        style: TextStyle(color: context.neon.mute)),
                    const SizedBox(height: 20),
                    SlayButton.icon(
                        onPressed: _busy ? null : _create,
                        icon: const Icon(Icons.add),
                        label: const Text('Create a Fashion Cup')),
                    const SizedBox(height: 24),
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    if (_cups == null && _error == null)
                      const Center(child: CircularProgressIndicator()),
                    if (_cups?.isEmpty == true)
                      const SlayPanel(
                          child: Text('Be the first to open a Fashion Cup.')),
                    for (final cup in _cups ?? <Map<String, dynamic>>[])
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SlayPanel(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                SlayLabel(cup['status']),
                                const SizedBox(height: 8),
                                Text(cup['name'],
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 8),
                                Text(
                                    '${cup['joined']} / ${cup['size']} players · ${cup['code']}',
                                    style: TextStyle(color: context.neon.mute)),
                                const SizedBox(height: 12),
                                Row(children: [
                                  OutlinedButton(
                                      onPressed: () => _detail(cup),
                                      child: const Text('View bracket')),
                                  const SizedBox(width: 12),
                                  if (cup['status'] == 'lobby')
                                    SlayButton(
                                        onPressed: () => _join(cup),
                                        child: const Text('Join cup'))
                                ])
                              ])))
                  ])))));
}
