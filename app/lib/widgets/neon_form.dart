import 'package:flutter/material.dart';

import '../theme/neon_theme.dart';
import 'neon.dart';

/// Small Night-Market form controls, matching the "Set the Night" prototype.

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Row(
      children: [
        Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: n.mid,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                )),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

class NeonSwitchRow extends StatelessWidget {
  const NeonSwitchRow({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: n.onAccent,
            activeTrackColor: n.gold,
          ),
        ],
      ),
    );
  }
}

class NeonStepper extends StatelessWidget {
  const NeonStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999,
    this.step = 1,
    this.format,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min, max, step;
  final String Function(int)? format;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    Widget btn(IconData icon, int delta) => Bouncy(
          onTap: () {
            final next = (value + delta).clamp(min, max).toInt();
            if (next != value) onChanged(next);
          },
          pressScale: 0.88,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: n.plate,
              shape: BoxShape.circle,
              border: Border.all(color: kCabinetInk, width: 2),
            ),
            child: Icon(icon, size: 18, color: n.ink),
          ),
        );
    return Row(
      children: [
        btn(Icons.remove, -step),
        const SizedBox(width: 10),
        SizedBox(
          width: 56,
          child: Text(
            format?.call(value) ?? '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 10),
        btn(Icons.add, step),
      ],
    );
  }
}

class SegOption<T> {
  const SegOption(this.value, this.label);
  final T value;
  final String label;
}

class NeonSegmented<T> extends StatelessWidget {
  const NeonSegmented({super.key, required this.options, required this.value, required this.onChanged});
  final List<SegOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: n.plate,
        borderRadius: BorderRadius.circular(NeonRadius.pill),
        border: Border.all(color: kCabinetInk, width: 2),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: Bouncy(
                onTap: () => onChanged(o.value),
                pressScale: 0.94,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: o.value == value ? n.gold : null,
                    borderRadius: BorderRadius.circular(NeonRadius.pill),
                  ),
                  child: Text(
                    o.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: o.value == value ? n.onAccent : n.mute,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NeonChip extends StatelessWidget {
  const NeonChip({super.key, required this.label, required this.selected, required this.onTap, this.accent});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final a = accent ?? n.gold;
    return Bouncy(
      onTap: onTap,
      pressScale: 0.93,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? a.withValues(alpha: 0.14) : n.plate,
          borderRadius: BorderRadius.circular(NeonRadius.pill),
          border: Border.all(color: selected ? a : kCabinetInk, width: selected ? 2 : 1.6),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: selected ? n.ink : n.mid,
          ),
        ),
      ),
    );
  }
}

class NeonSlider extends StatelessWidget {
  const NeonSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.safeLow,
    this.safeHigh,
  });

  final int value, min, max;
  final int? safeLow, safeHigh;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: n.gold,
            inactiveTrackColor: n.line,
            thumbColor: n.gold,
            overlayColor: n.gold.withValues(alpha: 0.15),
            trackHeight: 5,
          ),
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _tick('$min', n.mute),
            if (safeLow != null) _tick('$safeLow', n.jade),
            if (safeHigh != null) _tick('$safeHigh', n.jade),
            _tick('$max', n.mute),
          ],
        ),
      ],
    );
  }

  Widget _tick(String t, Color c) => Text(t,
      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1, color: c));
}
