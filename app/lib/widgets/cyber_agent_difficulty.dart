import 'package:flutter/material.dart';

import '../theme/neon_theme.dart';

/// Three discrete bot levels. Values stay compatible with the room API.
class CyberAgentDifficulty extends StatelessWidget {
  const CyberAgentDifficulty({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String>? onChanged;

  static const _levels = [
    ('easy', 'Rookie', 'Easy'),
    ('medium', 'Pro', 'Medium'),
    ('hard', 'Legend', 'Hard'),
  ];

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final selected = _levels.indexWhere((level) => level.$1 == value);
    return LayoutBuilder(builder: (context, constraints) {
      return GestureDetector(
        onHorizontalDragUpdate: onChanged == null
            ? null
            : (details) {
                final index =
                    (details.localPosition.dx / constraints.maxWidth * 3)
                        .floor()
                        .clamp(0, 2);
                final next = _levels[index].$1;
                if (next != value) onChanged!(next);
              },
        child: Opacity(
          opacity: onChanged == null ? 0.5 : 1,
          child: Stack(
            children: [
              Positioned(
                left: constraints.maxWidth / 6,
                right: constraints.maxWidth / 6,
                bottom: 17,
                height: 2,
                child: ColoredBox(
                  color: n.line,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: selected.clamp(0, 2) / 2,
                      heightFactor: 1,
                      child: ColoredBox(color: n.gold),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final level in _levels)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: value == level.$1,
                        enabled: onChanged != null,
                        label: '${level.$2}, ${level.$3} difficulty',
                        onTap: onChanged == null
                            ? null
                            : () => onChanged!(level.$1),
                        excludeSemantics: true,
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            key: ValueKey('segment-${level.$1}'),
                            borderRadius: BorderRadius.circular(14),
                            onTap: onChanged == null
                                ? null
                                : () => onChanged!(level.$1),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: value == level.$1
                                        ? n.gold
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    level.$2,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: value == level.$1
                                          ? n.onAccent
                                          : n.mid,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  height: 36,
                                  child: Center(
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 160),
                                      width: value == level.$1 ? 16 : 10,
                                      height: value == level.$1 ? 16 : 10,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color:
                                            value == level.$1 ? n.gold : n.mid,
                                        boxShadow: value == level.$1
                                            ? [
                                                BoxShadow(
                                                  color: n.gold
                                                      .withValues(alpha: 0.22),
                                                  blurRadius: 9,
                                                  spreadRadius: 2,
                                                ),
                                              ]
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }
}
