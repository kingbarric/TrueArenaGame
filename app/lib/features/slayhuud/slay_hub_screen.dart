import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../competitive/leaderboard_screen.dart';
import 'slay_models.dart';
import 'slay_career_screen.dart';
import 'slay_stage.dart';
import 'slay_theme.dart';
import 'slay_ui.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/idle_wiggle.dart';
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
  Widget build(BuildContext context) {
    final n = context.neon;
    return Theme(
      data: slayTheme(context),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: n.bg,
          body: Stack(children: [
            const Positioned.fill(child: SlaySparkles()),
            SafeArea(
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: _topBar(context)),
                Expanded(
                  child: _loading
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
                                    const EdgeInsets.fromLTRB(16, 4, 16, 32),
                                children: [
                                  const SizedBox(height: 8),
                                  _hero(context),
                                  const SizedBox(height: 24),
                                  const SlayHeadline('Pick your game',
                                      size: 22),
                                  const SizedBox(height: 12),
                                  _games(context),
                                  if (_competitions.isNotEmpty) ...[
                                    const SizedBox(height: 26),
                                    const SlayHeadline('On the runway',
                                        size: 22),
                                    const SizedBox(height: 12),
                                    for (final competition in _competitions)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: _competitionRow(
                                            context, competition),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) => Row(children: [
        SlayCabinet(
            onTap: () => Navigator.maybePop(context),
            semanticLabel: 'Back',
            radius: 99,
            padding: const EdgeInsets.all(8),
            child: Icon(Icons.arrow_back_rounded, color: context.neon.ink)),
        const SizedBox(width: 12),
        Expanded(
          child: ShaderMask(
            shaderCallback: (r) => LinearGradient(colors: [
              context.neon.brand,
              const Color(0xFFFF4FA3),
              context.neon.gold
            ]).createShader(r),
            child:
                const SlayHeadline('SLAYHUUD', size: 28, colour: Colors.white),
          ),
        ),
        if (_profile?['rated'] == true)
          IconButton(
              tooltip: 'Style rankings',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const LeaderboardScreen(gameType: 'slayhuud'))),
              icon: const Icon(Icons.leaderboard_rounded)),
        SlayGameMenu(onExit: () => leaveSlayScreen(context)),
      ]);

  Widget _hero(BuildContext context) {
    final n = context.neon;
    final stats = _profile!['stats'] as Map? ?? const {};
    return SlayCabinet(
      padding: EdgeInsets.zero,
      gradient: SlayStageLook.of('studio').gradient,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(21)),
          child: SizedBox(
            height: 240,
            child: SlayStage(
                catalog: _catalog!,
                look: SlayLook.initial().copy(items: {
                  'outfit': 'female-essential',
                  'hair': 'female-hair-0',
                  'shoes': 'shoe-1'
                }),
                controller: _stage),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SlayHeadline('Ready to slay?', size: 26, colour: kCabinetInk),
            const SizedBox(height: 4),
            const Text('Style it, strut it, get judged. ✨',
                style:
                    TextStyle(color: kCabinetInk, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              SlayStatChip(
                  icon: Icons.emoji_events_rounded,
                  label: '${stats['wins'] ?? 0} wins'),
              SlayStatChip(
                  icon: Icons.workspace_premium_rounded,
                  label: '${stats['top_three'] ?? 0} top 3',
                  colour: n.brand),
              SlayStatChip(
                  icon: Icons.bolt_rounded,
                  label: '${_profile!['xp']} XP',
                  colour: n.jade),
              if (_profile!['rated'] == true &&
                  _profile!['competitive']?['rating'] != null)
                SlayStatChip(
                    icon: Icons.star_rounded,
                    label: '★ ${_profile!['competitive']['rating']}'),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: SlayButton.icon(
                  onPressed: () => _studio(Map<String, dynamic>.from(
                      (_catalog!['themes'] as List)
                          .firstWhere((t) => t['id'] == 'first-date'))),
                  icon: const Icon(Icons.checkroom_rounded),
                  label: const Text('Free style')),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _games(BuildContext context) {
    final n = context.neon;
    return LayoutBuilder(
      builder: (context, size) {
        final half = (size.maxWidth - 12) / 2;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(
            width: size.maxWidth,
            child: _gameTile(context,
                title: 'My Career',
                subtitle: 'Starter Studio to Global Star. Daily Slay inside ☀️',
                icon: Icons.auto_awesome_rounded,
                from: const Color(0xFFFF4FA3),
                to: n.gold,
                onTap: _career,
                wide: true),
          ),
          for (final (title, subtitle, icon, colour, action) in [
            (
              'Style Battle',
              'You vs one stylist',
              Icons.bolt_rounded,
              n.brand,
              () => _create('battle')
            ),
            (
              'Group Show',
              'Up to 16 stylists',
              Icons.groups_rounded,
              const Color(0xFF2F8F86),
              () => _create('group')
            ),
            (
              'Slay or Pass',
              'The judges decide',
              Icons.local_fire_department_rounded,
              n.danger,
              () => _create('slay_or_pass')
            ),
            (
              'Fashion Cups',
              'Knockout tournaments',
              Icons.emoji_events_rounded,
              const Color(0xFF8F7BFF),
              _tournaments
            ),
            (
              'Client Book',
              'Style for a client',
              Icons.person_pin_rounded,
              const Color(0xFF6E1F33),
              _clients
            ),
          ])
            SizedBox(
              width: half,
              child: _gameTile(context,
                  title: title,
                  subtitle: subtitle,
                  icon: icon,
                  from: Color.lerp(colour, Colors.white, .18)!,
                  to: colour,
                  onTap: action),
            ),
        ]);
      },
    );
  }

  Widget _gameTile(BuildContext context,
      {required String title,
      required String subtitle,
      required IconData icon,
      required Color from,
      required Color to,
      required VoidCallback onTap,
      bool wide = false}) {
    final badge = IdleWiggle(
      child: Container(
        width: wide ? 64 : 52,
        height: wide ? 64 : 52,
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .22),
            shape: BoxShape.circle,
            border: Border.all(color: kCabinetInk, width: 2.5)),
        child: Icon(icon, color: Colors.white, size: wide ? 34 : 28),
      ),
    );
    final words = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SlayHeadline(title, size: wide ? 24 : 19, colour: Colors.white),
          const SizedBox(height: 3),
          Text(subtitle,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: .9),
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ]);
    return SlayCabinet(
      onTap: onTap,
      semanticLabel: title,
      gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [from, to]),
      padding: const EdgeInsets.all(14),
      child: wide
          ? Row(children: [
              badge,
              const SizedBox(width: 14),
              Expanded(child: words)
            ])
          : ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 132),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [badge, const SizedBox(height: 10), words])),
    );
  }

  Widget _competitionRow(
      BuildContext context, Map<String, dynamic> competition) {
    final n = context.neon;
    final status = competition['status'] == 'voting'
        ? '🗳️ Voting is open'
        : competition['status'] == 'results'
            ? '🏆 Results are in'
            : '👗 ${competition['contestants']} stylists · ${competition['status']}';
    return SlayCabinet(
      onTap: () => _open(competition),
      feel: BouncyFeel.soft,
      semanticLabel: competition['theme']['title'],
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
              gradient:
                  LinearGradient(colors: [n.brand, const Color(0xFFFF4FA3)]),
              shape: BoxShape.circle,
              border: Border.all(color: kCabinetInk, width: 2)),
          child: const Icon(Icons.checkroom_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_modeName(competition['mode']).toUpperCase(),
              style: TextStyle(
                  color: n.brand,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1)),
          Text(competition['theme']['title'],
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          Text(status, style: TextStyle(fontSize: 12, color: n.mute)),
        ])),
        const Icon(Icons.chevron_right_rounded),
      ]),
    );
  }

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

  Future<void> _career() async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => SlayCareerScreen(
                catalog: _catalog!,
                owned: Set<String>.from(_profile!['owned']))));
    if (mounted) _load();
  }
}
