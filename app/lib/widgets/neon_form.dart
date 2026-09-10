import 'package:flutter/material.dart';

import '../theme/neon_theme.dart';

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
            activeTrackColor: n.cyan,
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
    Widget btn(IconData icon, int delta) => InkResponse(
          onTap: () {
            final next = (value + delta).clamp(min, max).toInt();
            if (next != value) onChanged(next);
          },
          radius: 22,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: n.plate,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: n.line),
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
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: n.plate,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: n.line),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(o.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: o.value == value ? LinearGradient(colors: [n.cyan, n.cyan]) : null,
                    borderRadius: BorderRadius.circular(9),
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
    final a = accent ?? n.cyan;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? a.withValues(alpha: 0.14) : n.plate,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? a : n.line, width: selected ? 1.5 : 1),
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
            activeTrackColor: n.cyan,
            inactiveTrackColor: n.line,
            thumbColor: n.cyan,
            overlayColor: n.cyan.withValues(alpha: 0.15),
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
            if (safeLow != null) _tick('$safeLow', n.acid),
            if (safeHigh != null) _tick('$safeHigh', n.acid),
            _tick('$max', n.mute),
          ],
        ),
      ],
    );
  }

  Widget _tick(String t, Color c) => Text(t,
      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1, color: c));
}
