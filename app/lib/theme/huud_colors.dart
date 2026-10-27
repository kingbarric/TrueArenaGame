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

  // A warm orange, not a neon one: toned down from #FF8A1F so the hero
  // card and buttons don't glare, with dark ink on them still easy to read.
  static const _dark = HuudColors(
    orange: Color(0xFFE0812E),
    orangeDeep: Color(0xFFCE6422),
    orangeText: Color(0xFFEA9E57),
    orangeSoft: Color(0x26E0812E),
    onOrange: kCabinetInk,
    live: Color(0xFF4ADE80),
  );

  static const _light = HuudColors(
    orange: Color(0xFFE0812E),
    orangeDeep: Color(0xFFD56820),
    orangeText: Color(0xFFB34A00),
    orangeSoft: Color(0xFFFFE8D2),
    onOrange: kCabinetInk,
    live: Color(0xFF15803D),
  );

  static HuudColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  /// A small reduction in button saturation; artwork and status accents stay vivid.
  Color get buttonFill => Color.lerp(orange, const Color(0xFFFFE0B8), .18)!;

  LinearGradient get glow => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [orange, orangeDeep],
      );
}
