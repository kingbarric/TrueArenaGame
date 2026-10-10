import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import 'slay_assets.dart';

/// SlayHuud's game kit: PlayHuud's cabinet look (ink outline, hard shadow,
/// springy presses) dressed in a little glam — sparkles, stage colours and
/// rewards that pop.

/// The colours and icon each career stage wears everywhere it appears.
class SlayStageLook {
  const SlayStageLook(this.from, this.to, this.icon, this.ink);
  final Color from, to, ink;
  final IconData icon;

  LinearGradient get gradient => LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [from, to]);

  static SlayStageLook of(String? location) => switch (location) {
        'lagos' => const SlayStageLook(Color(0xFF2F8F86), Color(0xFFE08A5B),
            Icons.location_city_rounded, Colors.white),
        'sunset' => const SlayStageLook(Color(0xFF3A1E5C), Color(0xFFFF4FA3),
            Icons.nightlife_rounded, Colors.white),
        'royal' => const SlayStageLook(Color(0xFF6E1F33), Color(0xFFD9A441),
            Icons.diamond_rounded, Colors.white),
        'runway' => const SlayStageLook(Color(0xFF15151B), Color(0xFF8F7BFF),
            Icons.camera_rounded, Colors.white),
        _ => const SlayStageLook(Color(0xFFF2A7BC), Color(0xFFFFD27A),
            Icons.checkroom_rounded, kCabinetInk),
      };
}

/// A chunky arcade card: ink outline, hard drop shadow, and a springy press.
class SlayCabinet extends StatelessWidget {
  const SlayCabinet(
      {super.key,
      required this.child,
      this.onTap,
      this.colour,
      this.gradient,
      this.padding = const EdgeInsets.all(16),
      this.radius = 24,
      this.feel = BouncyFeel.wobble,
      this.semanticLabel});
  final Widget child;
  final VoidCallback? onTap;
  final Color? colour;
  final Gradient? gradient;
  final EdgeInsets padding;
  final double radius;
  final BouncyFeel feel;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (colour ?? context.neon.panel) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: kCabinetInk, width: 2.5),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 0, offset: Offset(3, 4))
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Semantics(
        button: true,
        label: semanticLabel,
        child: Bouncy(feel: feel, onTap: onTap, child: card));
  }
}

/// Stars that pop in one after another with a little overshoot.
class SlayStars extends StatelessWidget {
  const SlayStars(this.count,
      {super.key, this.of = 5, this.size = 22, this.animate = false});
  final int count, of;
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final still = !animate || MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: '$count of $of stars',
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (int i = 0; i < of; i++)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: still ? 1 : 0, end: 1),
              duration: Duration(milliseconds: still ? 0 : 420 + i * 160),
              curve: Interval(still ? 0 : i / (of + 1), 1,
                  curve: Curves.elasticOut),
              builder: (_, t, child) =>
                  Transform.scale(scale: t.clamp(0, 1.4), child: child),
              child: Icon(
                  i < count ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size,
                  color: i < count ? n.gold : n.mute.withValues(alpha: .5)),
            ),
        ]),
      ),
    );
  }
}

/// A fat, rounded progress bar that fills with a springy sweep.
class SlayXpBar extends StatelessWidget {
  const SlayXpBar(
      {super.key, required this.value, this.height = 16, this.colour});
  final double value;
  final double height;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final n = context.neon, fill = colour ?? n.gold;
    return Semantics(
      value: '${(value.clamp(0, 1) * 100).round()} percent',
      child: Container(
        height: height,
        decoration: BoxDecoration(
            color: n.plate,
            borderRadius: BorderRadius.circular(height),
            border: Border.all(color: kCabinetInk, width: 2)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0, 1)),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 900),
            curve: Curves.easeOutBack,
            builder: (_, t, __) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: t.clamp(0, 1),
              child: Container(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color.lerp(fill, Colors.white, .35)!, fill])),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small pill for a number that matters: coins, XP, streak, rank.
class SlayStatChip extends StatelessWidget {
  const SlayStatChip(
      {super.key, required this.icon, required this.label, this.colour});
  final IconData icon;
  final String label;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final n = context.neon, tint = colour ?? n.gold;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 11, 5),
      decoration: BoxDecoration(
        color: n.panel,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: kCabinetInk, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 0, offset: Offset(2, 2))
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: tint),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w900, color: n.ink)),
        ),
      ]),
    );
  }
}

/// The player's career character, in a ringed bubble.
class SlayCharacterBubble extends StatelessWidget {
  const SlayCharacterBubble(
      {super.key, this.thumbnail, this.body, this.size = 64, this.ring});
  final String? thumbnail, body;
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final image =
        thumbnail == null ? null : SlayAssets.instance.thumbnail(thumbnail!);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SlayStageLook.of('studio').gradient,
        border: Border.all(color: kCabinetInk, width: 2.5),
        boxShadow: [
          BoxShadow(
              color: (ring ?? n.gold).withValues(alpha: .55), blurRadius: 14)
        ],
      ),
      child: ClipOval(
        child: image != null
            ? Image(
                image: image, fit: BoxFit.cover, alignment: Alignment.topCenter)
            : Icon(body == 'male' ? Icons.face_6_rounded : Icons.face_3_rounded,
                size: size * .62, color: kCabinetInk),
      ),
    );
  }
}

/// Live "ends in" text for daily and timed events.
class SlayCountdown extends StatefulWidget {
  const SlayCountdown(this.endsAt, {super.key, this.style});
  final DateTime endsAt;
  final TextStyle? style;
  @override
  State<SlayCountdown> createState() => _SlayCountdownState();
}

class _SlayCountdownState extends State<SlayCountdown> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.endsAt.difference(DateTime.now());
    final text = left.isNegative
        ? 'New one soon'
        : left.inHours > 0
            ? '${left.inHours}h ${left.inMinutes % 60}m left'
            : '${left.inMinutes}m left';
    return Text(text, style: widget.style);
  }
}

/// Soft twinkling sparkles behind a screen. Still when motion is reduced.
class SlaySparkles extends StatefulWidget {
  const SlaySparkles({super.key, this.colour, this.count = 26});
  final Color? colour;
  final int count;
  @override
  State<SlaySparkles> createState() => _SlaySparklesState();
}

class _SlaySparklesState extends State<SlaySparkles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _SparklePainter(
                _clock, widget.colour ?? context.neon.gold, widget.count),
            size: Size.infinite,
          ),
        ),
      );
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.clock, this.colour, this.count) : super(repaint: clock);
  final Animation<double> clock;
  final Color colour;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(7);
    for (int i = 0; i < count; i++) {
      final x = random.nextDouble() * size.width,
          y = random.nextDouble() * size.height,
          phase = random.nextDouble(),
          r = 1.5 + random.nextDouble() * 3;
      final glow = (math.sin((clock.value + phase) * math.pi * 2) + 1) / 2;
      final paint = Paint()..color = colour.withValues(alpha: .08 + .32 * glow);
      // A four-point twinkle: two thin diamonds crossed.
      final s = r * (0.7 + glow * .6);
      final path = Path()
        ..moveTo(x, y - s * 2)
        ..lineTo(x + s * .45, y)
        ..lineTo(x, y + s * 2)
        ..lineTo(x - s * .45, y)
        ..close()
        ..moveTo(x - s * 2, y)
        ..lineTo(x, y + s * .45)
        ..lineTo(x + s * 2, y)
        ..lineTo(x, y - s * .45)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) =>
      old.colour != colour || old.count != count;
}

/// Big chunky headline in PlayHuud's display face.
class SlayHeadline extends StatelessWidget {
  const SlayHeadline(this.text, {super.key, this.size = 26, this.colour});
  final String text;
  final double size;
  final Color? colour;
  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context).textTheme.displaySmall?.copyWith(
          fontSize: size,
          height: 1.05,
          fontWeight: FontWeight.w900,
          color: colour ?? context.neon.ink));
}

/// Emoji for wardrobe categories, used on briefs and rewards.
const slayCategoryEmoji = {
  'outfit': '👗',
  'dress': '👗',
  'tops': '👚',
  'shirts': '👕',
  'trousers': '👖',
  'skirts': '🩱',
  'shoes': '👠',
  'watches': '⌚',
  'bags': '👜',
  'jewellery': '💍',
  'accessories': '✨',
  'makeup': '💄',
  'hair': '💇',
  'eyes': '👁️',
};

String slayCategoryName(String category) => switch (category) {
      'outfit' => 'A full outfit',
      'jewellery' => 'Jewellery',
      'watches' => 'A watch',
      'bags' => 'A bag',
      'shoes' => 'Shoes',
      _ => category[0].toUpperCase() + category.substring(1),
    };

/// A gentle repeating hop that says "tap me".
class IdleBounce extends StatefulWidget {
  const IdleBounce({super.key, required this.child});
  final Widget child;
  @override
  State<IdleBounce> createState() => _IdleBounceState();
}

class _IdleBounceState extends State<IdleBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _c.value < .3 ? math.sin(_c.value / .3 * math.pi) : 0.0;
        return Transform.translate(offset: Offset(0, -5 * t), child: child);
      },
      child: widget.child);
}
