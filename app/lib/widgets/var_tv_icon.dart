import 'package:flutter/material.dart';

/// The little "VAR" television that opens a replay of the last move — the
/// same badge in every board game that has one.
class VarTvIcon extends StatelessWidget {
  const VarTvIcon({
    super.key,
    required this.enabled,
    this.casing = const Color(0xffe0a94a),
    this.screen = const Color(0xff241708),
    this.label = const Color(0xffffe6ae),
    this.disabled = const Color(0xff6f604e),
  });

  final bool enabled;
  final Color casing;
  final Color screen;
  final Color label;
  final Color disabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 32,
      child: Stack(alignment: Alignment.center, children: [
        Icon(Icons.tv_rounded, size: 34, color: enabled ? casing : disabled),
        Positioned(
          top: 9,
          left: 7,
          right: 7,
          child: DecoratedBox(
            decoration: BoxDecoration(
                color: screen, borderRadius: BorderRadius.circular(2)),
            child: Text('VAR',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: enabled ? label : disabled,
                    fontSize: 7,
                    height: 1.25,
                    fontWeight: FontWeight.w900)),
          ),
        ),
      ]),
    );
  }
}
