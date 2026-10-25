import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/nav_art.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';
import '../../widgets/huud_art.dart';

/// Owner: turn the Huud Live. Only one of your Huuds is Live at a time, so
/// with another one Live it asks first whether to end that one. Then it asks
/// who to tell — every member (pushed to their phones), only the ones online
/// now, or nobody — and goes Live. Returns the Huud as it is now, or null if
/// they backed out.
Future<HuudSpace?> goLive(BuildContext context, String huudId) async {
  final api = AppScope.of(context).api;
  MyHuud? other;
  try {
    other = await otherLiveHuud(api, except: huudId);
  } catch (_) {
    // Can't tell — the server still refuses a second Live one, and says why.
  }
  if (!context.mounted) return null;
  if (other != null && !await confirmSwitchLive(context, other)) return null;
  if (!context.mounted) return null;
  final tell = await showHuudSheet<String>(context, builder: (_) => const _GoLiveSheet());
  if (tell == null || !context.mounted) return null;
  try {
    final raw = await api.post('/huud-spaces/$huudId/live', {'notify': tell, if (other != null) 'switchLive': true});
    if (context.mounted) huudSnack(context, "You're Live! 🔴");
    return HuudSpace.fromJson((raw as Map).cast<String, dynamic>());
  } on ApiException catch (e) {
    if (context.mounted) huudSnack(context, huudRefusal(e));
  } catch (_) {
    if (context.mounted) huudSnack(context, userErrorMessage);
  }
  return null;
}

/// What to say when a Huud request is turned down. The server keeps its
/// reasons to itself and sends a code; the rules about having several Huuds
/// are said here in the app's own words, anything else is "try again".
String huudRefusal(ApiException e) => switch (e.diagnosticMessage) {
      'FINISH_GAME_FIRST' => "You're in a game in your other Huud — finish it first, then come over.",
      'ONE_LIVE_HUUD' => 'Another of your Huuds is Live — only one can be Live at a time. End it first.',
      'HUUD_LIMIT' => "You have $kMaxHuuds Huuds — that's the most. Delete one in its settings to make another.",
      _ => e.message,
    };

/// Your Huuds, from the server's list: yours only, the Live one first.
Future<List<MyHuud>> ownHuuds(ApiClient api) async {
  final raw = await api.get('/huud-spaces/mine') as List;
  return [
    for (final e in raw)
      if (MyHuud.fromJson((e as Map).cast<String, dynamic>()) case final h when h.youOwn) h,
  ]..sort((a, b) => (b.live ? 1 : 0) - (a.live ? 1 : 0));
}

/// Your other Huud that's Live, if one is — only one of yours can be.
Future<MyHuud?> otherLiveHuud(ApiClient api, {String? except}) async =>
    (await ownHuuds(api)).where((h) => h.live && h.id != except).firstOrNull;

/// Before ending [other]'s Live to go Live somewhere else.
Future<bool> confirmSwitchLive(BuildContext context, MyHuud other, {String yes = 'End it and go Live here'}) =>
    confirmHuud(context,
        emoji: '📡',
        title: 'One Live at a time',
        message: '${other.name} is Live right now. Only one of your Huuds can be Live — end it and go Live here?',
        yes: yes);

const _choices = [
  ('all', '📣', 'Tell all members', "Everyone gets a notification (unless they've muted this Huud)"),
  ('online', '🟢', 'Only people online now', 'Just members who have PlayHuud open'),
  ('none', '🤫', "Don't tell anyone", 'Go Live quietly'),
];

class _GoLiveSheet extends StatefulWidget {
  const _GoLiveSheet();

  @override
  State<_GoLiveSheet> createState() => _GoLiveSheetState();
}

class _GoLiveSheetState extends State<_GoLiveSheet> {
  String _tell = 'all';

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Center(child: NavArt('live', active: true, size: 56)),
          const SizedBox(height: 6),
          Text('Go Live',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: n.ink)),
          const SizedBox(height: 4),
          Text('Your people can come in, talk and play',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: n.mid)),
          const SizedBox(height: 18),
          Text('Who should we tell?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: n.ink)),
          const SizedBox(height: 8),
          for (final (wire, emoji, title, line) in _choices) ...[
            Semantics(
              button: true,
              selected: _tell == wire,
              label: title,
              excludeSemantics: true,
              child: GestureDetector(
                key: ValueKey('golive-$wire'),
                onTap: () => setState(() => _tell = wire),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _tell == wire ? h.orangeSoft : n.panel,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _tell == wire ? h.orange : n.line, width: _tell == wire ? 2.4 : 1.4),
                  ),
                  child: Row(children: [
                    HuudText(emoji, style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: n.ink)),
                        Text(line, style: TextStyle(fontSize: 13.5, color: n.mid)),
                      ]),
                    ),
                    Icon(_tell == wire ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: _tell == wire ? h.orangeText : n.mute),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          HuudButton(
            key: const ValueKey('golive-confirm'),
            label: 'Go Live',
            icon: Icons.sensors_rounded,
            big: true,
            expand: true,
            onPressed: () => Navigator.of(context).pop(_tell),
          ),
        ]),
      ),
    );
  }
}
