import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';

/// Presets-first: the five modes launch as-is. "Customize" (an admin choice) opens the
/// full GameConfig editor — a later screen; here it's a stub target.
class ModeSelectScreen extends StatefulWidget {
  const ModeSelectScreen({super.key});

  @override
  State<ModeSelectScreen> createState() => _ModeSelectScreenState();
}

class _ModeSelectScreenState extends State<ModeSelectScreen> {
  List<ModePreset>? _presets;
  String? _error;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final api = AppScope.of(context).api;
    try {
      final raw = await api.get('/config/presets') as List;
      final presets = raw.map((e) => ModePreset.fromJson((e as Map).cast<String, dynamic>())).toList();
      // "Default"-tagged first, then the rest.
      presets.sort((a, b) => (b.tag == 'Default' ? 1 : 0).compareTo(a.tag == 'Default' ? 1 : 0));
      if (!mounted) return;
      setState(() {
        _presets = presets;
        _selectedId = presets.isNotEmpty ? presets.first.id : null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server');
    }
  }

  ModePreset? get _selected {
    for (final p in _presets ?? const <ModePreset>[]) {
      if (p.id == _selectedId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a mode')),
      body: SafeArea(
        child: Column(
          children: [
            const MarqueeBar('pick a mode  •  or build a custom game  •  five are launch-ready'),
            Expanded(child: _body(n)),
            if (_selected != null) _launchBar(_selected!),
          ],
        ),
      ),
    );
  }

  Widget _body(NeonColors n) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: n.danger)),
            const SizedBox(height: 12),
            NeonButton('Retry', style: NeonStyle.ghost, expand: false, onPressed: () {
              setState(() => _error = null);
              _load();
            }),
          ]),
        ),
      );
    }
    if (_presets == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      children: [
        for (final p in _presets!) _card(p),
        _customCard(n),
      ],
    );
  }

  Widget _card(ModePreset p) {
    final n = context.neon;
    final selected = p.id == _selectedId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: NeonCard(
        selected: selected,
        onTap: () => setState(() => _selectedId = p.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (p.tag != null) _pill(p.tag!, n.acid, n.onAccent),
                const Spacer(),
                if (selected) Icon(Icons.check_circle, color: n.cyan, size: 18),
              ],
            ),
            if (p.tag != null) const SizedBox(height: 8),
            Text(p.name, style: Theme.of(context).textTheme.titleMedium),
            if (p.description != null) ...[
              const SizedBox(height: 4),
              Text(p.description!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: n.mid)),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _stat('${p.minPlayers}–${p.maxPlayers} players', n.cyan),
              _stat('${p.traitors} traitors', n.magenta),
              _stat(p.veilLabel, n.acid),
              if (p.twistCount > 0) _stat('${p.twistCount} twist${p.twistCount == 1 ? '' : 's'}', n.mid),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _customCard(NeonColors n) => NeonCard(
        accent: n.acid,
        onTap: () => _customize(null),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Custom Game', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Start from scratch and pick your own twists.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: n.mid)),
        ]),
      );

  Widget _launchBar(ModePreset p) {
    final n = context.neon;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(color: n.panel, border: Border(top: BorderSide(color: n.line))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NeonButton('Open the room', onPressed: () => _openRoom(p)),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => _customize(p),
            child: Text('Customize setup →',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: n.cyan, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  void _openRoom(ModePreset p) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('“${p.name}” room — the lobby screen lands next (Phase 4).')),
    );
  }

  void _customize(ModePreset? from) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Setup editor for ${from?.name ?? 'a custom game'} — next screen.')),
    );
  }

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
        child: Text(text.toUpperCase(),
            style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 8, letterSpacing: 1.2)),
      );

  Widget _stat(String text, Color edge) {
    final n = context.neon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: n.plate,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Color.alphaBlend(edge.withOpacity(0.55), n.line)),
      ),
      child: Text(text.toUpperCase(),
          style: TextStyle(color: n.mid, fontWeight: FontWeight.w800, fontSize: 8, letterSpacing: 0.6)),
    );
  }
}
