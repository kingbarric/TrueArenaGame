import 'package:flutter/material.dart';

/// Whose turn it is, on the players themselves: a bold green ring and glow
/// round the player to move, amber round the one waiting. The ✋ hand
/// (see [TurnHand]) travels to whoever's up.
class TurnRing extends StatelessWidget {
  const TurnRing({super.key, required this.active, required this.child, this.size = 40});

  final bool active;
  final Widget child;

  /// The avatar's size — the ring sits just outside it.
  final double size;

  static const green = Color(0xff16a34a);
  static const amber = Color(0xfff59e0b);

  @override
  Widget build(BuildContext context) {
    final color = active ? green : amber;
    return AnimatedContainer(
      key: ValueKey(active ? 'turn-ring-active' : 'turn-ring-waiting'),
      duration: const Duration(milliseconds: 260),
      padding: EdgeInsets.all(active ? 3 : 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: active ? 3.4 : 2.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: active ? 0.75 : 0.35),
            blurRadius: active ? size * 0.45 : size * 0.18,
            spreadRadius: active ? 1.5 : 0,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// The ✋ that sits with the player to move. Shown on that player only; it
/// slides in from the direction of the other player, so it reads as the
/// hand moving across to them.
class TurnHand extends StatelessWidget {
  const TurnHand({super.key, required this.visible, this.from = const Offset(0, 0.8), this.size = 22});

  final bool visible;

  /// Where it slides in from (fractions of its own size) — towards the other player.
  final Offset from;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        offset: visible ? Offset.zero : from,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 240),
          opacity: visible ? 1 : 0,
          child: Text('✋', key: visible ? const ValueKey('turn-hand') : null, style: TextStyle(fontSize: size)),
        ),
      ),
    );
  }
}

/// Two players side by side (left and right): the ✋ glides over to
/// whichever one is up.
extension TurnHandBar on Widget {
  Widget withTurnHand({required bool left, required bool visible}) => Stack(children: [
        this,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeInOutCubic,
              alignment: Alignment(left ? -1 : 1, 0.15),
              child: Padding(
                // Tucked against the active player's picture.
                padding: const EdgeInsets.symmetric(horizontal: 62),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: visible ? 1 : 0,
                  child: const Text('✋', key: ValueKey('turn-hand'), style: TextStyle(fontSize: 24)),
                ),
              ),
            ),
          ),
        ),
      ]);
}
