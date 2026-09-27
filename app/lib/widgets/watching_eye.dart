import 'package:flutter/material.dart';

/// "People are watching this" — a softly pulsing green eye with a headcount.
///
/// Shows nothing at all when the room is empty of spectators: a zero here
/// would be a small disappointment on every screen it appeared on, and the
/// indicator only means anything when it's lit.
class WatchingEye extends StatefulWidget {
  const WatchingEye({super.key, required this.count, this.compact = false});

  final int count;

  /// Drops the word "watching" and tightens the padding, for tight rows.
  final bool compact;

  @override
  State<WatchingEye> createState() => _WatchingEyeState();
}

class _WatchingEyeState extends State<WatchingEye> with SingleTickerProviderStateMixin {
  static const _green = Color(0xff4ade80);

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count <= 0) return const SizedBox.shrink();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        // Held at its brightest for anyone who asked for less motion, so the
        // indicator still reads as "live" without breathing at them.
        final t = reduceMotion ? 1.0 : Curves.easeInOut.transform(_pulse.value);
        final glow = 0.35 + 0.45 * t;
        return Container(
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 11, vertical: widget.compact ? 4 : 6),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _green.withValues(alpha: 0.30 + 0.25 * t)),
            boxShadow: [
              BoxShadow(
                color: _green.withValues(alpha: 0.18 * glow),
                blurRadius: 12 + 8 * t,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.remove_red_eye_rounded, size: widget.compact ? 13 : 15, color: _green.withValues(alpha: glow + 0.2)),
            const SizedBox(width: 5),
            Text(
              widget.compact ? '${widget.count}' : '${widget.count} watching',
              style: TextStyle(
                color: _green,
                fontSize: widget.compact ? 11 : 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ]),
        );
      },
    );
  }
}
