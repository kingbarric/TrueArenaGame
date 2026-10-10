import 'package:flutter/material.dart';
import '../../theme/neon_theme.dart';
import 'slay_theme.dart';

class SlayStyleReport extends StatelessWidget {
  const SlayStyleReport(
      {super.key,
      required this.score,
      required this.themeTitle,
      this.career = false});
  final Map<String, dynamic> score;
  final String themeTitle;
  final bool career;

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
              for (var i = 0; i < (career ? 5 : 3); i++)
                Icon(
                    i < (score['stars'] as num)
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: context.neon.gold,
                    size: 32)
            ]),
            if (career) ...[
              const SizedBox(height: 12),
              Text('Personal best: ${score['personalBest']} / 100',
                  style: TextStyle(
                      color: context.neon.gold, fontWeight: FontWeight.w800)),
              if (score['newBest'] == true) const Text('New personal best! ✨'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(
                    shape: const StadiumBorder(),
                    avatar: const Icon(Icons.monetization_on_rounded, size: 18),
                    label: Text('+${score['coinsEarned']} coins')),
                Chip(
                    shape: const StadiumBorder(),
                    avatar: const Icon(Icons.bolt_rounded, size: 18),
                    label: Text('+${score['xpEarned']} XP')),
              ]),
              if (score['milestonePassed'] == false)
                Text(
                    'Aim for ${score['minimumScore']} to clear this finale. Your best is saved—try again!',
                    textAlign: TextAlign.center),
            ],
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
                career
                    ? (score['preview'] == true
                        ? 'Preview career rewards use test coins and XP.'
                        : 'Rewards count your best stars. Replays earn only improvements.')
                    : score['preview'] == true
                        ? 'Preview score — no coins or XP awarded.'
                        : 'Coins and XP are awarded once per theme each day.',
                style: TextStyle(color: context.neon.mute, fontSize: 12)),
            const SizedBox(height: 20),
            if (career) ...[
              SizedBox(
                  width: double.infinity,
                  child: SlayButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Back to my career'))),
              const SizedBox(height: 10)
            ],
            SizedBox(
                width: double.infinity,
                child: career
                    ? SlayButton.tonal(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Try again'))
                    : SlayButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Back to the studio'))),
          ])));
}
