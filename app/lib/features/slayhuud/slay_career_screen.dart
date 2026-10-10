import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import 'slay_game_menu.dart';
import 'slay_models.dart';
import 'slay_studio_screen.dart';
import 'slay_theme.dart';

class SlayCareerScreen extends StatefulWidget {
  const SlayCareerScreen(
      {super.key, required this.catalog, required this.owned});
  final Map<String, dynamic> catalog;
  final Set<String> owned;
  @override
  State<SlayCareerScreen> createState() => _SlayCareerScreenState();
}

class _SlayCareerScreenState extends State<SlayCareerScreen> {
  Map<String, dynamic>? _career;
  late Set<String> _owned = {...widget.owned};
  String? _error;
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final api = SlayApi(AppScope.of(context).api);
      final data = await Future.wait([api.career(), api.profile()]);
      if (!mounted) return;
      setState(() {
        _career = data[0];
        _owned = Set<String>.from(data[1]['owned']);
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Your career could not load. Let’s try again.');
      }
    }
  }

  List<Map<String, dynamic>> get _events => (_career!['events'] as List)
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  Future<void> _brief(Map<String, dynamic> event, {bool daily = false}) async {
    String body = 'female';
    final dailyPeriod = daily
        ? DateTime.parse(_career!['dailyEndsAt'])
            .toUtc()
            .subtract(const Duration(days: 1))
            .toIso8601String()
            .substring(0, 10)
        : null;
    final begin = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.neon.bg,
      builder: (c) => Theme(
          data: slayTheme(c),
          child: StatefulBuilder(
              builder: (c, update) => SafeArea(
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SlayLabel(
                                  daily ? 'DAILY SLAY' : event['chapterTitle']),
                              const SizedBox(height: 8),
                              Text(event['title'],
                                  style: Theme.of(c).textTheme.headlineMedium),
                              const SizedBox(height: 12),
                              Text(event['brief']),
                              const SizedBox(height: 16),
                              Wrap(spacing: 6, runSpacing: 6, children: [
                                for (final tag in event['theme']['styleTags'])
                                  Chip(label: Text(tag.toString())),
                              ]),
                              const SizedBox(height: 12),
                              const SlayLabel('Your checklist'),
                              const SizedBox(height: 8),
                              for (final item in event['theme']
                                  ['requiredCategories'])
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(children: [
                                      Icon(Icons.check_circle_outline_rounded,
                                          size: 18, color: c.neon.gold),
                                      const SizedBox(width: 8),
                                      Flexible(
                                          child: Text(item == 'outfit'
                                              ? 'Complete outfit or top + bottoms'
                                              : item.toString())),
                                    ])),
                              const SizedBox(height: 8),
                              Text(event['bonus'],
                                  style: TextStyle(color: c.neon.mute)),
                              if ((event['minimumScore'] as num) > 0 &&
                                  !daily) ...[
                                const SizedBox(height: 12),
                                Text(
                                    'Milestone: score ${event['minimumScore']} or more to clear it.',
                                    style: TextStyle(color: c.neon.gold)),
                              ],
                              const SizedBox(height: 16),
                              SlayPanel(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    const SlayLabel('Make it count'),
                                    const SizedBox(height: 6),
                                    Text(
                                        'Up to ${daily ? 225 : 175} coins · 140 XP',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 5),
                                    Text(
                                        'Earn rewards for your best performance. Improve your stars to earn the difference.',
                                        style: TextStyle(
                                            fontSize: 12, color: c.neon.mute)),
                                    if (event['personalBest'] != null)
                                      Text(
                                          'Your best: ${event['personalBest']} / 100',
                                          style: TextStyle(color: c.neon.gold)),
                                  ])),
                              const SizedBox(height: 16),
                              Wrap(spacing: 8, children: [
                                SlayPill(
                                    label: 'Her',
                                    icon: Icons.female,
                                    selected: body == 'female',
                                    onPressed: () =>
                                        update(() => body = 'female')),
                                SlayPill(
                                    label: 'Him',
                                    icon: Icons.male,
                                    selected: body == 'male',
                                    onPressed: () =>
                                        update(() => body = 'male')),
                              ]),
                              const SizedBox(height: 12),
                              SizedBox(
                                  width: double.infinity,
                                  child: SlayButton.icon(
                                      onPressed: () => Navigator.pop(c, true),
                                      icon: const Icon(
                                          Icons.auto_awesome_rounded),
                                      label: const Text('Let’s style!'))),
                            ])),
                  ))),
    );
    if (begin != true || !mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => SlayStudioScreen(
                  catalog: widget.catalog,
                  theme: Map<String, dynamic>.from(event['theme']),
                  owned: _owned,
                  initialBody: body,
                  careerEventId: daily ? 'daily' : event['id'],
                  initialBackground: event['location'],
                  careerPeriod: dailyPeriod,
                )));
    if (mounted) await _load();
  }

  void _locked(Map<String, dynamic> event) {
    final next = _career!['nextRank'];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.neon.bg,
      builder: (c) => SafeArea(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_rounded, color: c.neon.gold),
                    const SizedBox(height: 8),
                    Text('${event['chapterTitle']} is up ahead!',
                        style: Theme.of(c).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                        'Clear your current chapter finale and keep improving your best stars.'),
                    if (next != null) ...[
                      const SizedBox(height: 10),
                      Text(
                          'Next title: ${next['name']}\n${next['minimumXp']} XP · ${next['minimumCompleted']} events · ${next['minimumStars']} best stars')
                    ],
                    const SizedBox(height: 16),
                    SlayButton(
                        onPressed: () {
                          Navigator.pop(c);
                          setState(() => _tab = 1);
                        },
                        child: const Text('Show my journey')),
                  ]))),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: slayTheme(context),
      child: Builder(
          builder: (c) => Scaffold(
                appBar: AppBar(
                    title: const Text('My slay career'),
                    actions: [SlayGameMenu(onExit: () => leaveSlayScreen(c))]),
                bottomNavigationBar: NavigationBar(
                    selectedIndex: _tab,
                    onDestinationSelected: (v) => setState(() => _tab = v),
                    backgroundColor: c.neon.panel,
                    indicatorColor: c.neon.gold.withValues(alpha: .22),
                    destinations: const [
                      NavigationDestination(
                          icon: Icon(Icons.home_rounded), label: 'Career'),
                      NavigationDestination(
                          icon: Icon(Icons.route_rounded), label: 'Journey'),
                      NavigationDestination(
                          icon: Icon(Icons.bolt_rounded), label: 'Daily Slay'),
                    ]),
                body: _error != null
                    ? Center(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.cloud_off_rounded, size: 36),
                                  const SizedBox(height: 12),
                                  Text(_error!, textAlign: TextAlign.center),
                                  const SizedBox(height: 12),
                                  SlayButton(
                                      onPressed: _load,
                                      child: const Text('Try again')),
                                ])))
                    : _career == null
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                                key: ValueKey(_tab),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 24),
                                children: _tab == 0
                                    ? _home(c)
                                    : _tab == 1
                                        ? _journey(c)
                                        : _daily(c)),
                          ),
              )));
  Widget _stars(BuildContext c, int stars) => Semantics(
      label: '$stars out of 5 stars',
      child: ExcludeSemantics(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < 5; i++)
          Icon(i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
              color: c.neon.gold, size: 18),
      ])));
  Widget _stat(BuildContext c, IconData icon, String text) => Chip(
      avatar: Icon(icon, size: 16, color: c.neon.gold),
      shape: const StadiumBorder(),
      visualDensity: VisualDensity.compact,
      label: Text(text, style: const TextStyle(fontSize: 12)));
  List<Widget> _home(BuildContext c) {
    final s = _career!,
        next = _events
            .where((e) => e['unlocked'] == true && e['completed'] != true)
            .firstOrNull;
    final last = _events
        .where((e) => e['personalBest'] != null)
        .toList()
        .reversed
        .take(2);
    return [
      Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: c.neon.gold, width: 2),
              gradient: LinearGradient(colors: [
                Color.alphaBlend(
                    c.neon.gold.withValues(alpha: .20), c.neon.panel),
                c.neon.panel
              ]),
              boxShadow: [
                BoxShadow(
                    color: c.neon.gold.withValues(alpha: .25),
                    offset: const Offset(0, 5))
              ]),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.auto_awesome_rounded, color: c.neon.gold, size: 24),
              const SizedBox(width: 8),
              const Expanded(child: SlayLabel('YOUR FASHION STORY'))
            ]),
            const SizedBox(height: 12),
            Text(s['rank']['name'],
                style: Theme.of(c).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('Level ${s['level']} · ${s['xp']} career XP',
                style: TextStyle(fontSize: 13, color: c.neon.mute)),
            const SizedBox(height: 14),
            ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                    value: (s['levelXp'] as num) / 100,
                    minHeight: 10,
                    color: c.neon.gold,
                    backgroundColor: c.neon.plate)),
            const SizedBox(height: 8),
            Text('${s['levelXp']} / 100 XP to your next level',
                style: TextStyle(fontSize: 12, color: c.neon.mute)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _stat(c, Icons.star_rounded, '${s['totalStars']} stars'),
              _stat(c, Icons.check_circle_rounded,
                  '${s['completed']} / ${_events.length}'),
              _stat(c, Icons.local_fire_department_rounded,
                  '${s['streak']} days'),
            ]),
            const SizedBox(height: 8),
            SlayButton.tonal(
                compact: true,
                onPressed: () => setState(() => _tab = 1),
                child: const Text('Explore my journey →')),
          ])),
      const SizedBox(height: 22),
      Text(next == null ? 'Make your best even better' : 'Your next moment',
          style: Theme.of(c).textTheme.titleLarge),
      const SizedBox(height: 10),
      _eventCard(c, next ?? _events.first, featured: true),
      const SizedBox(height: 20),
      ..._daily(c, compact: true),
      if (last.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('Your best looks', style: Theme.of(c).textTheme.titleLarge),
        const SizedBox(height: 10),
        for (final e in last) _eventCard(c, e)
      ],
      const SizedBox(height: 16),
      Text(
          'Best stars count once per career event. Replay to beat your score and unlock your next chapter.',
          style: TextStyle(color: c.neon.mute, fontSize: 12)),
    ];
  }

  List<Widget> _journey(BuildContext c) => [
        Text('Small steps. Big slay.',
            style: Theme.of(c).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text('Follow the path, clear each finale and earn your next title.',
            style: TextStyle(color: c.neon.mute)),
        const SizedBox(height: 20),
        for (int chapter = 0; chapter < 5; chapter++) ...[
          Row(children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: c.neon.gold.withValues(alpha: .15),
                    shape: BoxShape.circle),
                child: Icon(
                    [
                      Icons.checkroom_rounded,
                      Icons.location_city_rounded,
                      Icons.nightlife_rounded,
                      Icons.diamond_rounded,
                      Icons.emoji_events_rounded
                    ][chapter],
                    color: c.neon.gold)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                    _events.firstWhere(
                        (e) => e['chapter'] == chapter)['chapterTitle'],
                    style: Theme.of(c).textTheme.titleMedium))
          ]),
          const SizedBox(height: 10),
          for (final event in _events.where((e) => e['chapter'] == chapter))
            _eventCard(c, event),
          const SizedBox(height: 16),
        ],
      ];
  List<Widget> _daily(BuildContext c, {bool compact = false}) {
    final event = Map<String, dynamic>.from(_career!['daily']);
    final end = DateTime.parse(_career!['dailyEndsAt']).toLocal();
    return [
      Text('Daily Slay', style: Theme.of(c).textTheme.titleLarge),
      const SizedBox(height: 6),
      Text('A fresh brief. One more chance to shine.',
          style: TextStyle(color: c.neon.mute)),
      const SizedBox(height: 10),
      _eventCard(c, event, daily: true, featured: true),
      const SizedBox(height: 8),
      Text(
          'Refreshes at ${TimeOfDay.fromDateTime(end).format(c)} · Your daily best earns rewards.',
          style: TextStyle(color: c.neon.mute, fontSize: 12)),
      if (!compact) ...[
        const SizedBox(height: 20),
        SlayPanel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SlayLabel('YOUR REPLAY GOAL'),
          const SizedBox(height: 8),
          Text(
              event['personalBest'] == null
                  ? 'Set your first personal best today.'
                  : 'Can you beat ${event['personalBest']} / 100?',
              style: Theme.of(c).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
              'Play at your own pace. Choose your pose, walk the runway, then see what worked and what to improve.'),
        ]))
      ],
    ];
  }

  Widget _eventCard(BuildContext c, Map<String, dynamic> e,
      {bool featured = false, bool daily = false}) {
    final unlocked = e['unlocked'] == true,
        complete = e['completed'] == true,
        milestone = (e['minimumScore'] as num) > 0 && !daily;
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SlayPanel(
            colour: featured ? c.neon.gold : null,
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: (unlocked ? c.neon.gold : c.neon.mute)
                            .withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(16)),
                    child: Icon(
                        !unlocked
                            ? Icons.lock_rounded
                            : complete
                                ? Icons.check_rounded
                                : milestone
                                    ? Icons.emoji_events_rounded
                                    : Icons.auto_awesome_rounded,
                        color: unlocked ? c.neon.gold : c.neon.mute)),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      if (milestone)
                        SlayLabel('CHAPTER FINALE', colour: c.neon.gold),
                      Text(e['title'],
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      if (e['personalBest'] != null)
                        Text('Best ${e['personalBest']} / 100',
                            style: TextStyle(fontSize: 12, color: c.neon.mute)),
                    ])),
              ]),
              if (featured) ...[
                const SizedBox(height: 10),
                Text(e['brief'],
                    style: TextStyle(fontSize: 13, color: c.neon.mute))
              ],
              const SizedBox(height: 10),
              Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _stars(c, (e['stars'] as num).toInt()),
                    SlayButton.tonal(
                        key: ValueKey(
                            'brief-${e['id']}-${daily ? 'daily' : 'career'}'),
                        compact: true,
                        colour: featured ? c.neon.gold : null,
                        onPressed: () =>
                            unlocked ? _brief(e, daily: daily) : _locked(e),
                        child: Text(!unlocked
                            ? 'How to unlock'
                            : complete
                                ? 'Beat my best'
                                : 'View brief →')),
                  ]),
            ])));
  }
}
