import 'package:flutter/material.dart';

import '../../theme/neon_theme.dart';
import '../../widgets/fireworks.dart';
import 'slay_theme.dart';
import 'slay_ui.dart';

/// The judged-look moment. Pops `true` to move on, `false` to keep styling.
class SlayResultsScreen extends StatelessWidget {
  const SlayResultsScreen(
      {super.key,
      required this.score,
      required this.title,
      this.location,
      this.career = false});
  final Map<String, dynamic> score;
  final String title;
  final String? location;
  final bool career;

  static Future<bool?> show(BuildContext context,
          {required Map<String, dynamic> score,
          required String title,
          String? location,
          bool career = false}) =>
      Navigator.of(context).push<bool>(PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, __, ___) => SlayResultsScreen(
            score: score, title: title, location: location, career: career),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
                scale: Tween(begin: .94, end: 1.0).animate(CurvedAnimation(
                    parent: animation, curve: Curves.easeOutBack)),
                child: child)),
      ));

  static String headline(int stars, int of) {
    final level = of == 5 ? stars : (stars / of * 5).round();
    return switch (level) {
      5 => 'SLAY! Total icon',
      4 => 'Serving looks!',
      3 => 'Cute! Almost there',
      2 => 'You made an impression',
      _ => 'Back to the mirror',
    };
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon, stage = SlayStageLook.of(location);
    final overall = (score['overall'] as num).round();
    final of = (score['starCount'] as num?)?.toInt() ?? 3;
    final stars = (score['stars'] as num).toInt();
    final celebrate = stars >= (of == 5 ? 4 : 3);
    final unlocked = (score['unlocked'] as List? ?? const [])
        .map((u) => Map<String, dynamic>.from(u))
        .toList();
    final rankUp = score['rankUp'] == null
        ? null
        : Map<String, dynamic>.from(score['rankUp']);
    final ranking = score['ranking'] == null
        ? null
        : Map<String, dynamic>.from(score['ranking']);
    final milestoneMissed = career && score['milestonePassed'] == false;
    final (worked, improve) = _feedback(score);
    final coins = (score['coinsEarned'] as num?)?.toInt() ?? 0,
        xp = (score['xpEarned'] as num?)?.toInt() ?? 0;

    return Theme(
      data: slayTheme(context),
      child: Scaffold(
        backgroundColor: n.bg,
        body: Stack(children: [
          Positioned.fill(
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                stage.from.withValues(alpha: .55),
                n.bg,
                n.bg
              ])))),
          const Positioned.fill(child: SlaySparkles(count: 34)),
          if (celebrate)
            Positioned.fill(
                child: Fireworks(
                    colors: [n.gold, n.brand, stage.to, Colors.white])),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              children: [
                Text(title.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: n.mid,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                        fontSize: 12)),
                const SizedBox(height: 6),
                Center(child: SlayHeadline(headline(stars, of), size: 30)),
                const SizedBox(height: 14),
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: overall.toDouble()),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 1100),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: '${v.round()}',
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(
                                    fontSize: 84,
                                    fontWeight: FontWeight.w900,
                                    color: n.ink,
                                    height: 1)),
                        TextSpan(
                            text: ' /100',
                            style: TextStyle(
                                color: n.mute,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                      ]),
                      semanticsLabel: '$overall out of 100',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                    child: SlayStars(stars, of: of, size: 40, animate: true)),
                if (score['newBest'] == true && career)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                          color: n.gold,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: kCabinetInk, width: 2)),
                      child: Text('🏆 NEW PERSONAL BEST',
                          style: TextStyle(
                              color: n.onAccent,
                              fontWeight: FontWeight.w900,
                              fontSize: 12)),
                    ),
                  ),
                if (score['preview'] == true && !career)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Preview score — no coins or XP awarded.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: n.mute, fontSize: 12)),
                  ),
                if (milestoneMissed) ...[
                  const SizedBox(height: 14),
                  _Note(
                      '👑 The finale needs ${score['minimumScore']}+ to open the next stage. '
                      'You made an impression, now polish the look and go again!'),
                ],
                if (rankUp != null) ...[
                  const SizedBox(height: 16),
                  _RankUp(rankUp),
                ],
                const SizedBox(height: 16),
                SlayCabinet(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (label, key, emoji) in [
                          ('Theme fit', 'themeFit', '🎯'),
                          ('Must-wears', 'requirements', '✅'),
                          ('Colours', 'colour', '🎨'),
                          ('Complete look', 'completeness', '👠'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(children: [
                              SizedBox(width: 26, child: Text(emoji)),
                              SizedBox(
                                  width: 104,
                                  child: Text(label,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13))),
                              Expanded(
                                  child: SlayXpBar(
                                      value: ((score[key] as num?) ?? 0) / 100,
                                      height: 12,
                                      colour: ((score[key] as num?) ?? 0) >= 80
                                          ? n.jade
                                          : n.gold)),
                              SizedBox(
                                  width: 36,
                                  child: Text(
                                      '${((score[key] as num?) ?? 0).round()}',
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900))),
                            ]),
                          ),
                        if (worked.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('WHAT WORKED',
                              style: TextStyle(
                                  color: n.jade,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  letterSpacing: 1.1)),
                          for (final line in worked) _Bullet('💚', line),
                        ],
                        if (improve.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('NEXT TIME',
                              style: TextStyle(
                                  color: n.gold,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  letterSpacing: 1.1)),
                          for (final line in improve) _Bullet('💡', line),
                        ],
                      ]),
                ),
                if (career) ...[
                  const SizedBox(height: 14),
                  Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (coins > 0)
                          SlayStatChip(
                              icon: Icons.monetization_on_rounded,
                              label: '+$coins coins'),
                        if (xp > 0)
                          SlayStatChip(
                              icon: Icons.bolt_rounded,
                              label: '+$xp XP',
                              colour: n.brand),
                        if (ranking?['friendsRank'] != null)
                          SlayStatChip(
                              icon: Icons.people_alt_rounded,
                              label: '#${ranking!['friendsRank']} with friends',
                              colour: n.jade),
                        if (ranking?['global']?['topPercent'] != null)
                          SlayStatChip(
                              icon: Icons.public_rounded,
                              label:
                                  'Top ${ranking!['global']['topPercent']}% worldwide',
                              colour: n.brand),
                        if (score['personalBest'] != null)
                          SlayStatChip(
                              icon: Icons.emoji_events_rounded,
                              label:
                                  'Best ${(score['personalBest'] as num).round()}'),
                      ]),
                  if (coins == 0 && xp == 0 && !milestoneMissed)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                          'Rewards for this score are already yours. Beat your best for more!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: n.mute, fontSize: 12)),
                    ),
                ],
                if (unlocked.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Center(
                      child: SlayHeadline('New in your wardrobe!', size: 20)),
                  const SizedBox(height: 10),
                  Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final item in unlocked) _Unlocked(item),
                      ]),
                ],
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(
                      child: SlayButton.tonal(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(career ? 'Try again' : 'Keep styling'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: SlayButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(career ? 'Continue' : 'Done'))),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  /// Splits the judge's notes into short "worked" and "next time" lists.
  static (List<String>, List<String>) _feedback(Map<String, dynamic> score) {
    num of(String key) => (score[key] as num?) ?? 0;
    final worked = <String>[
      if (of('themeFit') >= 85) 'Spot-on for the dress code',
      if (of('requirements') >= 100) 'Every must-wear is on',
      if (of('colour') >= 85) 'Your colours work together',
      if (of('completeness') >= 100) 'A complete head-to-toe look',
    ];
    final improve = (score['feedback'] as List? ?? const [])
        .map((f) => f.toString())
        .where((f) =>
            !f.startsWith('Your outfit, required items and palette match'))
        .toList();
    return (worked.take(2).toList(), improve.take(2).toList());
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.emoji, this.text);
  final String emoji, text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13.5, height: 1.3))),
        ]),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => SlayCabinet(
      colour: context.neon.gold.withValues(alpha: .18),
      padding: const EdgeInsets.all(12),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)));
}

class _RankUp extends StatelessWidget {
  const _RankUp(this.rankUp);
  final Map<String, dynamic> rankUp;
  @override
  Widget build(BuildContext context) {
    final stage = SlayStageLook.of(rankUp['location']);
    final items = (rankUp['items'] as List? ?? const []).length;
    final poses = (rankUp['poses'] as List? ?? const []).length;
    return SlayCabinet(
      gradient: stage.gradient,
      child: Column(children: [
        Text('🎉 RANK UP',
            style: TextStyle(
                color: stage.ink,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4)),
        SlayHeadline('You’re a ${rankUp['rank']}!',
            size: 26, colour: stage.ink),
        const SizedBox(height: 6),
        Text(
            '${rankUp['chapter']} is open: ${rankUp['room']} → ${rankUp['venue']}.'
            '${items > 0 ? ' $items new pieces' : ''}${poses > 0 ? '${items > 0 ? ' and' : ''} $poses new pose${poses > 1 ? 's' : ''}' : ''}.',
            textAlign: TextAlign.center,
            style: TextStyle(color: stage.ink, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _Unlocked extends StatelessWidget {
  const _Unlocked(this.item);
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(
            begin: MediaQuery.disableAnimationsOf(context) ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: const Interval(.4, 1, curve: Curves.elasticOut),
        builder: (_, t, child) => Transform.scale(scale: t, child: child),
        child: SizedBox(
          width: 108,
          child: SlayCabinet(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              SizedBox(
                  height: 70,
                  child: item['thumbnailUrl'] == null
                      ? Center(
                          child: Text(
                              slayCategoryEmoji[item['category']] ?? '✨',
                              style: const TextStyle(fontSize: 36)))
                      : SlayThumbnail(url: item['thumbnailUrl'])),
              const SizedBox(height: 4),
              Text('NEW!',
                  style: TextStyle(
                      color: context.neon.brand,
                      fontWeight: FontWeight.w900,
                      fontSize: 11)),
              Text(item['name'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );
}
