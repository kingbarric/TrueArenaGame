import 'package:flutter/material.dart';
import '../../theme/neon_theme.dart';

class SlayColourPicker extends StatelessWidget {
  const SlayColourPicker(
      {super.key,
      required this.palette,
      required this.selected,
      required this.onChanged,
      this.enabled = true});
  final Map<String, String> palette;
  final String? selected;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 44,
      child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          children: [
            Center(
                child: Text('Colour',
                    style: TextStyle(color: context.neon.mute, fontSize: 11))),
            const SizedBox(width: 8),
            for (final colour in <String?>[null, ...palette.keys])
              Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Semantics(
                      selected: selected == colour,
                      child: Tooltip(
                          message: colour ?? 'Original colour',
                          child: IconButton.filledTonal(
                              onPressed:
                                  enabled ? () => onChanged(colour) : null,
                              style: IconButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(36, 36),
                                  maximumSize: const Size(36, 36),
                                  backgroundColor: colour == null
                                      ? context.neon.panel
                                      : Color(int.parse(
                                          palette[colour]!
                                              .replaceFirst('#', 'ff'),
                                          radix: 16)),
                                  side: BorderSide(
                                      color: selected == colour
                                          ? context.neon.gold
                                          : context.neon.line,
                                      width: selected == colour ? 3 : 1)),
                              icon: Icon(
                                  colour == null
                                      ? Icons.restart_alt_rounded
                                      : selected == colour
                                          ? Icons.check_rounded
                                          : null,
                                  size: 17,
                                  color: colour == 'white' || colour == 'yellow'
                                      ? Colors.black
                                      : Colors.white))))),
          ]));
}
