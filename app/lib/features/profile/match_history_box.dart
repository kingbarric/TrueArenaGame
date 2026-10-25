import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../competitive/competitive_api.dart';
import '../competitive/competitive_models.dart';
import '../competitive/player_profile_screen.dart' show MatchRow;
import '../huud/huud_models.dart' show huudGameNames;

class MatchHistoryBox extends StatefulWidget {
  const MatchHistoryBox({super.key});
  @override
  MatchHistoryBoxState createState() => MatchHistoryBoxState();
}

class MatchHistoryBoxState extends State<MatchHistoryBox> {
  final _opponent = TextEditingController();
  Timer? _debounce;
  List<MatchHistoryEntry> _matches = const [];
  String? _game, _error;
  DateTime? _date;
  bool _started = false, _requested = false, _loading = true;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_requested) reload();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _opponent.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    _requested = true;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final matches = await CompetitiveApi(AppScope.of(context).api).myMatches(
          limit: 10,
          gameType: _game,
          opponent: _opponent.text,
          playedOn: _date);
      if (mounted && request == _request) {
        setState(() {
          _matches = matches.take(10).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _error = userRetryMessage;
          _loading = false;
        });
      }
    }
  }

  void _search(String value) {
    _debounce?.cancel();
    ++_request; // An older request must never overwrite a newly typed filter.
    _debounce = Timer(const Duration(milliseconds: 300), reload);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
        context: context,
        initialDate: _date ?? now,
        firstDate: DateTime(2020),
        lastDate: now);
    if (chosen == null || !mounted) return;
    setState(() => _date = chosen);
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final filtered =
        _game != null || _date != null || _opponent.text.trim().isNotEmpty;
    return NeonCard(
      key: const ValueKey('profile-history-box'),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Game history',
            style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w900, color: n.ink)),
        const SizedBox(height: 3),
        Text(filtered ? 'Latest 10 matching games' : 'Your latest 10 games',
            style: TextStyle(color: n.mute, fontSize: 12)),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('history-opponent'),
          controller: _opponent,
          maxLength: 80,
          decoration: const InputDecoration(
              hintText: 'Search opponent · played against',
              prefixIcon: Icon(Icons.search_rounded),
              counterText: ''),
          onChanged: _search,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, bounds) {
          final game = DropdownButtonFormField<String>(
            key: ValueKey('history-game-${_game ?? 'all'}'),
            initialValue: _game ?? 'all',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Game played'),
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All games')),
              for (final g in huudGameNames.entries)
                DropdownMenuItem(value: g.key, child: Text(g.value))
            ],
            onChanged: (v) {
              setState(() => _game = v == 'all' ? null : v);
              reload();
            },
          );
          final date = OutlinedButton.icon(
              key: const ValueKey('history-date'),
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_rounded, size: 17),
              label: Text(_date == null
                  ? 'Date played'
                  : '${_date!.day}/${_date!.month}/${_date!.year}'));
          if (bounds.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(14) > 20) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [game, const SizedBox(height: 8), date]);
          }
          return Row(children: [
            Expanded(child: game),
            const SizedBox(width: 8),
            date
          ]);
        }),
        if (filtered)
          Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  key: const ValueKey('history-clear'),
                  onPressed: () {
                    _debounce?.cancel();
                    _opponent.clear();
                    setState(() {
                      _game = null;
                      _date = null;
                    });
                    reload();
                  },
                  child: const Text('Clear filters'))),
        const SizedBox(height: 12),
        if (_loading)
          const SizedBox(
              height: 120, child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Column(children: [
            Text(_error!, style: TextStyle(color: n.danger)),
            TextButton(onPressed: reload, child: const Text('Try again'))
          ])
        else if (_matches.isEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                  filtered
                      ? 'No games match these filters.'
                      : 'No games yet — your games will show up here.',
                  key: const ValueKey('profile-no-matches'),
                  style: TextStyle(color: n.mute)))
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: Scrollbar(
                child: ListView.separated(
              key: const ValueKey('profile-history-list'),
              shrinkWrap: true,
              primary: false,
              itemCount: _matches.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => MatchRow(
                  key: ValueKey('profile-match-${_matches[i].matchId}'),
                  match: _matches[i]),
            )),
          ),
      ]),
    );
  }
}
