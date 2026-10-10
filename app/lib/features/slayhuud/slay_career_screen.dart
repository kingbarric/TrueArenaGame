import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import 'slay_game_menu.dart';
import 'slay_models.dart';
import 'slay_stage.dart';
import 'slay_studio_screen.dart';
import 'slay_theme.dart';
import 'slay_ui.dart';

/// Emoji for wardrobe categories, used on briefs and rewards.
const slayCategoryEmoji = {
  'outfit': '👗',
  'dress': '👗',
  'tops': '👚',
  'shirts': '👕',
  'trousers': '👖',
  'skirts': '🩱',
  'shoes': '👠',
  'watches': '⌚',
  'bags': '👜',
  'jewellery': '💍',
  'accessories': '✨',
  'makeup': '💄',
  'hair': '💇',
  'eyes': '👁️',
};

String slayCategoryName(String category) => switch (category) {
      'outfit' => 'A full outfit',
      'jewellery' => 'Jewellery',
      'watches' => 'A watch',
      'bags' => 'A bag',
      'shoes' => 'Shoes',
      _ => category[0].toUpperCase() + category.substring(1),
    };

/// Solo career: pick your star once, then climb from Starter Studio to Global Star.
class SlayCareerScreen extends StatefulWidget {
  const SlayCareerScreen(
      {super.key, required this.catalog, required this.owned});
  final Map<String, dynamic> catalog;
  final Set<String> owned;
  @override
  State<SlayCareerScreen> createState() => _SlayCareerScreenState();
}

class _SlayCareerScreenState extends State<SlayCareerScreen> {
  Map<String, dynamic>? _career, _dailyRanking;
  String? _error;
  late Set<String> _owned = {...widget.owned};

  SlayApi get _api => SlayApi(AppScope.of(context).api);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_api.career(), _api.profile()]);
      if (!mounted) return;
      setState(() {
        _career = results[0];
        _owned = Set<String>.from(results[1]['owned'] ?? _owned);
        _error = null;
      });
      if (_career!['character'] != null) {
        final ranking = await _api.careerLeaderboard('daily');
        if (mounted) setState(() => _dailyRanking = ranking);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Your career could not load.');
    }
  }

  Map<String, dynamic>? get _character => _career?['character'] == null
      ? null
      : Map<String, dynamic>.from(_career!['character']);

  List<Map<String, dynamic>> get _events => (_career!['events'] as List)
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  Future<void> _play(Map<String, dynamic> event, {bool daily = false}) async {
    if (event['unlocked'] != true) return;
    final go = await showSlayInvite(context, event, daily: daily);
    if (go != true || !mounted) return;
    final character = _character!;
    final period = daily
        ? DateTime.parse(_career!['dailyEndsAt'])
            .toUtc()
            .subtract(const Duration(days: 1))
            .toIso8601String()
            .substring(0, 10)
        : null;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => SlayStudioScreen(
                  catalog: widget.catalog,
                  theme: Map<String, dynamic>.from(event['theme']),
                  owned: _owned,
                  initialBody: character['body'],
                  careerEventId: daily ? 'daily' : event['id'],
                  careerPeriod: period,
                  careerCharacter: character,
                  initialBackground: event['location'],
                )));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Theme(
      data: slayTheme(context),
      child: Scaffold(
        backgroundColor: n.bg,
        body: Stack(children: [
          const Positioned.fill(child: SlaySparkles()),
          SafeArea(
            child: _career == null
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_error!),
                            const SizedBox(height: 12),
                            SlayButton(
                                onPressed: _load,
                                child: const Text('Try again')),
                          ]))
                : _character == null
                    ? SlayCharacterPicker(
                        catalog: widget.catalog,
                        onChosen: (body, avatarId) async {
                          final career = await _api.careerStart(body, avatarId);
                          if (mounted) setState(() => _career = career);
                          _load();
                        })
                    : _home(context),
          ),
        ]),
      ),
    );
  }

  Widget _home(BuildContext context) {
    final events = _events;
    final next = events.firstWhere(
        (e) => e['unlocked'] == true && e['completed'] != true,
        orElse: () => events.last);
    final chapters = (_career!['chapters'] as List)
        .map((c) => Map<String, dynamic>.from(c))
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Row(children: [
            _RoundIcon(
                icon: Icons.arrow_back_rounded,
                label: 'Back',
                onTap: () => Navigator.maybePop(context)),
            const SizedBox(width: 12),
            const Expanded(child: SlayHeadline('My Career', size: 24)),
            SlayGameMenu(onExit: () => Navigator.maybePop(context)),
          ]),
          const SizedBox(height: 14),
          _RankCard(career: _career!, catalog: widget.catalog),
          const SizedBox(height: 16),
          _NextUpCard(event: next, onPlay: () => _play(next)),
          const SizedBox(height: 16),
          _DailyCard(
              daily: Map<String, dynamic>.from(_career!['daily']),
              endsAt: DateTime.parse(_career!['dailyEndsAt']),
              ranking: _dailyRanking,
              onPlay: () => _play(Map<String, dynamic>.from(_career!['daily']),
                  daily: true)),
          const SizedBox(height: 26),
          const SlayHeadline('Your road to Global Star', size: 20),
          const SizedBox(height: 4),
          Text('Clear each stage’s finale to unlock the next.',
              style: TextStyle(color: context.neon.mute, fontSize: 13)),
          const SizedBox(height: 12),
          for (final chapter in chapters)
            _StageSection(
              chapter: chapter,
              events: events
                  .where((e) => e['chapter'] == chapter['chapter'])
                  .toList(),
              current: next['id'],
              nextRank: _career!['rankIndex'] + 1 == chapter['chapter']
                  ? _career!['nextRank']
                  : null,
              onPlay: _play,
            ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SlayCabinet(
      onTap: onTap,
      feel: BouncyFeel.snap,
      semanticLabel: label,
      padding: const EdgeInsets.all(8),
      radius: 99,
      child: Icon(icon, size: 22, color: context.neon.ink));
}

/// Who you are and how far you've come.
class _RankCard extends StatelessWidget {
  const _RankCard({required this.career, required this.catalog});
  final Map<String, dynamic> career, catalog;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final rank = Map<String, dynamic>.from(career['rank']);
    final next = career['nextRank'] == null
        ? null
        : Map<String, dynamic>.from(career['nextRank']);
    final xp = career['xp'] as int;
    final from = rank['minimumXp'] as int, to = next?['minimumXp'] as int?;
    final character = Map<String, dynamic>.from(career['character']);
    final avatar = (catalog['avatars'] as List).cast<Map>().firstWhere(
        (a) => (a['id'] ?? a['body']) == character['avatarId'],
        orElse: () => const {});
    final stage = SlayStageLook.of(((career['chapters'] as List)
        .lastWhere((c) => c['unlocked'] == true))['location']);
    return SlayCabinet(
      gradient: stage.gradient,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SlayCharacterBubble(
              thumbnail: avatar['thumbnailUrl'],
              body: character['body'],
              size: 68),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('LEVEL ${career['level']}',
                    style: TextStyle(
                        color: stage.ink.withValues(alpha: .8),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        fontSize: 11)),
                SlayHeadline(rank['name'], size: 28, colour: stage.ink),
                if (avatar['name'] != null && avatar['name'] != 'Original')
                  Text(avatar['name'],
                      style: TextStyle(
                          color: stage.ink.withValues(alpha: .8),
                          fontSize: 12)),
              ])),
        ]),
        const SizedBox(height: 14),
        SlayXpBar(value: to == null ? 1 : (xp - from) / math.max(1, to - from)),
        const SizedBox(height: 6),
        Text(
            next == null
                ? 'Global Star! You made it to the top ✨'
                : '$xp / $to XP to ${next['name']}',
            style: TextStyle(
                color: stage.ink, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          SlayStatChip(
              icon: Icons.star_rounded, label: '${career['totalStars']} stars'),
          SlayStatChip(
              icon: Icons.local_fire_department_rounded,
              label: '${career['streak']} day streak',
              colour: n.danger),
          SlayStatChip(
              icon: Icons.emoji_events_rounded,
              label:
                  '${career['completed']}/${(career['events'] as List).length} events',
              colour: n.jade),
        ]),
      ]),
    );
  }
}

/// The one big button: your next event.
class _NextUpCard extends StatelessWidget {
  const _NextUpCard({required this.event, required this.onPlay});
  final Map<String, dynamic> event;
  final VoidCallback onPlay;
  @override
  Widget build(BuildContext context) {
    final n = context.neon, stage = SlayStageLook.of(event['location']);
    final finale = (event['minimumScore'] as num) > 0;
    return SlayCabinet(
      onTap: onPlay,
      semanticLabel: 'Next event: ${event['title']}',
      colour: n.panel,
      child: Row(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
              gradient: stage.gradient,
              shape: BoxShape.circle,
              border: Border.all(color: kCabinetInk, width: 2.5)),
          child: Icon(finale ? Icons.workspace_premium_rounded : stage.icon,
              color: stage.ink, size: 30),
        ),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(finale ? 'NEXT UP · FINALE' : 'NEXT UP',
              style: TextStyle(
                  color: n.brand,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  fontSize: 11)),
          Text(event['title'],
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          Text(event['chapterTitle'],
              style: TextStyle(color: n.mute, fontSize: 12)),
        ])),
        IdleBounce(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: n.brand,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: kCabinetInk, width: 2)),
            child: const Text('PLAY',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ),
      ]),
    );
  }
}

/// A gentle repeating hop that says "tap me".
class IdleBounce extends StatefulWidget {
  const IdleBounce({super.key, required this.child});
  final Widget child;
  @override
  State<IdleBounce> createState() => _IdleBounceState();
}

class _IdleBounceState extends State<IdleBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _c.value < .3 ? math.sin(_c.value / .3 * math.pi) : 0.0;
        return Transform.translate(offset: Offset(0, -5 * t), child: child);
      },
      child: widget.child);
}

class _DailyCard extends StatelessWidget {
  const _DailyCard(
      {required this.daily,
      required this.endsAt,
      required this.ranking,
      required this.onPlay});
  final Map<String, dynamic> daily;
  final DateTime endsAt;
  final Map<String, dynamic>? ranking;
  final VoidCallback onPlay;
  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final best = daily['personalBest'] as num?;
    final friends = ranking?['friendsRank'];
    final top = ranking?['global']?['topPercent'];
    return SlayCabinet(
      onTap: onPlay,
      semanticLabel: 'Daily Slay: ${daily['title']}',
      gradient: LinearGradient(
          colors: [n.brand, const Color(0xFFFF4FA3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('☀️ DAILY SLAY',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2)),
          ),
          SlayCountdown(endsAt,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        SlayHeadline(daily['title'], size: 24, colour: Colors.white),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          SlayStatChip(
              icon: Icons.emoji_events_rounded,
              label: best == null ? 'Up to 225 coins' : 'Best ${best.round()}'),
          if (friends != null)
            SlayStatChip(
                icon: Icons.people_alt_rounded,
                label: '#$friends with friends',
                colour: n.jade),
          if (top != null)
            SlayStatChip(
                icon: Icons.public_rounded,
                label: 'Top $top%',
                colour: n.brand),
        ]),
      ]),
    );
  }
}

/// One career stage: its banner and the winding path of its events.
class _StageSection extends StatelessWidget {
  const _StageSection(
      {required this.chapter,
      required this.events,
      required this.current,
      required this.nextRank,
      required this.onPlay});
  final Map<String, dynamic> chapter;
  final List<Map<String, dynamic>> events;
  final String current;
  final dynamic nextRank;
  final Future<void> Function(Map<String, dynamic>) onPlay;

  static const _row = 104.0;
  static double _x(int i) => math.sin(i * 1.25 + .4) * .55;

  @override
  Widget build(BuildContext context) {
    final n = context.neon, stage = SlayStageLook.of(chapter['location']);
    final open = chapter['unlocked'] == true;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Opacity(
          opacity: open ? 1 : .6,
          child: SlayCabinet(
            gradient: open ? stage.gradient : null,
            colour: open ? null : n.plate,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              Icon(open ? stage.icon : Icons.lock_rounded,
                  color: open ? stage.ink : n.mute, size: 28),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('STAGE ${chapter['chapter'] + 1}',
                        style: TextStyle(
                            color: (open ? stage.ink : n.mute)
                                .withValues(alpha: .8),
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            fontSize: 10)),
                    SlayHeadline(chapter['title'],
                        size: 20, colour: open ? stage.ink : n.mute),
                    Text('${chapter['room']} → ${chapter['venue']}',
                        style: TextStyle(
                            color: (open ? stage.ink : n.mute)
                                .withValues(alpha: .85),
                            fontSize: 12)),
                  ])),
            ]),
          ),
        ),
        if (!open && nextRank != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
            child: Text(
                '🔓 Become ${nextRank['name']}: ${nextRank['minimumXp']} XP · '
                '${nextRank['minimumCompleted']} events · ${nextRank['minimumStars']}★ '
                'and clear the finale before it.',
                style: TextStyle(
                    color: n.mid, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        SizedBox(
          height: _row * events.length + 8,
          child: Stack(children: [
            Positioned.fill(
              child: CustomPaint(
                  painter: _TrailPainter(
                      [for (int i = 0; i < events.length; i++) _x(i)],
                      _row,
                      open ? stage.to : n.line)),
            ),
            for (int i = 0; i < events.length; i++)
              Positioned(
                top: i * _row + 8,
                left: 0,
                right: 0,
                height: _row,
                child: Align(
                  alignment: Alignment(_x(i), -1),
                  child: _EventNode(
                    event: events[i],
                    stage: stage,
                    current: events[i]['id'] == current,
                    labelLeft: _x(i) > 0,
                    onTap: () => onPlay(events[i]),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _TrailPainter extends CustomPainter {
  _TrailPainter(this.xs, this.row, this.colour);
  final List<double> xs;
  final double row;
  final Color colour;
  @override
  void paint(Canvas canvas, Size size) {
    if (xs.length < 2) return;
    Offset at(int i) => Offset(size.width / 2 * (1 + xs[i]), i * row + 8 + 36);
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (int i = 1; i < xs.length; i++) {
      final a = at(i - 1), b = at(i);
      path.cubicTo(a.dx, a.dy + row / 2, b.dx, b.dy - row / 2, b.dx, b.dy);
    }
    final paint = Paint()
      ..color = colour.withValues(alpha: .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 16) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) =>
      old.colour != colour || old.xs.length != xs.length;
}

class _EventNode extends StatelessWidget {
  const _EventNode(
      {required this.event,
      required this.stage,
      required this.current,
      required this.labelLeft,
      required this.onTap});
  final Map<String, dynamic> event;
  final SlayStageLook stage;
  final bool current, labelLeft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final open = event['unlocked'] == true, done = event['completed'] == true;
    final finale = (event['minimumScore'] as num) > 0;
    final size = finale ? 80.0 : 70.0;
    final bubble = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: open ? stage.gradient : null,
        color: open ? null : n.plate,
        border: Border.all(color: kCabinetInk, width: 3),
        boxShadow: [
          const BoxShadow(
              color: Colors.black38, blurRadius: 0, offset: Offset(2, 4)),
          if (current)
            BoxShadow(
                color: n.gold.withValues(alpha: .8),
                blurRadius: 18,
                spreadRadius: 2),
        ],
      ),
      child: Icon(
          !open
              ? Icons.lock_rounded
              : finale
                  ? Icons.workspace_premium_rounded
                  : done
                      ? Icons.check_rounded
                      : stage.icon,
          color: open ? stage.ink : n.mute,
          size: finale ? 36 : 30),
    );
    final label = SizedBox(
      width: 130,
      child: Column(
          crossAxisAlignment:
              labelLeft ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (finale)
              Text('FINALE · ${event['minimumScore']}+',
                  style: TextStyle(
                      color: n.gold,
                      fontSize: 10,
                      fontWeight: FontWeight.w900)),
            Text(event['title'],
                textAlign: labelLeft ? TextAlign.end : TextAlign.start,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: open ? n.ink : n.mute,
                    fontWeight: FontWeight.w800,
                    fontSize: 13)),
            if (done || (event['stars'] as int) > 0)
              SlayStars(event['stars'] as int, size: 14),
          ]),
    );
    return Semantics(
      button: open,
      label:
          '${event['title']}${open ? '' : ', locked'}${done ? ', ${event['stars']} stars' : ''}',
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (labelLeft) ...[label, const SizedBox(width: 10)],
          open
              ? Bouncy(feel: BouncyFeel.wobble, onTap: onTap, child: bubble)
              : bubble,
          if (!labelLeft) ...[const SizedBox(width: 10), label],
        ]),
      ),
    );
  }
}

/// The event brief as an invitation card. Returns true to start styling.
Future<bool?> showSlayInvite(BuildContext context, Map<String, dynamic> event,
    {bool daily = false}) {
  final stage = SlayStageLook.of(event['location']);
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (c) {
      final n = c.neon;
      final theme = Map<String, dynamic>.from(event['theme']);
      final best = event['personalBest'] as num?;
      final finale = !daily && (event['minimumScore'] as num) > 0;
      return Theme(
        data: slayTheme(c),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SingleChildScrollView(
              child: SlayCabinet(
                colour: n.bg,
                padding: EdgeInsets.zero,
                radius: 28,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                        decoration: BoxDecoration(
                            gradient: stage.gradient,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(25))),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  daily ? '☀️ DAILY SLAY' : '💌 YOU’RE INVITED',
                                  style: TextStyle(
                                      color: stage.ink,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.4)),
                              const SizedBox(height: 6),
                              SlayHeadline(event['title'],
                                  size: 28, colour: stage.ink),
                              const SizedBox(height: 4),
                              Text(event['chapterTitle'],
                                  style: TextStyle(
                                      color: stage.ink.withValues(alpha: .85),
                                      fontWeight: FontWeight.w700)),
                            ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(event['brief'],
                                  style: const TextStyle(
                                      fontSize: 15, height: 1.35)),
                              const SizedBox(height: 16),
                              _InviteRow(
                                  title: 'Dress code',
                                  child: Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final tag in theme['styleTags'])
                                          _Tag(
                                              '✨ ${tag[0].toUpperCase()}${tag.substring(1)}',
                                              n.brand),
                                      ])),
                              _InviteRow(
                                  title: 'Must wear',
                                  child: Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final item
                                            in theme['requiredCategories'])
                                          _Tag(
                                              '${slayCategoryEmoji[item] ?? '✨'} ${slayCategoryName(item)}',
                                              n.jade),
                                      ])),
                              if ((event['bonus'] ?? '').toString().isNotEmpty)
                                _InviteRow(
                                    title: 'Bonus tip',
                                    child: Text('💡 ${event['bonus']}')),
                              _InviteRow(
                                  title: 'Rewards',
                                  child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        SlayStatChip(
                                            icon: Icons.monetization_on_rounded,
                                            label:
                                                'Up to ${daily ? 225 : 175}'),
                                        const SlayStatChip(
                                            icon: Icons.bolt_rounded,
                                            label: 'Up to 140 XP'),
                                        if (!daily)
                                          const SlayStatChip(
                                              icon: Icons.checkroom_rounded,
                                              label: '4★ & 5★ unlock clothes'),
                                      ])),
                              if (finale)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                      color: n.gold.withValues(alpha: .15),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: n.gold, width: 1.5)),
                                  child: Text(
                                      '👑 Stage finale: score ${event['minimumScore']} or more to open the next stage.',
                                      style: TextStyle(
                                          color: n.ink,
                                          fontWeight: FontWeight.w800)),
                                ),
                              if (best != null) ...[
                                const SizedBox(height: 12),
                                Row(children: [
                                  Text('Your best: ${best.round()}',
                                      style: TextStyle(
                                          color: n.mid,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(width: 8),
                                  SlayStars(event['stars'] as int? ?? 0,
                                      size: 16),
                                ]),
                              ],
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: SlayButton.icon(
                                    onPressed: () => Navigator.pop(c, true),
                                    icon:
                                        const Icon(Icons.auto_awesome_rounded),
                                    label: Text(best == null
                                        ? 'Let’s slay!'
                                        : 'Beat my best!')),
                              ),
                            ]),
                      ),
                    ]),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(),
              style: TextStyle(
                  color: context.neon.mute,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1)),
          const SizedBox(height: 6),
          child,
        ]),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.colour);
  final String text;
  final Color colour;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: colour.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(99),
            border:
                Border.all(color: colour.withValues(alpha: .7), width: 1.5)),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      );
}

/// Choose your star once; they stay for the whole career.
class SlayCharacterPicker extends StatefulWidget {
  const SlayCharacterPicker(
      {super.key, required this.catalog, required this.onChosen});
  final Map<String, dynamic> catalog;
  final Future<void> Function(String body, String avatarId) onChosen;
  @override
  State<SlayCharacterPicker> createState() => _SlayCharacterPickerState();
}

class _SlayCharacterPickerState extends State<SlayCharacterPicker> {
  final _stage = SlayStageController();
  int _index = 0;
  bool _busy = false;

  List<Map<String, dynamic>> get _avatars => (widget.catalog['avatars'] as List)
      .map((a) => Map<String, dynamic>.from(a))
      .toList();

  SlayLook _lookFor(Map<String, dynamic> avatar) {
    final body = avatar['body'] as String;
    return SlayLook.initial(body).copy(avatarId: avatar['id'] ?? body, items: {
      'hair': '$body-hair-0',
      'outfit': '$body-essential',
      'shoes': 'shoe-1'
    });
  }

  Future<void> _confirm() async {
    final avatar = _avatars[_index];
    final name = avatar['name'] == null || avatar['name'] == 'Original'
        ? (avatar['body'] == 'male' ? 'him' : 'her')
        : avatar['name'];
    final sure = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: Text('Start your career with $name?'),
              content: const Text(
                  'Your star stays with you for the whole journey, from Starter Studio to Global Star.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Keep looking')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('That’s my star!')),
              ],
            ));
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onChosen(avatar['body'], avatar['id'] ?? avatar['body']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final avatars = _avatars, avatar = avatars[_index];
    final name = avatar['name'] == null || avatar['name'] == 'Original'
        ? (avatar['body'] == 'male' ? 'Classic him' : 'Classic her')
        : avatar['name'];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Row(children: [
          _RoundIcon(
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              onTap: () => Navigator.maybePop(context)),
          const Spacer(),
        ]),
      ),
      const SizedBox(height: 6),
      const SlayHeadline('Who’s your star?', size: 30),
      const SizedBox(height: 4),
      Text('Pick once. They’ll walk every runway with you.',
          style: TextStyle(color: n.mute)),
      const SizedBox(height: 10),
      Expanded(
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SlayCabinet(
                padding: EdgeInsets.zero,
                radius: 28,
                gradient: SlayStageLook.of('studio').gradient,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: SlayStage(
                      catalog: widget.catalog,
                      look: _lookFor(avatar),
                      controller: _stage),
                ),
              ),
            ),
          ),
          for (final (alignment, step, icon) in [
            (Alignment.centerLeft, -1, Icons.chevron_left_rounded),
            (Alignment.centerRight, 1, Icons.chevron_right_rounded)
          ])
            Align(
              alignment: alignment,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _RoundIcon(
                    icon: icon,
                    label: step < 0 ? 'Previous star' : 'Next star',
                    onTap: () => setState(
                        () => _index = (_index + step) % avatars.length)),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      SlayHeadline(name, size: 24),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (int i = 0; i < avatars.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.all(3),
            width: i == _index ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
                color: i == _index ? n.brand : n.line,
                borderRadius: BorderRadius.circular(8)),
          ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: SlayButton.icon(
              onPressed: _busy ? null : _confirm,
              icon: const Icon(Icons.favorite_rounded),
              label: const Text('This is my star')),
        ),
      ),
    ]);
  }
}
