import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../core/hangout_state.dart';
import '../theme/huud_colors.dart';
import '../theme/neon_theme.dart';
import 'neon.dart';

/// Who's in the call, as faces: whoever is talking gets a glowing orange
/// ring, and the words say it too ("Ada is talking"). Sits in the call bar
/// above every game screen, so players can see who's speaking mid-game.
class TalkingRow extends StatelessWidget {
  const TalkingRow({super.key, required this.call, this.max = 5, this.size = 30});

  final HangoutState call;
  final int max;
  final double size;

  static String said(List<String> speaking) => switch (speaking.length) {
        0 => '',
        1 => '${speaking[0]} is talking',
        2 => '${speaking[0]} and ${speaking[1]} are talking',
        _ => '${speaking[0]}, ${speaking[1]} and ${speaking.length - 2} more are talking',
      };

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final people = [...call.participants]..sort((a, b) => (b.isSpeaking ? 1 : 0) - (a.isSpeaking ? 1 : 0));
    final shown = people.take(max).toList();
    final names = [
      for (final p in people.where((p) => p.isSpeaking))
        p is lk.LocalParticipant ? 'You' : _first(p),
    ];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final p in shown)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: AnimatedContainer(
            key: ValueKey('talking-${p.identity}'),
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: p.isSpeaking ? h.orange : Colors.transparent, width: 2.5),
              boxShadow: p.isSpeaking ? [BoxShadow(color: h.orange.withValues(alpha: 0.55), blurRadius: 10)] : null,
            ),
            child: Avatar(_first(p), size: size, imageUrl: call.avatars[p.identity]),
          ),
        ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          names.isEmpty ? (people.isEmpty ? call.title : 'Voice on') : said(names),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w800, color: names.isEmpty ? n.mid : h.orangeText),
        ),
      ),
    ]);
  }

  static String _first(lk.Participant p) {
    final name = p.name.isEmpty ? p.identity : p.name;
    return name.split(' ').first;
  }
}
