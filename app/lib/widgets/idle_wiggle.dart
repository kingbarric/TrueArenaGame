import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Every so often, at a random moment, gives its child a small shake — a
/// toy on a shelf catching your eye, not a notification demanding it.
///
/// Each instance keeps its own random rhythm, so a grid of them never
/// shakes in step. Stays still when the device asks for reduced motion.
class IdleWiggle extends StatefulWidget {
  const IdleWiggle({
    super.key,
    required this.child,
    this.minGap = const Duration(seconds: 4),
    this.maxGap = const Duration(seconds: 11),
  });

  final Widget child;
  final Duration minGap;
  final Duration maxGap;

  @override
  State<IdleWiggle> createState() => _IdleWiggleState();
}

class _IdleWiggleState extends State<IdleWiggle>
    with SingleTickerProviderStateMixin {
  static final _random = math.Random();

  late final AnimationController _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 750));
  Timer? _next;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final span = widget.maxGap.inMilliseconds - widget.minGap.inMilliseconds;
    final wait = widget.minGap.inMilliseconds + _random.nextInt(math.max(1, span));
    _next = Timer(Duration(milliseconds: wait), () async {
      if (!mounted) return;
      if (!MediaQuery.of(context).disableAnimations) {
        await _shake.forward(from: 0).orCancel.catchError((_) {});
      }
      if (mounted) _schedule();
    });
  }

  @override
  void dispose() {
    _next?.cancel();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shake,
      child: widget.child,
      builder: (context, child) {
        final t = _shake.value;
        if (t == 0 || t == 1) return child!;
        // Three quick swings that die away: about 6° at most, plus a
        // tiny lift so it reads as a jiggle rather than a spin.
        final decay = 1 - t;
        final angle = math.sin(t * math.pi * 6) * 0.1 * decay;
        final lift = math.sin(t * math.pi) * 0.04;
        return Transform.rotate(
          angle: angle,
          child: Transform.scale(scale: 1 + lift, child: child),
        );
      },
    );
  }
}
