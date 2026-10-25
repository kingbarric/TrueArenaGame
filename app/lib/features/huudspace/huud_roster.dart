import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../../widgets/cyber_agent_difficulty.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';
import '../../widgets/huud_art.dart';

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
    this.tell = false,
    this.onChanged,
  });

  /// Whot's The Tell: pairs of people only, so no Cyber Agents.
  final bool tell;

  final HuudSpace huud;
  final String roomId;
  final List<HuudSeat> seated;
  final int seats;

  /// After a change, so the parent can refresh (the lobby also hears it on its socket).
  final Future<void> Function()? onChanged;

  @override
  State<HuudRoster> createState() => _HuudRosterState();
}

class _HuudRosterState extends State<HuudRoster> {
  String? _busy;
  final Map<String, HuudSeat> _addedAgents = {};
  List<HuudSeat> get _seated => [
        ...widget.seated,
        ..._addedAgents.values.where(
            (agent) => !widget.seated.any((s) => s.userId == agent.userId)),
      ];
  @override
  void didUpdateWidget(covariant HuudRoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _addedAgents.clear();
    } else {
      _addedAgents
          .removeWhere((id, _) => widget.seated.any((s) => s.userId == id));
    }
  }
  String _agentDifficulty = 'medium';

  String? get _me => AppScope.of(context).user?.id;

  Future<void> _run(String what, Future<dynamic> Function(ApiClient api) call,
      {String? say}) async {
    if (_busy != null) return;
    setState(() => _busy = what);
    try {
      await call(AppScope.of(context).api);
      if (mounted && say != null) huudSnack(context, say);
      if (mounted) await widget.onChanged?.call();
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, userErrorMessage);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Seat someone or let them watch. No banner — the list itself changes,
  /// and a banner would sit right over Start game.
  Future<void> _toggle(HuudMember person, bool seated) async {
    if (seated) {
      await _run(
          'p-${person.userId}',
          (api) => api.delete(
              '/huud-spaces/${widget.huud.id}/game/players/${person.userId}'));
      return;
    }
    if (_seated.length >= widget.seats) {
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
    await _run('p-${bot.userId}', (api) async {
      await api.delete('/rooms/${widget.roomId}/bots/${bot.userId}');
      _addedAgents.remove(bot.userId);
    });
  }

  /// One tap seats an agent at the selected level, without opening another sheet.
  Future<void> _addAgent() async {
    if (_seated.length >= widget.seats) return;
    final bots = _seated.where((s) => s.bot).length;
    final roomId = widget.roomId;
    await _run('agent', (api) async {
      final raw = await api.post('/rooms/$roomId/bots',
          {'name': 'Cyber ${bots + 1}', 'difficulty': _agentDifficulty});
      // Show the confirmed seat even if the lobby socket is delayed.
      if (mounted &&
          widget.roomId == roomId &&
          raw is Map &&
          raw['userId'] != null) {
        final agent = HuudSeat(
            userId: raw['userId'].toString(),
            name: raw['displayName'] as String? ?? 'Cyber ${bots + 1}',
            bot: true);
        setState(() => _addedAgents[agent.userId] = agent);
      }
    });
  }

  Future<void> _findPlayers() async {
    if (_busy != null) return;
    if (!widget.huud.findingPlayers &&
        widget.huud.privacy != HuudPrivacy.public) {
      final ok = await confirmHuud(context,
          emoji: '🌍',
          title: 'Invite players publicly?',
          message:
              'A preview of your Huud and game will appear in Live Now and the feed. You approve who joins to play. Your Huud stays ${widget.huud.privacy.label.toLowerCase()}.',
          yes: 'Find players');
      if (!ok || !mounted) return;
    }
    await _run(
        'find-players',
        (api) => widget.huud.findingPlayers
            ? api.delete('/huud-spaces/${widget.huud.id}/public-invite')
            : api.post('/huud-spaces/${widget.huud.id}/public-invite'),
        say: widget.huud.findingPlayers
            ? 'Invitation closed'
            : 'Invitation posted in Live Now and the feed');
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final monopoly = widget.huud.currentGame?.gameType == 'monopoly';
    final host = widget.huud.youAreHost;
    final hostId = widget.huud.host?.userId;
    final seatedIds = {for (final s in _seated) s.userId: s};
    final people = [...widget.huud.members]..sort((a, b) {
        final presence = (b.here ? 1 : 0) - (a.here ? 1 : 0);
        if (presence != 0) return presence;
        final seated = (seatedIds.containsKey(b.userId) ? 1 : 0) -
            (seatedIds.containsKey(a.userId) ? 1 : 0);
        return seated != 0
            ? seated
            : a.handle.toLowerCase().compareTo(b.handle.toLowerCase());
      });
    final bots = _seated.where((s) => s.bot).toList();
    final full = _seated.length >= widget.seats;

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
          padding: const EdgeInsets.only(bottom: 4),
          child: Semantics(
            button: onTap != null,
            label: '$name, $status',
            excludeSemantics: true,
            child: GestureDetector(
              key: key,
              onTap: busy ? null : onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                decoration: BoxDecoration(
                  color: playing ? h.orangeSoft : n.plate,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: playing ? h.orange : n.line,
                      width: playing ? 2 : 1.2),
                ),
                child: Row(children: [
                  face,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: n.ink)),
                  ),
                  HuudText(status,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: statusColor)),
                  if (onTap != null) ...[
                    const SizedBox(width: 6),
                    busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(
                            playing
                                ? Icons.check_circle_rounded
                                : Icons.add_circle_outline_rounded,
                            size: 24,
                            color: playing ? h.orangeText : n.mute),
                  ],
                ]),
              ),
            ),
          ),
        );

    String seatStatus(HuudSeat seat) =>
        seat.userId == hostId ? '👑 Host' : '🎮 Playing';

    Widget personRow(HuudMember p) {
      final seat = seatedIds[p.userId];
      final playing = seat != null;
      final canToggle =
          host && (p.userId != hostId || monopoly) && (playing || !full);
      return row(
        key: ValueKey('roster-${p.userId}'),
        face: Avatar(p.name, size: 32, imageUrl: p.avatarUrl),
        name: p.userId == _me ? 'You' : p.handle,
        // Not playing: in the Huud right now, or not.
        status: playing ? seatStatus(seat) : (p.here ? '🟢 Active' : '🌙 Away'),
        statusColor: playing ? h.orangeText : (p.here ? h.live : n.mute),
        playing: playing,
        onTap: canToggle ? () => _toggle(p, playing) : null,
        busy: _busy == 'p-${p.userId}',
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text('Who\'s playing?',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: n.ink)),
        ),
        HuudChip('${_seated.length} / ${widget.seats} playing',
            emoji: '🎮', color: h.orangeText),
      ]),
      const SizedBox(height: 4),
      Text(
          host
              ? 'Tap people to choose who plays. Everyone else watches and chats.'
              : 'The host picks who plays. Everyone else watches and chats.',
          style: TextStyle(fontSize: 14, color: n.mid)),
      if (widget.tell) ...[
        const SizedBox(height: 8),
        Container(
          key: const ValueKey('roster-tell-note'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
              color: h.orangeSoft, borderRadius: BorderRadius.circular(14)),
          child: HuudText(
              '🤫 The Tell · teams of two · 4, 6 or 8 players · people only',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: h.orangeText)),
        ),
      ],
      const SizedBox(height: 12),
      for (final p in people.where((p) => p.here)) personRow(p),
      for (final b in bots)
        row(
          key: ValueKey('roster-${b.userId}'),
          face: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: h.orangeSoft, shape: BoxShape.circle),
            child: const HuudText('🤖', style: TextStyle(fontSize: 20)),
          ),
          name: '${b.handle} (Cyber Agent)',
          status: '🎮 Playing',
          statusColor: h.live,
          playing: true,
          onTap: host ? () => _removeAgent(b) : null,
          busy: _busy == 'p-${b.userId}',
        ),
      if (host && !full && !widget.tell) ...[
        const SizedBox(height: 8),
        Text('BOT LEVEL',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: n.mute)),
        const SizedBox(height: 8),
        CyberAgentDifficulty(
          value: _agentDifficulty,
          onChanged: _busy == null ? (value) => setState(() => _agentDifficulty = value) : null,
        ),
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
      ],
      if (host && (!full || widget.huud.findingPlayers))
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('roster-find-players'),
              onPressed: _busy == null ? _findPlayers : null,
              icon: Icon(
                  widget.huud.findingPlayers
                      ? Icons.close_rounded
                      : Icons.public_rounded,
                  size: 18),
              label: Text(widget.huud.findingPlayers
                  ? 'Stop invitation'
                  : 'Find players'),
            )),
      for (final p in people.where((p) => !p.here)) personRow(p),
    ]);
  }
}
