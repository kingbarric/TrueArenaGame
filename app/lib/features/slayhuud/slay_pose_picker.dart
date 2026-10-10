import 'package:flutter/material.dart';
import '../../theme/neon_theme.dart';
import 'slay_theme.dart';

const slayPoses = {
  'signature': (
    label: 'Signature',
    description: 'Relaxed runway attitude',
    icon: Icons.accessibility_new_rounded
  ),
  'confident': (
    label: 'Hand on hip',
    description: 'Confident, ready to slay',
    icon: Icons.star_rounded
  ),
  'editorial': (
    label: 'Cover star',
    description: 'Angled waist and head tilt',
    icon: Icons.photo_camera_rounded
  ),
  'celebrate': (
    label: 'Victory',
    description: 'Arms up, own the spotlight',
    icon: Icons.emoji_events_rounded
  ),
};

class SlayPosePicker extends StatelessWidget {
  const SlayPosePicker(
      {super.key,
      required this.selected,
      required this.available,
      required this.onSelected});
  final String selected;
  final List<String> available;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SlayLabel('Pick your show-off pose'),
            const SizedBox(height: 8),
            Text('Every pose starts with a catwalk. Tap one to try it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.neon.mute, fontSize: 12)),
            const SizedBox(height: 20),
            LayoutBuilder(
                builder: (context, constraints) =>
                    Wrap(spacing: 12, runSpacing: 18, children: [
                      for (final entry in slayPoses.entries)
                        if (available.contains(entry.key))
                          SizedBox(
                              width: (constraints.maxWidth - 12) / 2,
                              child: Column(children: [
                                SlayPill(
                                    label: entry.value.label,
                                    icon: entry.value.icon,
                                    selected: selected == entry.key,
                                    onPressed: () => onSelected(entry.key)),
                                const SizedBox(height: 5),
                                Text(entry.value.description,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: context.neon.mute,
                                        fontSize: 11)),
                              ])),
                    ])),
            const SizedBox(height: 8),
          ])));
}
