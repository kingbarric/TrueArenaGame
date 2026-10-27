import 'package:flutter/material.dart';

import 'neon_theme.dart';

/// Orange text on orange-ish paper fails contrast in daylight, so there are
/// two oranges: [HuudColors.orange] fills buttons (always with dark ink on
/// top), [HuudColors.orangeText] is the deeper/brighter one for words and
/// icons sitting on the page.
@immutable
class HuudColors {
  const HuudColors({
    required this.orange,
    required this.orangeDeep,
    required this.orangeText,
    required this.orangeSoft,
    required this.onOrange,
    required this.live,
  });

  final Color orange, orangeDeep, orangeText, orangeSoft, onOrange, live;

  // Muted terracotta keeps large cards and buttons calm. Both gradient
  // endpoints retain at least 4.9:1 contrast with the dark label ink.
  static const _dark = HuudColors(
    orange: Color(0xFFB9855B),
    orangeDeep: Color(0xFFAC7952),
    orangeText: Color(0xFFD1A37D),
    orangeSoft: Color(0x1AB9855B),
    onOrange: kCabinetInk,
    live: Color(0xFF4ADE80),
  );

  static const _light = HuudColors(
    orange: Color(0xFFB9855B),
    orangeDeep: Color(0xFFAC7952),
    orangeText: Color(0xFF925E3A),
    orangeSoft: Color(0xFFF0E1D4),
    onOrange: kCabinetInk,
    live: Color(0xFF15803D),
  );

  static HuudColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  /// A gentle lift in the muted fill, without the old bright peach cast.
  Color get buttonFill => Color.lerp(orange, const Color(0xFFD8C3B2), .10)!;

  LinearGradient get glow => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [orange, orangeDeep],
      );
}
