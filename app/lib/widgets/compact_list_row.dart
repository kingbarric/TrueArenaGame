import 'package:flutter/material.dart';

import '../theme/neon_theme.dart';

/// A plain, space-efficient row for repeated items such as people and rooms.
/// Keeps touch targets usable while avoiding a full card around every item.
class CompactListRow extends StatelessWidget {
  const CompactListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final design = context.neonDesign.kind;
    final Decoration decoration = switch (design) {
      NeonDesignKind.cabinet => BoxDecoration(
          border: Border(bottom: BorderSide(color: n.line))),
      NeonDesignKind.nebula => BoxDecoration(
          color: n.panel.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: n.line.withValues(alpha: 0.7))),
      NeonDesignKind.supercar => ShapeDecoration(
          color: n.panel,
          shape: BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: n.line),
          )),
    };
    return Container(
      margin: design == NeonDesignKind.cabinet
          ? EdgeInsets.zero : const EdgeInsets.only(bottom: 4),
      decoration: decoration,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: design == NeonDesignKind.cabinet ? 2 : 8,
                vertical: 4),
            child: Row(children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    if (subtitle != null) subtitle!,
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 6),
                trailing!,
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
