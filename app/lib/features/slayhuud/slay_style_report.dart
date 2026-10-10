import 'package:flutter/material.dart';
import '../../theme/neon_theme.dart';
import 'slay_theme.dart';

class SlayStyleReport extends StatelessWidget {
  const SlayStyleReport(
      {super.key, required this.score, required this.themeTitle});
  final Map<String, dynamic> score;
  final String themeTitle;

  @override
  Widget build(BuildContext context) => SafeArea(
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SlayLabel('Your style report'),
            const SizedBox(height: 10),
            Text(themeTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Judged by theme, item and palette tags.',
                style: TextStyle(color: context.neon.mute, fontSize: 12)),
            Text('${score['overall']}',
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(fontSize: 64)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 3; i++)
                Icon(
                    i < (score['stars'] as num)
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: context.neon.gold,
                    size: 32)
            ]),
            const SizedBox(height: 20),
            for (final dim in {
              'themeFit': 'Theme fit',
              'requirements': 'Required items',
              'colour': 'Palette balance',
              'completeness': 'Completeness'
            }.entries)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Expanded(child: Text(dim.value)),
                    Text('${score[dim.key]} / 100',
                        style: const TextStyle(fontWeight: FontWeight.w600))
                  ])),
            for (final tip in (score['feedback'] as List? ?? []))
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(tip.toString(),
                      style: TextStyle(color: context.neon.mute))),
            if ((score['feedback'] as List? ?? []).isEmpty &&
                (score['missing'] as List).isNotEmpty)
              Text('Try adding: ${(score['missing'] as List).join(', ')}',
                  style: TextStyle(color: context.neon.mute)),
            const SizedBox(height: 14),
            Text(
                score['preview'] == true
                    ? 'Preview score — no coins or XP awarded.'
                    : 'Coins and XP are awarded once per theme each day.',
                style: TextStyle(color: context.neon.mute, fontSize: 12)),
            const SizedBox(height: 20),
            SizedBox(
                width: double.infinity,
                child: SlayButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to the studio'))),
          ])));
}
