import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../competitive/leaderboard_screen.dart';
import 'slay_models.dart';
import 'slay_stage.dart';
import 'slay_theme.dart';
import '../../theme/neon_theme.dart';
import 'slay_studio_screen.dart';
import 'slay_competition_screen.dart';
import 'slay_cups_screen.dart';
import 'slay_game_menu.dart';
import '../../widgets/neon.dart';

class SlayHubScreen extends StatefulWidget {
  const SlayHubScreen({super.key});
  @override
  State<SlayHubScreen> createState() => _SlayHubScreenState();
}

class _SlayHubScreenState extends State<SlayHubScreen> {
  Map<String, dynamic>? _catalog, _profile;
  List<Map<String, dynamic>> _competitions = [];
  String? _error;
  bool _loading = true;
  final _stage = SlayStageController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final api = SlayApi(AppScope.of(context).api);
      final data =
          await Future.wait([api.catalog(), api.profile(), api.competitions()]);
      if (mounted) {
        setState(() {
          _catalog = data[0] as Map<String, dynamic>;
          _profile = data[1] as Map<String, dynamic>;
          _competitions = data[2] as List<Map<String, dynamic>>;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _studio(Map<String, dynamic> theme) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => SlayStudioScreen(
                catalog: _catalog!,
                theme: theme,
                initialBody: (theme['bodyEligibility'] as List).first,
                owned: Set<String>.from(_profile!['owned']))));
    if (mounted) _load();
  }

  Future<void> _open(Map<String, dynamic> competition) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                SlayCompetitionScreen(competitionId: competition['id'])));
    if (mounted) _load();
  }

  Future<void> _create(String mode) async {
    String theme = 'first-date', body = 'male';
    int seats = mode == 'battle'
        ? 2
        : mode == 'group'
            ? 8
            : 6;
    final go = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.neon.bg,
        builder: (c) => StatefulBuilder(
            builder: (c, update) => SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SlayLabel(mode == 'battle'
                              ? 'Head to head'
                              : mode == 'group'
                                  ? 'The style table'
                                  : 'The elimination show'),
                          const SizedBox(height: 8),
                          Text('Set the brief.',
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 20),
                          DropdownButtonFormField<String>(
                              initialValue: theme,
                              decoration:
                                  const InputDecoration(labelText: 'Theme'),
                              items: [
                                for (final t in _catalog!['themes'] as List)
                                  DropdownMenuItem(
                                      value: t['id'] as String,
                                      child: Text(t['title']))
                              ],
                              onChanged: (v) => update(() => theme = v!)),
                          if (mode != 'battle') ...[
                            const SizedBox(height: 16),
                            DropdownButtonFormField<int>(
                                initialValue: seats,
                                decoration: const InputDecoration(
                                    labelText: 'Contestants'),
                                items: [
                                  for (final n in [4, 6, 8, 10, 16])
                                    DropdownMenuItem(
                                        value: n, child: Text('$n players'))
                                ],
                                onChanged: (v) => update(() => seats = v!))
                          ],
                          if (mode == 'slay_or_pass') ...[
                            const SizedBox(height: 16),
                            SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(
                                      value: 'male',
                                      label: Text('Male contestants')),
                                  ButtonSegment(
                                      value: 'female',
                                      label: Text('Female contestants'))
                                ],
                                selected: {
                                  body
                                },
                                onSelectionChanged: (v) =>
                                    update(() => body = v.first)),
                            const SizedBox(height: 12),
                            Text(
                                '3–6 judges use the opposite avatar body. The judges rate the style and theme fit.',
                                style: TextStyle(
                                    color: context.neon.mute, fontSize: 12))
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                              width: double.infinity,
                              child: SlayButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('Create the room'))),
                        ])))));
    if (go != true || !mounted) return;
    try {
      final competition = await SlayApi(AppScope.of(context).api)
          .create(mode, theme, seats, body);
      if (mounted) await _open(competition);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: slayTheme(context),
      child: Builder(
          builder: (context) => Scaffold(
                appBar: AppBar(
                    title: const Text('SLAYHUUD',
                        style: TextStyle(
                            letterSpacing: 3,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    actions: [
                      IconButton(
                          tooltip: 'Style rankings',
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LeaderboardScreen(
                                      gameType: 'slayhuud'))),
                          icon: const Icon(Icons.leaderboard_outlined)),
                      SlayGameMenu(onExit: () => leaveSlayScreen(context)),
                    ]),
                body: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(_error!)),
                                SlayButton(
                                    onPressed: () {
                                      setState(() => _loading = true);
                                      _load();
                                    },
                                    child: const Text('Try again'))
                              ]))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                children: [
                                  Row(children: [
                                    const Expanded(
                                        child: SlayLabel(
                                            'Your fashion playground')),
                                    Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                            color: context.neon.plate,
                                            borderRadius:
                                                BorderRadius.circular(30)),
                                        child: Text('${_profile!['xp']} XP',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 11)))
                                  ]),
                                  const SizedBox(height: 12),
                                  Text('Ready to slay?',
                                      style: Theme.of(context)
                                          .textTheme
                                          .displaySmall),
                                  const SizedBox(height: 10),
                                  Text('Style a look. Enter a challenge. Vote.',
                                      style:
                                          TextStyle(color: context.neon.mute)),
                                  const SizedBox(height: 14),
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    for (final stat in {
                                      '★ Slay': _profile!['competitive']
                                                  ?['rating']
                                              ?.toString() ??
                                          'Unrated',
                                      '🏆 Wins':
                                          '${_profile!['stats']?['wins'] ?? 0}',
                                      '✦ Top 3':
                                          '${_profile!['stats']?['top_three'] ?? 0}',
                                    }.entries)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 7),
                                        decoration: BoxDecoration(
                                            color: context.neon.panel,
                                            borderRadius:
                                                BorderRadius.circular(30),
                                            border: Border.all(
                                                color: context.neon.gold
                                                    .withValues(alpha: .4))),
                                        child: Text(
                                            '${stat.key}  ${stat.value}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: context.neon.ink)),
                                      ),
                                  ]),
                                  const SizedBox(height: 14),
                                  SlayPanel(
                                      padding: EdgeInsets.zero,
                                      child: Column(children: [
                                        Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                20, 18, 20, 10),
                                            child: Row(children: [
                                              const Expanded(
                                                  child: SlayLabel(
                                                      'Your dressing room')),
                                              Icon(Icons.auto_awesome_outlined,
                                                  size: 17,
                                                  color: context.neon.gold)
                                            ])),
                                        SizedBox(
                                            height: 220,
                                            child: ClipRRect(
                                                borderRadius:
                                                    const BorderRadius.vertical(
                                                        bottom:
                                                            Radius.circular(0)),
                                                child: SlayStage(
                                                    catalog: _catalog!,
                                                    look: SlayLook.initial()
                                                        .copy(items: {
                                                      'outfit':
                                                          'female-essential',
                                                      'hair': 'female-hair-0',
                                                      'shoes': 'shoe-1'
                                                    }),
                                                    controller: _stage))),
                                        Padding(
                                            padding: const EdgeInsets.all(18),
                                            child: Row(children: [
                                              Expanded(
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                    Text('Make it yours',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleLarge),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                        'Outfits, hair and a full 360° view.',
                                                        style: TextStyle(
                                                            fontSize: 12,
                                                            color: context
                                                                .neon.mute))
                                                  ])),
                                              SlayButton(
                                                  onPressed: () => _studio(Map<
                                                          String, dynamic>.from(
                                                      (_catalog!['themes']
                                                              as List)
                                                          .firstWhere((t) =>
                                                              t['id'] ==
                                                              'first-date'))),
                                                  child: const Text(
                                                      'Let’s style!'))
                                            ])),
                                      ])),
                                  const SizedBox(height: 20),
                                  Row(children: [
                                    Expanded(
                                        child: Text('Take the stage',
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium)),
                                    const SlayLabel('Choose how to play')
                                  ]),
                                  const SizedBox(height: 14),
                                  LayoutBuilder(
                                      builder: (c, size) => Wrap(
                                              spacing: 12,
                                              runSpacing: 12,
                                              children: [
                                                _mode(
                                                    size.maxWidth,
                                                    'Solo challenges',
                                                    'Play at your pace. Earn stars.',
                                                    Icons.auto_awesome_outlined,
                                                    context.neon.gold,
                                                    () => _themes()),
                                                _mode(
                                                    size.maxWidth,
                                                    'Style Battle',
                                                    'Challenge one other stylist.',
                                                    Icons.bolt_outlined,
                                                    context.neon.brand,
                                                    () => _create('battle')),
                                                _mode(
                                                    size.maxWidth,
                                                    'Group challenge',
                                                    'Style together. Vote for the best.',
                                                    Icons.groups_outlined,
                                                    context.neon.jade,
                                                    () => _create('group')),
                                                _mode(
                                                    size.maxWidth,
                                                    'Slay or Pass',
                                                    'Judges vote. One stylist wins.',
                                                    Icons
                                                        .local_fire_department_outlined,
                                                    context.neon.danger,
                                                    () => _create(
                                                        'slay_or_pass')),
                                              ])),
                                  const SizedBox(height: 22),
                                  InkWell(
                                      onTap: _clients,
                                      borderRadius: BorderRadius.circular(22),
                                      child: SlayPanel(
                                          colour: context.neon.plate,
                                          child: Row(children: [
                                            Icon(Icons.person_outline,
                                                size: 30,
                                                color: context.neon.brand),
                                            const SizedBox(width: 16),
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  const SlayLabel(
                                                      'The client book'),
                                                  const SizedBox(height: 5),
                                                  Text('Be someone’s stylist.',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleLarge),
                                                  Text(
                                                      'Real briefs. Your creative direction.',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: context
                                                              .neon.mute))
                                                ])),
                                            const Icon(Icons.north_east,
                                                size: 18)
                                          ]))),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                      onPressed: _tournaments,
                                      icon: const Icon(
                                          Icons.emoji_events_outlined),
                                      label:
                                          const Text('SlayHuud Fashion Cups')),
                                  if (_competitions.isNotEmpty) ...[
                                    const SizedBox(height: 28),
                                    Text('On the runway',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium),
                                    const SizedBox(height: 12),
                                    for (final competition in _competitions)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 10),
                                          child: InkWell(
                                              onTap: () => _open(competition),
                                              borderRadius:
                                                  BorderRadius.circular(22),
                                              child: SlayPanel(
                                                  padding:
                                                      const EdgeInsets.all(16),
                                                  child: Row(children: [
                                                    Container(
                                                        width: 44,
                                                        height: 44,
                                                        decoration: BoxDecoration(
                                                            color: const Color(
                                                                0xffefe4e9),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12)),
                                                        child: Icon(
                                                            Icons.checkroom,
                                                            color: context
                                                                .neon.brand)),
                                                    const SizedBox(width: 14),
                                                    Expanded(
                                                        child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                          SlayLabel(_modeName(
                                                              competition[
                                                                  'mode'])),
                                                          const SizedBox(
                                                              height: 4),
                                                          Text(
                                                              competition[
                                                                      'theme']
                                                                  ['title'],
                                                              style: const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600)),
                                                          Text(
                                                              competition['status'] ==
                                                                      'voting'
                                                                  ? 'Community voting is open'
                                                                  : competition[
                                                                              'status'] ==
                                                                          'results'
                                                                      ? 'Results are in'
                                                                      : '${competition['contestants']} players · ${competition['status']}',
                                                              style: TextStyle(
                                                                  fontSize: 12,
                                                                  color: context
                                                                      .neon
                                                                      .mute))
                                                        ])),
                                                    const Icon(
                                                        Icons.arrow_forward,
                                                        size: 18)
                                                  ]))))
                                  ],
                                  const SizedBox(height: 12),
                                  Text(
                                      'New cultural outfits are coming. Themes are available now; the wardrobe grows as new designs are added.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: context.neon.mute,
                                          fontSize: 11)),
                                ])),
              )));
  Widget _mode(double width, String title, String subtitle, IconData icon,
          Color colour, VoidCallback onTap) =>
      SizedBox(
          width: (width - 12) / 2,
          child: Semantics(
              button: true,
              label: title,
              child: Bouncy(
                  onTap: onTap,
                  child: Container(
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(minHeight: 112),
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color.alphaBlend(colour.withValues(alpha: .19),
                                    context.neon.panel),
                                context.neon.panel
                              ]),
                          border: Border.all(
                              color: colour.withValues(alpha: .65), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                                color: colour.withValues(alpha: .32),
                                offset: const Offset(0, 4))
                          ],
                          borderRadius: BorderRadius.circular(24)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                      color: colour,
                                      borderRadius: BorderRadius.circular(30)),
                                  child: Icon(icon,
                                      color: colour == context.neon.brand
                                          ? Colors.white
                                          : context.neon.onAccent,
                                      size: 20)),
                              const Spacer(),
                              Icon(Icons.play_arrow_rounded,
                                  size: 20, color: colour)
                            ]),
                            const SizedBox(height: 9),
                            Text(title,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 3),
                            Text(subtitle,
                                style: TextStyle(
                                    fontSize: 11,
                                    height: 1.4,
                                    color: context.neon.mute))
                          ])))));
  String _modeName(String mode) => switch (mode) {
        'battle' => 'Style Battle',
        'group' => 'Group competition',
        'slay_or_pass' => 'Slay or Pass',
        'daily' => 'Daily challenge',
        'weekly' => 'Weekly challenge',
        _ => mode
      };
  Future<void> _clients() async {
    final client = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: context.neon.bg,
        builder: (c) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SlayLabel('Your next appointment'),
                      const SizedBox(height: 12),
                      for (final client in _catalog!['clients'] as List)
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(client['name']),
                            subtitle: Text(client['brief']),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.pop(
                                c, Map<String, dynamic>.from(client)))
                    ]))));
    if (client == null || !mounted) return;
    final theme = Map<String, dynamic>.from((_catalog!['themes'] as List)
        .firstWhere((t) => t['id'] == client['themeId']));
    theme['description'] = client['brief'];
    theme['title'] = "${client['name']}'s brief";
    _studio(theme);
  }

  Future<void> _tournaments() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SlayCupsScreen()));
    if (mounted) _load();
  }

  Future<void> _themes() async {
    final theme = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.neon.bg,
        builder: (c) => SafeArea(
            child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: .7,
                builder: (c, scroll) => ListView(
                        controller: scroll,
                        padding: const EdgeInsets.all(20),
                        children: [
                          const SlayLabel('Find your inspiration'),
                          const SizedBox(height: 12),
                          Text('Choose your moment.',
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 16),
                          for (final t in _catalog!['themes'] as List)
                            ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(t['title']),
                                subtitle:
                                    Text((t['styleTags'] as List).join(' · ')),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.pop(
                                    c, Map<String, dynamic>.from(t)))
                        ]))));
    if (theme != null && mounted) _studio(theme);
  }
}
