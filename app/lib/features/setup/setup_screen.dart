import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../../widgets/neon_form.dart';
import '../lobby/lobby_screen.dart';
import '../onboarding/guest_gate.dart';

/// The GameConfig editor. Opened only when an admin taps "Customize" (or the Custom
/// Game card). Starts from a preset (or a plain base), edits in place, and validates
/// live against POST /api/v1/config/validate.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.basePreset});
  final ModePreset? basePreset;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late Map<String, dynamic> _config;
  late String _baseline;
  List<TwistMeta>? _twists;
  Map<String, dynamic>? _validation;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _config = _deepCopy(widget.basePreset?.config ?? _plainBase());
    _config['preset'] = widget.basePreset?.slug ?? 'custom';
    _baseline = jsonEncode(_config);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTwists();
      _validate();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _deepCopy(Map<String, dynamic> m) =>
      jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  Map<String, dynamic> _plainBase() => {
        'catalogVersion': 1,
        'preset': 'custom',
        'table': {'players': 8, 'minPlayers': 6, 'maxPlayers': 10, 'adminOverride': false, 'traitorCurve': [
          [4, 2]
        ]},
        'timers': {'night': 60, 'roundTable': 300, 'vote': 60, 'defense': 60},
        'nightKill': {'openingNight': 'on', 'doubleAfterRound': null, 'allowSkip': false, 'requireTraitorConsensus': false},
        'revealOnElimination': 'always',
        'tieBreak': 'revote',
        'secondTie': 'no_elimination',
        'suddenDeathSeconds': 30,
        'afk': 'abstain',
        'voteReveal': 'sequential',
        'endgameVeil': 'final_4',
        'twists': <String, dynamic>{},
      };

  ApiClient get _api => AppScope.of(context).api;

  Future<void> _loadTwists() async {
    try {
      final raw = await _api.get('/config/twists') as List;
      if (!mounted) return;
      setState(() => _twists = raw.map((e) => TwistMeta.fromJson((e as Map).cast<String, dynamic>())).toList());
    } catch (_) {/* twist grid just stays empty */}
  }

  void _change(VoidCallback mutate) {
    setState(mutate);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _validate);
  }

  Future<void> _validate() async {
    try {
      final res = await _api.post('/config/validate', _config);
      if (!mounted) return;
      setState(() => _validation = (res as Map).cast<String, dynamic>());
    } catch (_) {
      if (mounted) setState(() => _validation = null);
    }
  }

  // ---- config accessors ----
  Map<String, dynamic> get _table => (_config['table'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get _timers => (_config['timers'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get _night => (_config['nightKill'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get _twistMap => (_config['twists'] as Map).cast<String, dynamic>();

  int get _players => _table['players'] as int;
  int get _traitors {
    final curve = (_table['traitorCurve'] as List).cast<List>();
    var t = 1;
    for (final p in curve) {
      if (_players >= (p[0] as num)) t = (p[1] as num).toInt();
    }
    return t;
  }

  bool get _diverged => jsonEncode(_config) != _baseline;
  bool get _valid => _validation == null || (_validation!['ok'] as bool? ?? true);
  List<String> get _errors => ((_validation?['errors'] as List?) ?? const []).cast<String>();
  List<String> get _warnings => ((_validation?['warnings'] as List?) ?? const []).cast<String>();

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: Text(widget.basePreset?.name ?? 'Custom game')),
      body: SafeArea(
        child: Column(
          children: [
            const MarqueeBar('every twist is a preset toggle  •  five modes are named bundles  •  build your own'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _section('The table', [
                    FieldLabel('Players', trailing: Text('$_players',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                    NeonSlider(
                      value: _players,
                      min: 4,
                      max: 20,
                      safeLow: _table['minPlayers'] as int?,
                      safeHigh: _table['maxPlayers'] as int?,
                      onChanged: (v) => _change(() => _table['players'] = v),
                    ),
                    NeonSwitchRow(
                      label: 'Admin override (4–20)',
                      value: _table['adminOverride'] as bool? ?? false,
                      onChanged: (v) => _change(() => _table['adminOverride'] = v),
                    ),
                    const SizedBox(height: 6),
                    const FieldLabel('Traitors'),
                    const SizedBox(height: 6),
                    NeonStepper(
                      value: _traitors,
                      min: 1,
                      max: 6,
                      onChanged: (v) => _change(() => _table['traitorCurve'] = [
                            [4, v]
                          ]),
                    ),
                  ]),
                  _section('Clocks', [
                    _timerRow('Night', 'night', 30, 120, 15),
                    _timerRow('Round table', 'roundTable', 60, 600, 30),
                    _timerRow('Vote', 'vote', 30, 90, 15),
                  ]),
                  _section('The night', [
                    NeonSwitchRow(
                      label: 'Kill on the opening night',
                      value: (_night['openingNight'] as String? ?? 'on') == 'on',
                      onChanged: (v) => _change(() => _night['openingNight'] = v ? 'on' : 'off'),
                    ),
                    NeonSwitchRow(
                      label: 'Traitors may skip one kill',
                      value: _night['allowSkip'] as bool? ?? false,
                      onChanged: (v) => _change(() => _night['allowSkip'] = v),
                    ),
                    NeonSwitchRow(
                      label: 'Require Traitor consensus',
                      value: _night['requireTraitorConsensus'] as bool? ?? false,
                      onChanged: (v) => _change(() => _night['requireTraitorConsensus'] = v),
                    ),
                    const SizedBox(height: 8),
                    const FieldLabel('Double murder'),
                    const SizedBox(height: 6),
                    NeonSegmented<int>(
                      options: const [SegOption(0, 'Never'), SegOption(2, 'After R2'), SegOption(3, 'After R3')],
                      value: (_night['doubleAfterRound'] as num?)?.toInt() ?? 0,
                      onChanged: (v) => _change(() => _night['doubleAfterRound'] = v == 0 ? null : v),
                    ),
                  ]),
                  _section('Reveals', [
                    const FieldLabel('Role on elimination'),
                    const SizedBox(height: 6),
                    NeonSegmented<String>(
                      options: const [SegOption('always', 'Always'), SegOption('never', 'Never'), SegOption('alternating', 'Alternating')],
                      value: _config['revealOnElimination'] as String? ?? 'always',
                      onChanged: (v) => _change(() => _config['revealOnElimination'] = v),
                    ),
                    const SizedBox(height: 10),
                    const FieldLabel('Vote review'),
                    const SizedBox(height: 6),
                    NeonSegmented<String>(
                      options: const [SegOption('sequential', 'Sequential'), SegOption('all_at_once', 'All at once')],
                      value: _config['voteReveal'] as String? ?? 'sequential',
                      onChanged: (v) => _change(() => _config['voteReveal'] = v),
                    ),
                    const SizedBox(height: 10),
                    const FieldLabel('Veiled endgame'),
                    const SizedBox(height: 6),
                    NeonSegmented<String>(
                      options: const [
                        SegOption('final_4', 'Final 4'),
                        SegOption('final_5', 'Final 5'),
                        SegOption('final_6', 'Final 6'),
                        SegOption('off', 'Off'),
                      ],
                      value: _config['endgameVeil'] as String? ?? 'off',
                      onChanged: (v) => _change(() => _config['endgameVeil'] = v),
                    ),
                  ]),
                  _section('Ties & AFK', [
                    const FieldLabel('On a tie'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 7, runSpacing: 7, children: [
                      for (final t in const [
                        ['revote', 'Revote'],
                        ['no_elimination', 'No elimination'],
                        ['random', 'Random tied'],
                        ['sudden_death', 'Sudden death'],
                        ['host_decides', 'Host decides'],
                        ['trial_of_two', 'Trial of two'],
                      ])
                        NeonChip(
                          label: t[1],
                          selected: _config['tieBreak'] == t[0],
                          onTap: () => _change(() => _config['tieBreak'] = t[0]),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    const FieldLabel('Missed vote'),
                    const SizedBox(height: 6),
                    NeonSegmented<String>(
                      options: const [SegOption('abstain', 'Abstain'), SegOption('host_assigns', 'Host assigns')],
                      value: _config['afk'] as String? ?? 'abstain',
                      onChanged: (v) => _change(() => _config['afk'] = v),
                    ),
                  ]),
                  _twistSection(n),
                ],
              ),
            ),
            _bottomBar(n),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    final n = context.neon;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NeonCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: n.gold, letterSpacing: 2, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );
  }

  Widget _timerRow(String label, String key, int min, int max, int step) {
    final v = (_timers[key] as num).toInt();
    String fmt(int s) => s >= 60 ? '${(s / 60).toStringAsFixed(s % 60 == 0 ? 0 : 1)}m' : '${s}s';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.neon.mid))),
        NeonStepper(value: v, min: min, max: max, step: step, format: fmt,
            onChanged: (nv) => _change(() => _timers[key] = nv)),
      ]),
    );
  }

  Widget _twistSection(NeonColors n) {
    final twists = _twists;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NeonCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('TWISTS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: n.gold, letterSpacing: 2, fontWeight: FontWeight.w800)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(color: n.jade, borderRadius: BorderRadius.circular(NeonRadius.pill)),
              child: Text('${_twistMap.length} ON',
                  style: TextStyle(color: n.onAccent, fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: 1)),
            ),
          ]),
          const SizedBox(height: 12),
          if (twists == null)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
          else
            Column(
              children: [
                for (final t in twists) _TwistTile(
                  meta: t,
                  enabled: _twistMap.containsKey(t.id),
                  onToggle: () => _change(() {
                    if (_twistMap.containsKey(t.id)) {
                      _twistMap.remove(t.id);
                    } else {
                      _twistMap[t.id] = <String, dynamic>{};
                    }
                  }),
                ),
              ],
            ),
        ]),
      ),
    );
  }

  Widget _bottomBar(NeonColors n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(color: n.panel, border: Border(top: BorderSide(color: n.line))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_errors.isNotEmpty)
          _panel(n.danger, _errors.first + (_errors.length > 1 ? '  (+${_errors.length - 1} more)' : ''))
        else if (_warnings.isNotEmpty)
          _panel(n.jade, _warnings.first),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Text('$_players players · $_traitors traitors · ${_twistMap.length} twist${_twistMap.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, fontWeight: FontWeight.w700)),
          ]),
        ),
        NeonButton(
          _diverged ? 'Save & open the huud' : 'Open the huud',
          style: _diverged ? NeonStyle.danger : NeonStyle.go,
          onPressed: _valid ? _open : null,
        ),
      ]),
    );
  }

  Widget _panel(Color c, String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withValues(alpha: 0.5)),
        ),
        child: Text(text, style: TextStyle(color: context.neon.ink, fontSize: 11, height: 1.4)),
      );

  Future<void> _open() async {
    if (!await canHostOrPromptToVerify(context) || !mounted) return;
    final config = _deepCopy(_config);
    final preset = widget.basePreset ?? ModePreset(
      id: 'custom',
      scope: 'user',
      slug: 'custom',
      name: 'Custom Game',
      tag: null,
      description: null,
      config: config,
    );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LobbyScreen(preset: preset, gameConfig: config),
    ));
  }
}

class _TwistTile extends StatefulWidget {
  const _TwistTile({required this.meta, required this.enabled, required this.onToggle});
  final TwistMeta meta;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  State<_TwistTile> createState() => _TwistTileState();
}

class _TwistTileState extends State<_TwistTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: widget.enabled ? n.brand.withValues(alpha: 0.1) : n.plate,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: widget.enabled ? n.brand : kCabinetInk, width: widget.enabled ? 1.5 : 1.6),
        ),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: widget.onToggle,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(11, 11, 4, 11),
                    child: Text(widget.meta.name.toUpperCase(),
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: n.ink)),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: Icon(_open ? Icons.expand_less : Icons.info_outline, color: n.mute),
                onPressed: () => setState(() => _open = !_open),
              ),
              Switch(
                value: widget.enabled,
                onChanged: (_) => widget.onToggle(),
                activeThumbColor: n.onAccent,
                activeTrackColor: n.brand,
              ),
              const SizedBox(width: 4),
            ]),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 0, 11, 11),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(widget.meta.summary,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: n.mid, height: 1.4)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
