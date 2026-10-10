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

  static const _dark = HuudColors(
    orange: Color(0xFFFF8A1F),
    orangeDeep: Color(0xFFE85D04),
    orangeText: Color(0xFFFFA24C),
    orangeSoft: Color(0x26FF8A1F),
    onOrange: kCabinetInk,
    live: Color(0xFF4ADE80),
  );

  static const _light = HuudColors(
    orange: Color(0xFFFF8A1F),
    orangeDeep: Color(0xFFF26B0F),
    orangeText: Color(0xFFB34A00),
    orangeSoft: Color(0xFFFFE8D2),
    onOrange: kCabinetInk,
    live: Color(0xFF15803D),
  );

  static HuudColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  LinearGradient get glow => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [orange, orangeDeep],
      );
}
