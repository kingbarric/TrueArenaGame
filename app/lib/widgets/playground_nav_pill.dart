import 'package:flutter/material.dart';

import '../theme/neon_theme.dart';

/// A floating rounded pill nav — the toy-box alternative to a traditional
/// full-width bottom bar (see the "Playground Home" design pass). Lives
/// only on `HomeScreen` for now: the rest of the app is still pushed via
/// `Navigator`, not a persistent tab shell, so this is a decorative/
/// shortcut rail rather than a real tab bar — a bigger, separate change if
/// the whole app ever moves to one.
class PlaygroundNavPill extends StatelessWidget {
  const PlaygroundNavPill({super.key, required this.items, required this.activeIndex});

  final List<PlaygroundNavItem> items;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final design = context.neonDesign.kind;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: design == NeonDesignKind.supercar
          ? ShapeDecoration(
              gradient: LinearGradient(colors: [n.panel, n.plate]),
              shape: BeveledRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: n.gold, width: 1.5),
              ),
              shadows: [BoxShadow(color: n.gold.withValues(alpha: 0.18), blurRadius: 18)],
            )
          : BoxDecoration(
              color: n.panel,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: design == NeonDesignKind.nebula ? n.line : kCabinetInk,
                  width: design == NeonDesignKind.nebula ? 1.2 : 2.5),
              boxShadow: design == NeonDesignKind.nebula
                  ? [BoxShadow(color: n.brand.withValues(alpha: 0.25), blurRadius: 20)]
                  : const [BoxShadow(color: Colors.black38, blurRadius: 0, offset: Offset(3, 4))],
            ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < items.length; i++) _pillItem(context, n, items[i], i == activeIndex),
      ]),
    );
  }

  Widget _pillItem(BuildContext context, NeonColors n, PlaygroundNavItem item, bool active) {
    final design = context.neonDesign.kind;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: item.onTap,
        child: AnimatedContainer(
          key: ValueKey(design),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          width: active ? 50 : 44,
          height: active ? 50 : 44,
          transform: active ? Matrix4.translationValues(0.0, -4.0, 0.0) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: design == NeonDesignKind.supercar
              ? ShapeDecoration(
                  color: active ? n.gold : Colors.transparent,
                  shape: BeveledRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                    side: BorderSide(color: active ? n.gold : n.line,
                        width: active ? 1.4 : 0.8),
                  ),
                )
              : BoxDecoration(
                  shape: design == NeonDesignKind.nebula
                      ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: design == NeonDesignKind.nebula
                      ? BorderRadius.circular(16) : null,
                  color: active ? n.gold : Colors.transparent,
                  border: active ? Border.all(
                      color: design == NeonDesignKind.nebula ? n.brand : kCabinetInk,
                      width: design == NeonDesignKind.nebula ? 1.2 : 2.4) : null,
                  boxShadow: active
                      ? (design == NeonDesignKind.nebula
                          ? [BoxShadow(color: n.brand.withValues(alpha: 0.38), blurRadius: 14)]
                          : const [BoxShadow(color: Colors.black38, blurRadius: 0, offset: Offset(1, 2))])
                      : null,
                ),
          alignment: Alignment.center,
          child: Icon(item.icon, size: active ? 21 : 19, color: active ? kCabinetInk : n.mute),
        ),
      ),
    );
  }
}

class PlaygroundNavItem {
  const PlaygroundNavItem({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
}
