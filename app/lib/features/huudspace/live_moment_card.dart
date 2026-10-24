import 'package:flutter/material.dart';

import '../../theme/neon_theme.dart';
import '../../widgets/game_badge.dart';
import '../../widgets/huud_art.dart';
import '../../widgets/neon.dart';
import '../huud/huud_models.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';

/// Live Huuds as a wall of uneven cards, two to a row, each telling what's
/// going on in there right now. Tapping a card is the way in: it opens the
/// full-screen look-in, where you can listen first and join if you like.
class LiveMomentWall extends StatelessWidget {
  const LiveMomentWall({super.key, required this.huuds, required this.onOpen});
  final List<LiveHuud> huuds;
  final void Function(int index) onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        // Big text gets one card to a row rather than two cramped ones.
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final count = box.maxWidth / scale < 300 ? 1 : (box.maxWidth >= 720 ? 3 : 2);
        final columns = List.generate(count, (_) => <int>[]);
        final heights = List.filled(count, 0.0);
        for (var i = 0; i < huuds.length; i++) {
          var shortest = 0;
          for (var c = 1; c < count; c++) {
            if (heights[c] < heights[shortest]) shortest = c;
          }
          columns[shortest].add(i);
          heights[shortest] += LiveMomentCard.estimate(huuds[i]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var c = 0; c < count; c++) ...[
            if (c > 0) const SizedBox(width: 10),
            Expanded(
              child: Column(children: [
                for (final i in columns[c])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: LiveMomentCard(huud: huuds[i], onTap: () => onOpen(i)),
                  ),
              ]),
            ),
          ],
        ]);
      });
}

/// One Live Huud: its picture, what it's up to, and the latest few things
/// that happened in it — a move, a win, someone arriving, a chat line.
class LiveMomentCard extends StatelessWidget {
  const LiveMomentCard({super.key, required this.huud, required this.onTap});
  final LiveHuud huud;
  final VoidCallback onTap;

  static bool _tall(LiveHuud h) => h.moments.length >= 2;

  /// Roughly how tall the card draws, to keep the columns level.
  static double estimate(LiveHuud h) => (_tall(h) ? 112 : 78) + 104 + h.moments.length * 26.0;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // A step lighter than the page so the cards lift off it.
    final surface = dark ? Color.alphaBlend(n.ink.withValues(alpha: 0.035), n.panel) : n.panel;
    final meta = dark ? Color.lerp(n.mute, n.mid, 0.35)! : n.mute;
    final cup = huud.championship;
    final game = cup?.gameType ?? huud.gameType;
    final doing = cup != null
        ? cup.text
        : game == null
            ? 'Hanging out 💬'
            : switch (huud.gameStatus) {
                'playing' => 'Playing ${huudGameName(game)}',
                'waiting' => huud.findingPlayers ? '${huudGameName(game)} · Join to play' : 'Getting ready for ${huudGameName(game)}',
                _ => 'Just played ${huudGameName(game)}',
              };
    final art = game == null ? null : GameBadge.artworkFor(huudArtworkId(game));
    final backdrop = huudBackgroundAsset(huud.background);
    final count = '${huud.memberCount} in${huud.watching > 0 ? ' · ${huud.watching} watching' : ''}';
    final lead = huud.moments.firstOrNull;
    return Semantics(
      button: true,
      child: Material(
        key: ValueKey('live-huud-${huud.id}'),
        color: surface,
        elevation: dark ? 3 : 1,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: huud.youAreIn ? h.orange : n.line, width: huud.youAreIn ? 1.5 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: _tall(huud) ? 112 : 78,
              child: Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
                if (backdrop != null)
                  Image.asset(backdrop, fit: BoxFit.cover, excludeFromSemantics: true)
                else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [h.orange.withValues(alpha: dark ? 0.32 : 0.28), surface],
                      ),
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.35, 1],
                      colors: [surface.withValues(alpha: 0), surface],
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: _Pill(child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: h.live, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('LIVE', style: TextStyle(fontSize: 10, height: 1.2, fontWeight: FontWeight.w900, color: h.live)),
                  ])),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: _Pill(
                      child: Text(count,
                          style: const TextStyle(fontSize: 10, height: 1.2, fontWeight: FontWeight.w700, color: Color(0xFFF6EAE3)))),
                ),
                Positioned(
                  left: 8,
                  bottom: -14,
                  child: art != null
                      ? Image.asset(art, width: 46, height: 46, fit: BoxFit.contain, excludeFromSemantics: true)
                      : const HuudSymbol('🎉', size: 40, decorative: true),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(huud.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, height: 1.15, fontWeight: FontWeight.w900, color: n.ink)),
                if (huud.host != null)
                  Text('${huud.host!.handle} · ${huud.privacy.label}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, height: 1.3, color: meta)),
                const SizedBox(height: 3),
                HuudText(doing,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, height: 1.25, fontWeight: FontWeight.w700, color: h.orangeText)),
                if (lead != null) ...[
                  const SizedBox(height: 8),
                  _LeadMoment(lead, meta: meta),
                ],
                for (final m in huud.moments.skip(1)) ...[
                  const SizedBox(height: 6),
                  _MomentLine(m, meta: meta),
                ],
                const SizedBox(height: 9),
                Row(children: [
                  Expanded(
                    child: Wrap(spacing: 5, runSpacing: 4, children: [
                      if (huud.gamesPlayed > 0)
                        _Stat('🏆', huud.gamesPlayed, '${huud.gamesPlayed} ${huud.gamesPlayed == 1 ? 'game' : 'games'} played'),
                      if (huud.recentMessages > 0)
                        _Stat('💬', huud.recentMessages, '${huud.recentMessages} chat ${huud.recentMessages == 1 ? 'message' : 'messages'} lately'),
                    ]),
                  ),
                  HuudAvatarStack(
                      key: ValueKey('live-members-${huud.id}'),
                      people: huud.members,
                      total: huud.memberCount,
                      max: 3,
                      size: 24),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The newest thing that happened, led by whoever did it.
class _LeadMoment extends StatelessWidget {
  const _LeadMoment(this.moment, {required this.meta});
  final HuudMoment moment;
  final Color meta;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final who = moment.who;
    final at = moment.at;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (who != null)
        Avatar(who.name, size: 22, imageUrl: who.avatarUrl)
      else
        HuudSymbol(moment.symbol, size: 20, decorative: true),
      const SizedBox(width: 6),
      Expanded(
        child: Text.rich(
          TextSpan(children: [
            if (who != null)
              TextSpan(
                  text: moment.kind == 'chat' ? '${who.handle}: ' : '${who.handle} ',
                  style: TextStyle(fontWeight: FontWeight.w800, color: n.ink)),
            TextSpan(text: moment.kind == 'chat' ? '“${moment.text}”' : moment.text),
          ]),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, height: 1.3, color: n.mid),
        ),
      ),
      if (at != null) ...[
        const SizedBox(width: 4),
        Text(huudAgo(at), style: TextStyle(fontSize: 10, height: 1.4, color: meta)),
      ],
    ]);
  }
}

/// An earlier moment: a small picture, one line, how long ago.
class _MomentLine extends StatelessWidget {
  const _MomentLine(this.moment, {required this.meta});
  final HuudMoment moment;
  final Color meta;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final who = moment.who;
    final at = moment.at;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 1), child: HuudSymbol(moment.symbol, size: 16, decorative: true)),
      const SizedBox(width: 6),
      Expanded(
        child: Text.rich(
          TextSpan(children: [
            if (who != null)
              TextSpan(
                  text: moment.kind == 'chat' ? '${who.handle}: ' : '${who.handle} ',
                  style: TextStyle(fontWeight: FontWeight.w700, color: n.mid)),
            TextSpan(text: moment.kind == 'chat' ? '“${moment.text}”' : moment.text),
          ]),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, height: 1.3, color: meta),
        ),
      ),
      if (at != null) ...[
        const SizedBox(width: 4),
        Text(huudAgo(at), style: TextStyle(fontSize: 10, height: 1.4, color: meta)),
      ],
    ]);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xC716100F), borderRadius: BorderRadius.circular(999)),
        child: child,
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.symbol, this.value, this.label);
  final String symbol;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(3, 2, 7, 2),
        decoration: BoxDecoration(
            color: dark ? n.line.withValues(alpha: 0.7) : n.plate, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          HuudSymbol(symbol, size: 16, decorative: true),
          const SizedBox(width: 3),
          Text('$value', style: TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w800, color: n.ink)),
        ]),
      ),
    );
  }
}
