import 'slay_preview_scoring.dart';

/// Fixture counterpart of the career endpoints. Never used in production.
class SlayPreviewCareer {
  SlayPreviewCareer(this.content, this.catalog);
  final Map<String, dynamic> content, catalog;
  final Map<String, Map<String, dynamic>> bests = {};
  int xp = 0;
  Map<String, dynamic>? character;
  final Set<String> granted = {};
  List<Map<String, dynamic>> get chapters => (content['chapters'] as List)
      .map((c) => Map<String, dynamic>.from(c))
      .toList();
  List<String> _list(Map c, String body, [String? pool]) => List<String>.from(
      (pool == null ? c['collection'][body] : c['rewards'][body][pool]) ??
          const []);
  Set<String> careerItems(String body, int rank) => {
        for (final c in chapters.where((c) => c['chapter'] <= rank)) ...[
          ..._list(c, body),
          ..._list(c, body, 'four').where(granted.contains),
          ..._list(c, body, 'five').where(granted.contains),
        ]
      };
  List<String> poses(int rank) => [
        for (final c in chapters.where((c) => c['chapter'] <= rank))
          ...List<String>.from(c['poses'])
      ];
  Map<String, String> locks(String body, int rank) {
    final open = careerItems(body, rank), locks = <String, String>{};
    for (final c in chapters) {
      for (final id in _list(c, body)) {
        if (!open.contains(id)) {
          locks.putIfAbsent(id, () => 'Opens at ${c['title']}');
        }
      }
      for (final (pool, stars) in [('four', 4), ('five', 5)]) {
        for (final id in _list(c, body, pool)) {
          if (!open.contains(id)) {
            locks.putIfAbsent(id, () => 'Earn $stars★ in ${c['title']}');
          }
        }
      }
    }
    return locks;
  }

  Map<String, dynamic> start(String body, String? avatarId) {
    if (character != null) {
      throw StateError('Your career character is already chosen');
    }
    character = {'body': body, 'avatarId': avatarId ?? body};
    return home(DateTime.now().toUtc());
  }

  Map<String, dynamic> chooseCharacter(String body, String avatarId) {
    if (character == null) throw StateError('Start your career first');
    if (!(catalog['avatars'] as List)
        .any((a) => a['body'] == body && (a['id'] ?? a['body']) == avatarId)) {
      throw StateError('Choose an available character');
    }
    character = {'body': body, 'avatarId': avatarId};
    return home(DateTime.now().toUtc());
  }

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
      'streak': streak,
      'chapters': [
        for (final c in chapters)
          {
            'chapter': c['chapter'],
            'title': c['title'],
            'location': c['location'],
            'room': c['room'],
            'venue': c['venue'],
            'unlocked': rank >= c['chapter']
          }
      ],
      'character': character == null
          ? null
          : {
              ...character!,
              'items': careerItems(character!['body'], rank).toList(),
              'poses': poses(rank),
              'locks': locks(character!['body'], rank),
            },
    };
  }

  /// A few fixture rivals so the preview's standings have someone to beat.
  Map<String, dynamic> leaderboard(String id, DateTime now) {
    final c = challenge(id, now), p = id == 'daily' ? period(now) : 'career';
    final mine = bests['${c['id']}:$p']?['score'] as num?;
    final rows = [
      {'username': 'adaeze_styles', 'score': 94.0, 'me': false},
      {'username': 'kofi.fits', 'score': 88.5, 'me': false},
      {'username': 'zara_glow', 'score': 76.0, 'me': false},
      if (mine != null)
        {'username': 'you', 'score': mine.toDouble(), 'me': true},
    ]..sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    final position = rows.indexWhere((r) => r['me'] == true) + 1;
    return {
      'challengeId': c['id'],
      'title': c['title'],
      'period': p,
      'personalBest': mine,
      'friendsRank': position == 0 ? null : position,
      'friends': rows,
      'global': {
        'total': 1240,
        'rank': mine == null ? null : (1240 * (1 - mine / 110)).round(),
        'topPercent': mine == null ? null : (100 * (1 - mine / 110)).ceil(),
        'top': rows.take(3).toList()
      }
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
    final rankBefore = home(now)['rankIndex'] as int;
    final previousStars = old == null ? 0 : stars(old['score']);
    final unlocked = <Map<String, dynamic>>[];
    if (id != 'daily' && character != null) {
      final chapter =
          chapters.firstWhere((ch) => ch['chapter'] == c['chapter']);
      for (final (tier, pool) in [(4, 'four'), (5, 'five')]) {
        if (previousStars < tier && stars(best) >= tier) {
          final next = _list(chapter, character!['body'], pool)
              .where((i) => !granted.contains(i))
              .firstOrNull;
          if (next != null) {
            granted.add(next);
            final item =
                (catalog['items'] as List).firstWhere((i) => i['id'] == next);
            unlocked.add({
              'id': next,
              'name': item['name'],
              'category': item['category'],
              'thumbnailUrl': item['thumbnailUrl']
            });
          }
        }
      }
    }
    xp += xpGain as int;
    bests[key] = {'score': best, 'coins': coins, 'xp': points};
    final after = home(now), rank = after['rankIndex'] as int;
    final chapter = rank > rankBefore
        ? chapters.firstWhere((ch) => ch['chapter'] == rank)
        : null;
    return {
      'unlocked': unlocked,
      'rankUp': chapter == null
          ? null
          : {
              'rank': (content['ranks'] as List)[rank]['name'],
              'chapter': chapter['title'],
              'location': chapter['location'],
              'room': chapter['room'],
              'venue': chapter['venue'],
              'poses': chapter['poses'],
              'items': [
                if (character != null)
                  for (final id in _list(chapter, character!['body']))
                    {
                      'id': id,
                      'name': (catalog['items'] as List)
                          .firstWhere((i) => i['id'] == id)['name']
                    }
              ]
            },
      'ranking': leaderboard(id, now),
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
