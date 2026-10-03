import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/neon_theme.dart';

enum NeonStyle { go, gold, danger, ghost }

/// How a shape behaves when you press it. Everything used to share one
/// symmetric 130ms ease, which made a tiny chip and a big game tile feel
/// identical — flat and a bit dead. These give different objects different
/// personalities, and every one of them is *asymmetric*: the press goes
/// down fast and hard, the release springs back slowly. That asymmetry is
/// most of what reads as "alive" rather than "animated".
enum BouncyFeel {
  /// Buttons and controls: a crisp dip, then a small overshoot on release.
  snap,

  /// Big playful targets (game tiles, badges): deeper dip, a slight tilt,
  /// and a real elastic wobble coming back.
  wobble,

  /// Rows, cards, list items — things you tap *through* rather than play
  /// with. Gentle, no overshoot, nothing showy.
  soft,
}

/// Shared tap/hover feedback — every interactive shape in the app runs its
/// press and hover states through this, so nothing responds to a tap or a
/// pointer hover as a flat, static object.
class Bouncy extends StatefulWidget {
  const Bouncy({
    super.key,
    required this.child,
    this.onTap,
    this.feel = BouncyFeel.snap,
    double? pressScale,
    this.hoverScale = 1.03,
  }) : _pressScaleOverride = pressScale;

  final Widget child;
  final VoidCallback? onTap;
  final BouncyFeel feel;
  final double hoverScale;

  /// Callers can still pin an exact press depth; otherwise [feel] picks one.
  final double? _pressScaleOverride;

  double get pressScale =>
      _pressScaleOverride ??
      switch (feel) {
        BouncyFeel.snap => 0.96,
        BouncyFeel.wobble => 0.92,
        BouncyFeel.soft => 0.985,
      };

  /// Going down is always quick — a press should feel instant under the
  /// finger. The personality is all in the way it comes back.
  Duration get _pressDuration => const Duration(milliseconds: 90);

  Duration get _releaseDuration => switch (feel) {
        BouncyFeel.snap => const Duration(milliseconds: 280),
        BouncyFeel.wobble => const Duration(milliseconds: 520),
        BouncyFeel.soft => const Duration(milliseconds: 200),
      };

  Curve get _releaseCurve => switch (feel) {
        BouncyFeel.snap =>
          Curves.easeOutBack, // overshoots past rest, then settles
        BouncyFeel.wobble => Curves.elasticOut,
        BouncyFeel.soft => Curves.easeOut,
      };

  /// A few degrees of tilt on press, for [BouncyFeel.wobble] only — the
  /// "jiggle" that keeps a grid of game tiles from feeling like a form.
  double get _pressTurns => feel == BouncyFeel.wobble ? -0.006 : 0.0;

  @override
  State<Bouncy> createState() => _BouncyState();
}

class _BouncyState extends State<Bouncy> {
  bool _pressed = false;
  bool _hovering = false;

  void _setPressed(bool v) {
    if (widget.onTap == null) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    // Respect the OS "reduce motion" switch — springy overshoot is exactly
    // the kind of movement that setting exists to turn off.
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final scale =
        _pressed ? widget.pressScale : (_hovering ? widget.hoverScale : 1.0);
    final turns = _pressed ? widget._pressTurns : 0.0;

    final duration = reduce
        ? Duration.zero
        : (_pressed ? widget._pressDuration : widget._releaseDuration);
    final curve = _pressed ? Curves.easeOut : widget._releaseCurve;

    return MouseRegion(
      cursor:
          widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter:
          widget.onTap == null ? null : (_) => setState(() => _hovering = true),
      onExit: widget.onTap == null
          ? null
          : (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedRotation(
          turns: turns,
          duration: duration,
          curve: curve,
          child: AnimatedScale(
            scale: scale,
            duration: duration,
            curve: curve,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// "Comic Pop" — the TikTok-logo trick: a gold copy and a brand copy of the
/// same shape peek out from behind the solid, ink-outlined front layer,
/// offset to opposite corners. Nothing about it is a single flat fill — the
/// button reads as three stacked layers, not "a solid button". Pressing it
/// pulls both colored layers flush behind the front one (the offsets
/// collapse to zero), like the whole stack getting pushed together.
/// `go` = brand front, `gold` = gold front, `danger` = red front. `ghost`
/// stays a quiet, un-layered outline on purpose — it's the secondary action
/// next to one of these, and layering it too would fight for attention.
class NeonButton extends StatefulWidget {
  const NeonButton(this.label,
      {super.key,
      required this.onPressed,
      this.style = NeonStyle.go,
      this.expand = true});

  final String label;
  final VoidCallback? onPressed;
  final NeonStyle style;
  final bool expand;

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> {
  bool _pressed = false;
  bool _hovering = false;

  void _setPressed(bool v) {
    if (widget.onPressed == null) return;
    setState(() => _pressed = v);
  }

  void _setHovering(bool v) {
    if (widget.onPressed == null) return;
    setState(() => _hovering = v);
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final design = context.neonDesign.kind;
    final disabled = widget.onPressed == null;
    final scale = _pressed ? 0.96 : (_hovering ? 1.02 : 1.0);

    if (design != NeonDesignKind.cabinet) {
      final (fill, foreground) = switch (widget.style) {
        NeonStyle.go => (n.brand, Colors.white),
        NeonStyle.gold => (n.gold, n.onAccent),
        NeonStyle.danger => (n.danger, Colors.white),
        NeonStyle.ghost => (n.panel, n.ink),
      };
      final edge = widget.style == NeonStyle.ghost ? n.line : n.gold;
      final solid = widget.style == NeonStyle.gold ||
          widget.style == NeonStyle.danger;
      final blend = Theme.of(context).brightness == Brightness.light ? 0.08 : 0.25;
      final Decoration decoration = design == NeonDesignKind.supercar
          ? ShapeDecoration(
              color: solid ? fill : null,
              gradient: solid ? null : LinearGradient(
                  colors: [fill, Color.lerp(fill, n.plate, blend)!]),
              shape: BeveledRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: edge, width: 1.5),
              ),
              shadows: disabled ? null : [BoxShadow(
                color: edge.withValues(alpha: _pressed ? 0.08 : 0.25),
                blurRadius: 12,
              )],
            )
          : BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: solid ? fill : null,
              gradient: solid ? null : LinearGradient(
                  colors: [fill, Color.lerp(fill, n.panel, blend)!]),
              border: Border.all(color: edge.withValues(alpha: 0.65)),
              boxShadow: disabled ? null : [BoxShadow(
                color: fill.withValues(alpha: _pressed ? 0.12 : 0.35),
                blurRadius: 18,
                spreadRadius: -3,
              )],
            );
      return Semantics(
        button: true,
        label: widget.label,
        child: MouseRegion(
          cursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
          onEnter: (_) => _setHovering(true),
          onExit: (_) => _setHovering(false),
          child: GestureDetector(
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            onTap: widget.onPressed,
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 130),
              child: AnimatedContainer(
                key: ValueKey(design),
                duration: const Duration(milliseconds: 160),
                width: widget.expand ? double.infinity : null,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 22),
                decoration: decoration,
                child: Text(widget.label,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: foreground,
                        fontSize: 16,
                        letterSpacing: design == NeonDesignKind.supercar ? 1.1 : 0.2)),
              ),
            ),
          ),
        ),
      );
    }

    if (widget.style == NeonStyle.ghost) {
      return Semantics(
        button: true,
        label: widget.label,
        child: MouseRegion(
          cursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
          onEnter: (_) => _setHovering(true),
          onExit: (_) => _setHovering(false),
          child: GestureDetector(
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            onTap: widget.onPressed,
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 130),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: widget.expand ? double.infinity : null,
                alignment: Alignment.center,
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(NeonRadius.control),
                  border: Border.all(color: n.brand, width: 2),
                ),
                child: Text(
                  widget.label,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: n.ink, fontSize: 17),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final (Color front, Color fg) = switch (widget.style) {
      NeonStyle.gold => (n.gold, n.onAccent),
      NeonStyle.danger => (n.danger, Colors.white),
      NeonStyle.go || NeonStyle.ghost => (n.brand, Colors.white),
    };
    final baseOffset = disabled ? 0.0 : (_hovering && !_pressed ? 5.0 : 4.0);
    final offset = _pressed ? 0.0 : baseOffset;
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
        onEnter: (_) => _setHovering(true),
        onExit: (_) => _setHovering(false),
        child: GestureDetector(
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: widget.onPressed,
          child: Padding(
            // room for the colored layers to peek past the front layer's edges
            padding: const EdgeInsets.all(5),
            child: _LayeredSurface(
              front: front,
              offset: offset,
              expand: widget.expand,
              child: Text(
                widget.label,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: fg, fontSize: 17),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LayeredSurface extends StatelessWidget {
  const _LayeredSurface(
      {required this.front,
      required this.offset,
      required this.expand,
      required this.child});

  final Color front;
  final double offset;
  final bool expand;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final radius = BorderRadius.circular(NeonRadius.control);
    Widget layer(Color? fill, {Color? border}) => AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: border == null ? null : Border.all(color: border, width: 3),
          ),
        );

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Transform.translate(
            offset: Offset(-offset, -offset), child: layer(n.gold)),
        Transform.translate(
            offset: Offset(offset, offset), child: layer(n.brand)),
        layer(front, border: kCabinetInk),
        // the front layer above is empty (just establishes size + ink ring);
        // the label sits in its own identically-padded layer on top of it.
        IgnorePointer(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// The Arcade Cabinet surface — a solid fill inside a thick ink (or accent)
/// ring, with an optional top-highlight/bottom-shadow bevel that inverts
/// when [pressed]. Built from stacked solid layers rather than `BoxShadow`'s
/// `inset` (not available on the Flutter version this app targets), so the
/// bevel is two flat strips clipped to the surface's own rounded corners —
/// still a flat-color look, just shaped like a physical button. Shared by
/// [NeonButton] and [NeonCard] so both read as the same material.
class CabinetSurface extends StatelessWidget {
  const CabinetSurface({
    super.key,
    required this.child,
    required this.fill,
    this.ring = kCabinetInk,
    this.beveled = true,
    this.pressed = false,
    this.radius,
    this.ringWidth = 3,
  });

  final Widget child;
  final Color fill;
  final Color ring;
  final bool beveled;
  final bool pressed;
  final BorderRadius? radius;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? BorderRadius.circular(NeonRadius.control);
    final topColor = pressed
        ? Colors.black.withValues(alpha: 0.24)
        : Colors.white.withValues(alpha: 0.45);
    final bottomColor = pressed
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.24);
    return ClipRRect(
      borderRadius: r,
      child: Container(
        decoration:
            BoxDecoration(border: Border.all(color: ring, width: ringWidth)),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: fill)),
            if (beveled) ...[
              Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(height: 4, color: topColor)),
              Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(height: 5, color: bottomColor)),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class NeonCard extends StatelessWidget {
  const NeonCard({
    super.key,
    required this.child,
    this.onTap,
    this.accent,
    this.selected = false,
    this.dashed = false,
    this.padding,
    this.mirror = false,
    this.glass = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? accent;
  final bool selected;
  final bool dashed;
  final EdgeInsets? padding;

  /// Flip the card's asymmetric corners — alternate this across a grid/list
  /// so the "blob" shapes don't all lean the same way.
  final bool mirror;

  /// Frosted glass rather than a solid panel: the card lets the background
  /// through and blurs it. Set false for a card sitting over a busy image
  /// or in a long scrolling list, where a per-card blur costs more than it
  /// gives.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final design = context.neonDesign.kind;
    if (design != NeonDesignKind.cabinet) {
      final edge = selected ? (accent ?? n.gold) : n.line;
      final Decoration decoration = design == NeonDesignKind.supercar
          ? ShapeDecoration(
              gradient: LinearGradient(colors: [n.panel, n.plate]),
              shape: BeveledRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: edge, width: selected ? 2 : 1.2),
              ),
              shadows: selected ? [BoxShadow(
                color: edge.withValues(alpha: 0.32), blurRadius: 18)] : null,
            )
          : BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(colors: [
                n.panel.withValues(alpha: 0.92),
                n.plate.withValues(alpha: 0.78),
              ]),
              border: Border.all(color: edge.withValues(alpha: 0.8),
                  width: selected ? 2 : 1),
              boxShadow: [BoxShadow(
                color: (selected ? edge : n.brand).withValues(alpha: selected ? 0.3 : 0.12),
                blurRadius: selected ? 24 : 14,
              )],
            );
      final card = AnimatedContainer(
        key: ValueKey(design),
        duration: const Duration(milliseconds: 180),
        decoration: decoration,
        child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
      );
      if (onTap == null) return card;
      return Bouncy(onTap: onTap, pressScale: 0.98,
          hoverScale: 1.015, child: card);
    }
    final ring = selected ? (accent ?? n.brand) : kCabinetInk;
    final radius = NeonRadius.blob(mirror: mirror);
    final body =
        Padding(padding: padding ?? const EdgeInsets.all(16), child: child);
    final card = AnimatedContainer(
      key: ValueKey(design),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: selected
            ? [
                BoxShadow(
                    color: (accent ?? n.brand).withValues(alpha: 0.35),
                    blurRadius: 22,
                    spreadRadius: -6)
              ]
            : null,
      ),
      child: glass
          ? ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    // Enough panel to keep text legible, little enough to
                    // read as glass over whatever is behind it.
                    color: n.panel.withValues(alpha: 0.52),
                    border: Border.all(
                      color: selected
                          ? ring
                          : Colors.white.withValues(alpha: 0.16),
                      width: selected ? 2.5 : 1.2,
                    ),
                  ),
                  child: body,
                ),
              ),
            )
          : CabinetSurface(
              fill: n.panel,
              ring: ring,
              ringWidth: selected ? 3 : 2,
              beveled: false,
              radius: radius,
              child: body,
            ),
    );
    if (onTap == null) return card;
    return Bouncy(
        onTap: onTap, pressScale: 0.98, hoverScale: 1.015, child: card);
  }
}

/// A softly scrolling marquee strip — the theme's signature. Static under reduced motion.
class MarqueeBar extends StatefulWidget {
  const MarqueeBar(this.text, {super.key});
  final String text;

  @override
  State<MarqueeBar> createState() => _MarqueeBarState();
}

class _MarqueeBarState extends State<MarqueeBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 18))
        ..repeat();

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
          color: n.gold,
          letterSpacing: 3,
          fontWeight: FontWeight.w700,
        );
    return Container(
      height: 34,
      alignment: Alignment.centerLeft,
      color: n.plate,
      child: ClipRect(
        child: reduce
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(line, style: style))
            : AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final w = MediaQuery.sizeOf(context).width;
                  final dx = -_c.value * w;
                  return Stack(children: [
                    Positioned(
                        left: dx,
                        child: Text(line * 6, maxLines: 1, style: style)),
                    Positioned(
                        left: dx + w * 6,
                        child: Text(line * 6, maxLines: 1, style: style)),
                  ]);
                },
              ),
      ),
    );
  }
}

/// The 15 preset profile icons offered in Settings — a mix of animal
/// mascots, a villain half (mask, alien, ninja, devil) and a faithful half
/// (angel), matching the game's own Traitors-vs-Faithful split.
const List<String> kAvatarPresets = [
  '🦊', '🐺', '🎭', '🕵️', '🦁', '🐸', '🦄', '🐙', '🦉', '🐲', // mascots
  '👺', '👽', '🥷', '😈', // traitor-flavored
  '😇', // faithful-flavored
];

class Avatar extends StatelessWidget {
  const Avatar(this.name,
      {super.key,
      this.size = 28,
      this.color,
      this.emoji,
      this.imagePath,
      this.imageUrl});
  final String name;
  final double size;
  final Color? color;

  /// One of [kAvatarPresets], or null. Ignored if [imagePath] is set.
  final String? emoji;

  /// A locally-picked photo path. Takes priority over [emoji].
  final String? imagePath;

  /// A remote profile photo. Used when no local photo is available.
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final path = imagePath;
    Widget content;
    if (path != null && File(path).existsSync()) {
      content = ClipOval(
        child: Image.file(File(path),
            width: size, height: size, fit: BoxFit.cover),
      );
    } else if (imageUrl?.startsWith('data:image/') == true) {
      try {
        content = ClipOval(child: Image.memory(
          base64Decode(imageUrl!.split(',').last),
          width: size, height: size, fit: BoxFit.cover,
        ));
      } catch (_) {
        content = Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: TextStyle(fontWeight: FontWeight.w800,
                fontSize: size * 0.42, color: n.ink));
      }
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      content = ClipOval(
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: size * 0.42,
                color: n.ink),
          ),
        ),
      );
    } else if (emoji != null && emoji!.isNotEmpty) {
      content = Text(emoji!, style: TextStyle(fontSize: size * 0.55));
    } else {
      content = Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
            fontWeight: FontWeight.w800, fontSize: size * 0.42, color: n.ink),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? n.plate,
        shape: BoxShape.circle,
        border: Border.all(color: kCabinetInk, width: 2),
      ),
      child: content,
    );
  }
}

/// A small green dot only while the person has a live app connection.
class OnlineAvatar extends StatelessWidget {
  const OnlineAvatar(this.name, {
    super.key,
    required this.online,
    this.size = 32,
    this.imageUrl,
    this.imagePath,
    this.emoji,
  });

  final String name;
  final bool online;
  final double size;
  final String? imageUrl;
  final String? imagePath;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final dotSize = (size * 0.28).clamp(8.0, 16.0);
    return Semantics(
      label: online ? '$name, online' : name,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.none, children: [
          Avatar(name, size: size, imageUrl: imageUrl,
              imagePath: imagePath, emoji: emoji),
          if (online)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: const Color(0xff4ade80),
                  shape: BoxShape.circle,
                  border: Border.all(color: n.panel, width: 2),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// A frosted, translucent surface for anything that floats above the page —
/// modal sheets, the game-invite banner. The blur is what makes it read as
/// a *layer*: you can still see the app moving underneath, which is the
/// difference between "a panel appeared" and "a solid slab dropped on the
/// screen".
class NeonGlass extends StatelessWidget {
  const NeonGlass({
    super.key,
    required this.child,
    this.borderRadius,
    this.opacity = 0.62,
    this.blur = 22,
    this.border = true,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final double opacity;
  final double blur;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final radius =
        borderRadius ?? const BorderRadius.vertical(top: Radius.circular(28));
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: n.panel.withValues(alpha: opacity),
            borderRadius: radius,
            border: border
                ? Border.all(
                    color: kCabinetInk.withValues(alpha: 0.55), width: 1.5)
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Opens a modal sheet with the app's motion and glass treatment: it rises
/// and fades in together rather than snapping up, over a soft blurred dim.
Future<T?> showNeonSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: kScrim,
    elevation: 0,
    transitionAnimationController: null,
    builder: (ctx) => NeonGlass(child: builder(ctx)),
  );
}
