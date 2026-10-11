import 'package:flutter/widgets.dart';

/// A sideways swipe moves to the next or previous tab, for screens whose
/// tabs share one scrolling page (so a [PageView] doesn't fit). Vertical
/// scrolling is untouched: only a mostly-horizontal fling counts, and a
/// sideways list inside (a row of chips, a bracket) still scrolls itself.
class SwipeToSwitch extends StatelessWidget {
  const SwipeToSwitch({super.key, required this.child, this.onNext, this.onPrevious});

  final Widget child;

  /// Swiped left — the tab to the right. Null at the last tab.
  final VoidCallback? onNext;

  /// Swiped right — the tab to the left. Null at the first tab.
  final VoidCallback? onPrevious;

  static const _minVelocity = 300.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v <= -_minVelocity) {
          onNext?.call();
        } else if (v >= _minVelocity) {
          onPrevious?.call();
        }
      },
      child: child,
    );
  }
}

/// The tab next to [current] in [tabs], or null at either end.
T? neighbourTab<T>(List<T> tabs, T current, int step) {
  final i = tabs.indexOf(current) + step;
  return i < 0 || i >= tabs.length || tabs.indexOf(current) < 0 ? null : tabs[i];
}
