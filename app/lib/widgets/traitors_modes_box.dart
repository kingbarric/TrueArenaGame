import 'package:flutter/material.dart';

import '../theme/neon_theme.dart';
import 'game_badge.dart';
import 'mode_art.dart';
import 'neon.dart';

/// Traitors on a games list: one game, so one box — with its five modes
/// inside it. Tapping a mode opens that mode straight away; nobody is asked
/// "which Traitors?" a second time.
class TraitorsModesBox extends StatelessWidget {
  const TraitorsModesBox({super.key, required this.onPick, this.keyPrefix = 'traitors-mode', this.busyMode});

  /// The slug of the mode tapped. Null shows the box without taps.
  final void Function(String mode)? onPick;

  /// Each tile's key is `$keyPrefix-$slug`, so one screen's tiles can be told
  /// from another's in tests.
  final String keyPrefix;

  /// A mode being opened: its tile shows a spinner and the others wait.
  final String? busyMode;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final first = traitorsModeCards.first;
    final rest = traitorsModeCards.skip(1).toList();
    final icon = GameBadge.artworkFor('truearena');
    return Container(
      key: ValueKey('$keyPrefix-box'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: n.panel,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: n.brand.withValues(alpha: .45), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
            width: 46,
            height: 46,
            child: icon == null ? const GameBadge(gameId: 'truearena', size: 46) : Image.asset(icon, fit: BoxFit.contain),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Traitors',
                  maxLines: 1,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: n.ink, height: 1.1)),
              Text('Find the liars at the table · pick a mode',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: n.mid)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: n.brand.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)),
            child: Text('${traitorsModeCards.length} modes',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: n.brand)),
          ),
        ]),
        const SizedBox(height: 12),
        _ModeTile(mode: first, aspectRatio: 2.15, wide: true, box: this),
        const SizedBox(height: 10),
        for (var i = 0; i < rest.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _ModeTile(mode: rest[i], aspectRatio: 1.2, box: this)),
            const SizedBox(width: 10),
            Expanded(
                child: i + 1 < rest.length
                    ? _ModeTile(mode: rest[i + 1], aspectRatio: 1.2, box: this)
                    : const SizedBox.shrink()),
          ]),
        ],
      ]),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.mode, required this.aspectRatio, required this.box, this.wide = false});

  final TraitorsModeCard mode;
  final double aspectRatio;
  final TraitorsModesBox box;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final busy = box.busyMode == mode.slug;
    final onPick = box.onPick;
    final tap = onPick == null || box.busyMode != null ? null : () => onPick(mode.slug);
    final art = traitorsModeArt[mode.slug];
    const shadow = [Shadow(color: Colors.black87, blurRadius: 6)];
    return Semantics(
      button: true,
      label: 'Play Traitors: ${mode.name}, ${mode.players} players. ${mode.hook}',
      excludeSemantics: true,
      child: Bouncy(
        key: ValueKey('${box.keyPrefix}-${mode.slug}'),
        feel: BouncyFeel.wobble,
        onTap: tap,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(fit: StackFit.expand, children: [
              if (art != null) Image.asset(art, fit: BoxFit.cover) else ColoredBox(color: context.neon.plate),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x33000000), Color(0xD9000000)],
                    stops: [0, .45, 1],
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
                  child: Text('${mode.players} players',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 9,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(mode.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: wide ? 19 : 15, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1, shadows: shadow)),
                  const SizedBox(height: 2),
                  Text(mode.hook,
                      maxLines: wide ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: wide ? 13 : 11.5, color: const Color(0xFFEDE6DA), height: 1.2, shadows: shadow)),
                ]),
              ),
              if (busy)
                const ColoredBox(
                  color: Colors.black45,
                  child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
