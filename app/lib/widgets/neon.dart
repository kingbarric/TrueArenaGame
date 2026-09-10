import 'package:flutter/material.dart';

import '../theme/neon_theme.dart';

enum NeonStyle { go, cyan, danger, ghost }

/// A chunky Night-Market action button. `go` = acid→cyan (positive), `cyan` = primary,
/// `danger` = magenta→red, `ghost` = outline only.
class NeonButton extends StatelessWidget {
  const NeonButton(this.label, {super.key, required this.onPressed, this.style = NeonStyle.go, this.expand = true});

  final String label;
  final VoidCallback? onPressed;
  final NeonStyle style;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final (Gradient? grad, Color fg, Color? border) = switch (style) {
      NeonStyle.go => (LinearGradient(colors: [n.acid, n.cyan]), n.onAccent, null),
      NeonStyle.cyan => (LinearGradient(colors: [n.cyan, n.cyan]), n.onAccent, null),
      NeonStyle.danger => (LinearGradient(colors: [n.magenta, n.danger]), Colors.white, null),
      NeonStyle.ghost => (null, n.cyan, n.cyan),
    };
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              gradient: grad,
              borderRadius: BorderRadius.circular(14),
              border: border == null ? null : Border.all(color: border, width: 1.5),
            ),
            child: Container(
              width: expand ? double.infinity : null,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Text(
                label.toUpperCase(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg, letterSpacing: 1.2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NeonCard extends StatelessWidget {
  const NeonCard({super.key, required this.child, this.onTap, this.accent, this.selected = false, this.dashed = false, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final Color? accent;
  final bool selected;
  final bool dashed;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final edge = selected ? (accent ?? n.cyan) : n.line;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: n.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: edge, width: selected ? 1.5 : 1),
        boxShadow: selected
            ? [BoxShadow(color: (accent ?? n.cyan).withValues(alpha: 0.35), blurRadius: 22, spreadRadius: -6)]
            : null,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: card),
    );
  }
}

/// A softly scrolling marquee strip — the theme's signature. Static under reduced motion.
class MarqueeBar extends StatefulWidget {
  const MarqueeBar(this.text, {super.key});
  final String text;

  @override
  State<MarqueeBar> createState() => _MarqueeBarState();
}

class _MarqueeBarState extends State<MarqueeBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final line = '${widget.text}    •    ';
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: n.acid,
          letterSpacing: 3,
          fontWeight: FontWeight.w700,
        );
    return Container(
      height: 30,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: n.line))),
      child: ClipRect(
        child: reduce
            ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(line, style: style))
            : AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final w = MediaQuery.sizeOf(context).width;
                  final dx = -_c.value * w;
                  return Stack(children: [
                    Positioned(left: dx, child: Text(line * 6, maxLines: 1, style: style)),
                    Positioned(left: dx + w * 6, child: Text(line * 6, maxLines: 1, style: style)),
                  ]);
                },
              ),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 28, this.color});
  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color ?? n.plate, shape: BoxShape.circle),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.42, color: n.ink),
      ),
    );
  }
}
