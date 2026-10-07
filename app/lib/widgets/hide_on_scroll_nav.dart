import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

/// A floating bottom bar that gets out of the way while you read: it slides
/// away when the content is scrolled down and comes back the moment you
/// scroll up or reach the top — the way Twitter's tab bar behaves.
///
/// Only vertical scrolling counts; a sideways swipe (the player-card
/// carousel, a row of chips) leaves the bar where it is. Changing
/// [resetKey] (e.g. switching tabs) always brings it back.
class HideOnScrollNav extends StatefulWidget {
  const HideOnScrollNav({
    super.key,
    required this.body,
    required this.nav,
    this.bottom = 18,
    this.resetKey,
  });

  final Widget body;
  final Widget nav;
  final double bottom;
  final Object? resetKey;

  @override
  State<HideOnScrollNav> createState() => _HideOnScrollNavState();
}

class _HideOnScrollNavState extends State<HideOnScrollNav> {
  bool _visible = true;

  @override
  void didUpdateWidget(covariant HideOnScrollNav old) {
    super.didUpdateWidget(old);
    if (old.resetKey != widget.resetKey) _visible = true;
  }

  void _set(bool visible) {
    if (visible != _visible) setState(() => _visible = visible);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is UserScrollNotification) {
      switch (n.direction) {
        case ScrollDirection.reverse:
          _set(false);
        case ScrollDirection.forward:
          _set(true);
        case ScrollDirection.idle:
          break;
      }
    } else if (n is ScrollUpdateNotification && n.metrics.pixels <= n.metrics.minScrollExtent) {
      _set(true); // back at the top
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
        child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.body),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: widget.bottom,
        child: IgnorePointer(
          ignoring: !_visible,
          child: AnimatedSlide(
            key: const ValueKey('hide-on-scroll-nav'),
            offset: _visible ? Offset.zero : const Offset(0, 2),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: widget.nav,
            ),
          ),
        ),
      ),
    ]);
  }
}
