import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/mode_art.dart';
import 'huud_kit.dart';
import 'whot_mode_sheet.dart';

/// The five built-in Traitors modes, by the slug the server keeps them under.
const traitorsModeNames = {
  'classic_conspiracy': 'Classic Conspiracy',
  'midnight_heist': 'Midnight Heist',
  'blood_moon': 'Blood Moon',
  'the_last_alibi': 'The Last Alibi',
  'final_gambit': 'Final Gambit',
};

const _traitorsModeEmoji = {
  'classic_conspiracy': '🕵️',
  'midnight_heist': '🛡️',
  'blood_moon': '🌕',
  'the_last_alibi': '⏳',
  'final_gambit': '🎯',
};

/// "Traitors · Blood Moon" — what a Huud calls its Traitors game.
String traitorsModeName(String? mode) {
  final name = traitorsModeNames[mode];
  return name == null ? 'Traitors' : 'Traitors · $name';
}

/// Before anyone sits down: which Traitors? Each mode with its table size and
/// traitor count, as the game's own mode picker shows them. Null when closed.
Future<String?> askTraitorsMode(BuildContext context) {
  final presets = AppScope.of(context).api.get('/config/presets').then((raw) => [
        for (final p in (raw as List).map((e) => ModePreset.fromJson((e as Map).cast<String, dynamic>())))
          if (p.scope == 'builtin' && p.slug != null) p
      ]);
  return showHuudSheet<String>(
    context,
    builder: (context) {
      final n = context.neon;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Which Traitors?',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: n.ink)),
            const SizedBox(height: 4),
            Text('Pick a mode, then choose who plays.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: n.mid)),
            const SizedBox(height: 16),
            FutureBuilder<List<ModePreset>>(
              future: presets,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text("Couldn't load the modes — close this and try again.",
                        textAlign: TextAlign.center, style: TextStyle(color: n.mid)),
                  );
                }
                final modes = snap.data;
                if (modes == null) {
                  return const Padding(
                      padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final p in modes) ...[
                    HuudModeCard(
                      keyPrefix: 'traitors-mode',
                      mode: p.slug!,
                      art: traitorsModeArt[p.slug],
                      emoji: _traitorsModeEmoji[p.slug] ?? '🎭',
                      title: p.name,
                      tagline: p.tag == null ? '${p.minPlayers}–${p.maxPlayers} players' : '${p.tag} · ${p.minPlayers}–${p.maxPlayers} players',
                      points: [
                        if (p.description != null) p.description!,
                        '${p.traitors} traitor${p.traitors == 1 ? '' : 's'} · ${p.veilLabel}'
                            '${p.twistCount > 0 ? ' · ${p.twistCount} twist${p.twistCount == 1 ? '' : 's'}' : ''}',
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ]);
              },
            ),
          ]),
        ),
      );
    },
  );
}
