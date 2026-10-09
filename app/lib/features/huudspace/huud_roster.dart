import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';

/// Who's playing the Huud's game: everyone in the Huud, and any Cyber Agents.
/// The host taps people to sit them down or let them watch (up to the seats);
/// players show whether they're ready. The only button is Add Cyber Agent.
///
/// Used on the Huud's Play card and in the game's lobby — [seated] is the
/// table as that screen knows it (the lobby's live snapshot, or the Huud view).
class HuudRoster extends StatefulWidget {
  const HuudRoster({
    super.key,
    required this.huud,
    required this.roomId,
    required this.seated,
    required this.seats,
    this.onChanged,
  });

  final HuudSpace huud;
  final String roomId;
  final List<HuudSeat> seated;
  final int seats;

  /// After a change, so the parent can refresh (the lobby also hears it on its socket).
  final VoidCallback? onChanged;

  @override
  State<HuudRoster> createState() => _HuudRosterState();
}

class _HuudRosterState extends State<HuudRoster> {
  String? _busy;

  String? get _me => AppScope.of(context).user?.id;

  Future<void> _run(String what, Future<dynamic> Function(ApiClient api) call, {String? say}) async {
    if (_busy != null) return;
    setState(() => _busy = what);
    try {
      await call(AppScope.of(context).api);
      if (mounted && say != null) huudSnack(context, say);
      widget.onChanged?.call();
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, "That didn't work — check your internet and try again.");
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Seat someone or let them watch. No banner — the list itself changes,
  /// and a banner would sit right over Start game.
  Future<void> _toggle(HuudMember person, bool seated) async {
    if (seated) {
      await _run(
          'p-${person.userId}', (api) => api.delete('/huud-spaces/${widget.huud.id}/game/players/${person.userId}'));
      return;
    }
    if (widget.seated.length >= widget.seats) {
      huudSnack(context, 'Every seat is taken — tap a player to free one');
      return;
    }
    await _run(
        'p-${person.userId}',
        (api) => api.post('/huud-spaces/${widget.huud.id}/game/players', {
              'userIds': [person.userId]
            }));
  }

  Future<void> _removeAgent(HuudSeat bot) async {
    final ok = await confirmHuud(context,
        emoji: '🤖',
        title: 'Remove ${bot.handle}?',
        message: 'Their seat becomes free.',
        yes: 'Remove',
        danger: true);
    if (!ok || !mounted) return;
    await _run('p-${bot.userId}', (api) => api.delete('/rooms/${widget.roomId}/bots/${bot.userId}'));
  }

  /// One tap, one agent: named Cyber 1, Cyber 2… at medium — no questions, no banner.
  Future<void> _addAgent() async {
    final bots = widget.seated.where((s) => s.bot).length;
    await _run('agent',
        (api) => api.post('/rooms/${widget.roomId}/bots', {'name': 'Cyber ${bots + 1}', 'difficulty': 'medium'}));
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final host = widget.huud.youAreHost;
    final hostId = widget.huud.host?.userId;
    final seatedIds = {for (final s in widget.seated) s.userId: s};
    final people = [...widget.huud.members]
      ..sort((a, b) => (seatedIds.containsKey(b.userId) ? 1 : 0) - (seatedIds.containsKey(a.userId) ? 1 : 0));
    final bots = widget.seated.where((s) => s.bot).toList();
    final full = widget.seated.length >= widget.seats;

    Widget row({
      required Key key,
      required Widget face,
      required String name,
      required String status,
      required Color statusColor,
      required bool playing,
      VoidCallback? onTap,
      bool busy = false,
    }) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(
            button: onTap != null,
            label: '$name, $status',
            excludeSemantics: true,
            child: GestureDetector(
              key: key,
              onTap: busy ? null : onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: playing ? h.orangeSoft : n.plate,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: playing ? h.orange : n.line, width: playing ? 2 : 1.2),
                ),
                child: Row(children: [
                  face,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: n.ink)),
                  ),
                  Text(status, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: statusColor)),
                  if (onTap != null) ...[
                    const SizedBox(width: 6),
                    busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(playing ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                            size: 24, color: playing ? h.orangeText : n.mute),
                  ],
                ]),
              ),
            ),
          ),
        );

    String seatStatus(HuudSeat seat) =>
        seat.ready ? '✅ Ready' : (seat.userId == hostId ? '👑 Host' : '⏳ Not ready yet');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text('Who\'s playing?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: n.ink)),
        ),
        HuudChip('${widget.seated.length} / ${widget.seats} playing', emoji: '🎮', color: h.orangeText),
      ]),
      const SizedBox(height: 4),
      Text(
          host
              ? 'Tap people to choose who plays. Everyone else watches and chats.'
              : 'The host picks who plays. Everyone else watches and chats.',
          style: TextStyle(fontSize: 14, color: n.mid)),
      const SizedBox(height: 12),
      for (final p in people)
        Builder(builder: (context) {
          final seat = seatedIds[p.userId];
          final playing = seat != null;
          final canToggle = host && p.userId != hostId && (playing || !full);
          return row(
            key: ValueKey('roster-${p.userId}'),
            face: Avatar(p.name, size: 36, imageUrl: p.avatarUrl),
            name: p.userId == _me ? 'You' : p.handle,
            status: playing ? seatStatus(seat) : '👀 Watching',
            statusColor: playing ? (seat.ready ? h.live : n.mid) : n.mute,
            playing: playing,
            onTap: canToggle ? () => _toggle(p, playing) : null,
            busy: _busy == 'p-${p.userId}',
          );
        }),
      for (final b in bots)
        row(
          key: ValueKey('roster-${b.userId}'),
          face: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: h.orangeSoft, shape: BoxShape.circle),
            child: const Text('🤖', style: TextStyle(fontSize: 20)),
          ),
          name: '${b.handle} (Cyber Agent)',
          status: '✅ Ready',
          statusColor: h.live,
          playing: true,
          onTap: host ? () => _removeAgent(b) : null,
          busy: _busy == 'p-${b.userId}',
        ),
      if (host && !full)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: HuudButton(
            key: const ValueKey('roster-add-agent'),
            label: 'Add Cyber Agent',
            icon: Icons.smart_toy_rounded,
            kind: HuudButtonKind.soft,
            expand: true,
            busy: _busy == 'agent',
            onPressed: _addAgent,
          ),
        ),
    ]);
  }
}
