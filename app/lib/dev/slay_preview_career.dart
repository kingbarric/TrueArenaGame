import 'slay_preview_scoring.dart';

/// Fixture counterpart of the career endpoints. Never used in production.
class SlayPreviewCareer {
  SlayPreviewCareer(this.content, this.catalog);
  final Map<String, dynamic> content, catalog;
  final Map<String, Map<String, dynamic>> bests = {};
  int xp = 0;
  int stars(num score) => score >= 90
      ? 5
      : score >= 80
          ? 4
          : score >= 65
              ? 3
              : score >= 50
                  ? 2
                  : 1;
  List<Map<String, dynamic>> get challenges => (content['challenges'] as List)
      .map((c) => Map<String, dynamic>.from(c))
      .toList();
  Map<String, dynamic> challenge(String id, DateTime day) => id == 'daily'
      ? challenges[
          (day.difference(DateTime.utc(1970)).inDays) % challenges.length]
      : challenges.firstWhere((c) => c['id'] == id);
  String period(DateTime day) => day.toIso8601String().substring(0, 10);
  Map<String, dynamic> theme(Map<String, dynamic> c) => {
        'id': c['id'],
        'title': c['title'],
        'description': c['brief'],
        'styleTags': c['styleTags'],
        'requiredCategories': c['requiredCategories'],
        'optionalCategories': ['watches', 'bags', 'jewellery', 'accessories'],
        'bodyEligibility': ['female', 'male'],
        'systemWeight': 1,
        'stylingSeconds': 0,
        'budget': null,
      };
  Map<String, dynamic> event(Map<String, dynamic> c, bool unlocked, String p) {
    final best = bests['${c['id']}:$p'];
    return {
      ...c,
      'theme': theme(c),
      'unlocked': unlocked,
      'personalBest': best?['score'],
      'stars': best == null ? 0 : stars(best['score']),
      'completed': best != null && best['score'] >= c['minimumScore']
    };
  }

  Map<String, dynamic> home(DateTime now) {
    final day = DateTime.utc(now.year, now.month, now.day);
    final events = challenges.map((c) => event(c, true, 'career')).toList();
    final completed = events.where((e) => e['completed'] == true).toList();
    final totalStars =
        completed.fold<int>(0, (n, e) => n + (e['stars'] as int));
    final ranks = (content['ranks'] as List).cast<Map>();
    int rank = 0;
    for (int i = 1; i < ranks.length; i++) {
      final r = ranks[i];
      if (xp >= r['minimumXp'] &&
          completed.length >= r['minimumCompleted'] &&
          totalStars >= r['minimumStars'] &&
          completed.any((e) => e['id'] == r['milestone'])) {
        rank = i;
      } else {
        break;
      }
    }
    for (final e in events) {
      e['unlocked'] = rank >= e['chapter'];
    }
    int streak = 0;
    var cursor = bests.keys.any((k) => k.endsWith(':${period(day)}'))
        ? day
        : day.subtract(const Duration(days: 1));
    while (bests.keys.any((k) => k.endsWith(':${period(cursor)}'))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    final daily = event(challenge('daily', day), true, period(day));
    daily['completed'] = daily['personalBest'] != null;
    daily['minimumScore'] = 0;
    return {
      'xp': xp,
      'level': 1 + xp ~/ 100,
      'levelXp': xp % 100,
      'rankIndex': rank,
      'rank': ranks[rank],
      'nextRank': rank + 1 < ranks.length ? ranks[rank + 1] : null,
      'events': events,
      'totalStars': totalStars,
      'completed': completed.length,
      'daily': daily,
      'dailyEndsAt': day.add(const Duration(days: 1)).toIso8601String(),
      'streak': streak
    };
  }

  Map<String, dynamic> score(
      String id, Map<String, dynamic> look, DateTime now) {
    final day = DateTime.utc(now.year, now.month, now.day),
        c = challenge(id, now);
    if (id != 'daily' &&
        (home(now)['rankIndex'] as int) < (c['chapter'] as int)) {
      throw StateError(
          'Complete the previous career chapter to unlock this event');
    }
    final judged = scoreSlayPreview(look, theme(c), catalog),
        p = id == 'daily' ? period(day) : 'career',
        key = '${c['id']}:$p';
    final old = bests[key],
        previous = old?['score'] ?? -1,
        score = judged['overall'] as num;
    final best = score > previous ? score : previous,
        passed = id == 'daily' || best >= c['minimumScore'];
    final coins = passed ? (id == 'daily' ? 100 : 50) + 25 * stars(best) : 0,
        points = passed ? 40 + 20 * stars(best) : 0;
    final coinGain = coins - (old?['coins'] ?? 0),
        xpGain = points - (old?['xp'] ?? 0);
    xp += xpGain as int;
    bests[key] = {'score': best, 'coins': coins, 'xp': points};
    return {
      ...judged,
      'stars': stars(score),
      'starCount': 5,
      'personalBest': best,
      'newBest': score > previous,
      'coinsEarned': coinGain,
      'xpEarned': xpGain,
      'milestonePassed': passed,
      'minimumScore': c['minimumScore'],
      'career': home(now),
      'preview': true
    };
  }
}
