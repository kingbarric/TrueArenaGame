import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_state.dart';
import 'slay_models.dart';
import 'slay_stage.dart';
import 'slay_theme.dart';
import '../../theme/neon_theme.dart';
import 'slay_game_menu.dart';

class SlayStudioScreen extends StatefulWidget {
  const SlayStudioScreen(
      {super.key,
      required this.catalog,
      required this.theme,
      required this.owned,
      this.competitionId,
      this.initialBody = 'female',
      this.deadline});
  final Map<String, dynamic> catalog, theme;
  final Set<String> owned;
  final String? competitionId;
  final String initialBody;
  final DateTime? deadline;
  @override
  State<SlayStudioScreen> createState() => _SlayStudioScreenState();
}

class _SlayStudioScreenState extends State<SlayStudioScreen> {
  late SlayLook _look = SlayLook.initial(widget.initialBody);
  late final Set<String> _owned = {...widget.owned};
  final _stage = SlayStageController();
  String _category = 'outfit';
  bool _busy = false, _performing = false;
  String? _error;
  Timer? _clock;
  static const _categories = {
    'outfit': 'Looks',
    'dress': 'Dresses',
    'tops': 'Tops',
    'shirts': 'Shirts',
    'trousers': 'Trousers',
    'skirts': 'Skirts',
    'hair': 'Hair',
    'eyes': 'Eyes',
    'shoes': 'Shoes',
    'headwear': 'Headwear',
    'jewellery': 'Earrings',
    'bags': 'Bags',
    'makeup': 'Lipstick',
    'watches': 'Watches',
    'glasses': 'Glasses',
    'accessories': 'Details'
  };
  @override
  void initState() {
    super.initState();
    if (widget.deadline != null) {
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _brief() async => showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.theme['title'],
                        style: Theme.of(sheet).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    Text(widget.theme['description']),
                    const SizedBox(height: 16),
                    const SlayLabel('Required in this look'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      for (final c
                          in widget.theme['requiredCategories'] as List)
                        Chip(label: Text(c))
                    ]),
                    const SizedBox(height: 12),
                    Text(
                        'Style tags: ${(widget.theme['styleTags'] as List).join(' · ')}'),
                    if (widget.theme['budget'] != null)
                      Text('Wardrobe budget: ${widget.theme['budget']} coins'),
                  ]))));

  String get _timeLeft {
    if (widget.deadline == null) return '';
    final seconds =
        widget.deadline!.difference(DateTime.now()).inSeconds.clamp(0, 86400);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String get _draftKey =>
      'slay-draft-${AppScope.of(context).user?.id}-${_look.body}';
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final raw = prefs.getString(_draftKey);
    if (raw == null) return;
    try {
      final look =
          SlayLook.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
      final available = (widget.catalog['items'] as List)
          .where((item) => item['assetUrl'] != null)
          .map((item) => item['id'])
          .toSet();
      if (look.body == _look.body &&
          look.items.values.every(available.contains) &&
          mounted) {
        setState(() => _look = look);
      }
    } catch (_) {}
  }

  void _change(SlayLook look) {
    setState(() {
      _look = look;
      _error = null;
    });
    final key = _draftKey;
    SharedPreferences.getInstance()
        .then((p) => p.setString(key, jsonEncode(look.toJson())));
  }

  Future<void> _select(Map<String, dynamic> item) async {
    final id = item['id'] as String;
    if (!_owned.contains(id)) {
      final purchase = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: Text('Add ${item['name']}?'),
                  content: Text(
                      '${item['coinCost']} earned coins. This item stays in your wardrobe.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Later')),
                    SlayButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Unlock'))
                  ]));
      if (purchase != true || !mounted) return;
      try {
        await AppScope.of(context)
            .api
            .post('/slay/wardrobe/buy', {'itemId': id});
        if (!mounted) return;
        setState(() => _owned.add(id));
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
        return;
      }
    }
    _change(_look.equip(item,
        wardrobe: (widget.catalog['items'] as List).cast<Map>()));
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = SlayApi(AppScope.of(context).api);
      var submittedLook = _look;
      // Wait for the renderer to acknowledge the exact outfit before exporting its image.
      await _stage.request('applyLook', {'look': submittedLook.toJson()});
      if (!mounted) return;
      setState(() => _performing = true);
      final pose = await _stage.showOff();
      if (!mounted) return;
      if (widget.deadline != null &&
          !DateTime.now().isBefore(widget.deadline!)) {
        throw StateError(
            'Styling time has ended. This look was not submitted.');
      }
      submittedLook = submittedLook.copy(pose: pose);
      setState(() {
        _performing = false;
        _look = submittedLook;
      });
      final image = await _stage.snapshot();
      if (!mounted) return;
      final id = await api.save(submittedLook, image);
      if (widget.competitionId != null) {
        await api.action(widget.competitionId!, 'submit', {'lookId': id});
        if (mounted) Navigator.pop(context, true);
      } else {
        final score = await api.score(widget.theme['id'], id);
        if (!mounted) return;
        await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: context.neon.bg,
            builder: (c) => SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const SlayLabel('Your style report'),
                      const SizedBox(height: 10),
                      Text('${score['overall']}',
                          style: Theme.of(c)
                              .textTheme
                              .displaySmall
                              ?.copyWith(fontSize: 64)),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                              3,
                              (i) => Icon(
                                  i < (score['stars'] as num)
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  color: context.neon.gold,
                                  size: 32))),
                      const SizedBox(height: 20),
                      for (final dim in {
                        'themeFit': 'Theme fit',
                        'requirements': 'Required items',
                        'colour': 'Colour harmony',
                        'completeness': 'Completeness'
                      }.entries)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(children: [
                              Expanded(child: Text(dim.value)),
                              Text('${score[dim.key]} / 100',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))
                            ])),
                      if ((score['missing'] as List).isNotEmpty)
                        Text(
                            'Try adding: ${(score['missing'] as List).join(', ')}',
                            style: TextStyle(color: context.neon.mute)),
                      const SizedBox(height: 14),
                      Text('Coins and XP are awarded once per theme each day.',
                          style: TextStyle(
                              color: context.neon.mute, fontSize: 12)),
                      const SizedBox(height: 20),
                      SizedBox(
                          width: double.infinity,
                          child: SlayButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Back to the studio'))),
                    ]))));
      }
    } catch (e) {
      if (mounted && !e.toString().contains('cancelled')) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _performing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: slayTheme(context),
      child: Builder(builder: (context) {
        final items = (widget.catalog['items'] as List)
            .cast<Map>()
            .where((i) =>
                i['assetUrl'] != null &&
                i['category'] == _category &&
                (i['body'] == 'unisex' || i['body'] == _look.body))
            .toList();
        final canRemove = [
          'eyes',
          'makeup',
          'jewellery',
          'watches',
          'bags',
          'glasses',
          'headwear',
          'accessories'
        ].contains(_category);
        return Scaffold(
            appBar: AppBar(title: const Text('Your studio'), actions: [
              Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                      child: SlayLabel(widget.deadline == null
                          ? 'Practice look'
                          : _timeLeft))),
              SlayGameMenu(
                  onBrief: _brief,
                  onReset: _busy
                      ? null
                      : () => _change(SlayLook.initial(_look.body)),
                  exitLabel: 'Back to SlayHuud',
                  onExit: () => leaveSlayScreen(context)),
            ]),
            body:
                SafeArea(child: LayoutBuilder(builder: (context, constraints) {
              final stageHeight =
                  (constraints.maxHeight * .43).clamp(180.0, 400.0);
              return Column(children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const SlayLabel('Your challenge'),
                            const SizedBox(height: 4),
                            Text(widget.theme['title'],
                                style:
                                    Theme.of(context).textTheme.headlineMedium)
                          ])),
                      if (widget.competitionId == null)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          for (final body in ['female', 'male'])
                            if ((widget.theme['bodyEligibility'] as List)
                                .contains(body))
                              Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Tooltip(
                                      message: '$body avatar',
                                      child: SlayPill(
                                        label: body == 'female' ? 'Her' : 'Him',
                                        icon: body == 'female'
                                            ? Icons.female
                                            : Icons.male,
                                        selected: _look.body == body,
                                        onPressed: _busy
                                            ? null
                                            : () {
                                                setState(() => _look =
                                                    SlayLook.initial(body));
                                                _restore();
                                              },
                                      ))),
                        ])
                    ])),
                SizedBox(
                    height: stageHeight,
                    child: Stack(children: [
                      Positioned.fill(
                          child: SlayStage(
                              catalog: widget.catalog,
                              look: _look,
                              controller: _stage)),
                      Positioned(
                          top: 12,
                          left: 14,
                          child: ValueListenableBuilder<bool>(
                              valueListenable: _stage.showingOff,
                              builder: (_, playing, __) => playing
                                  ? ValueListenableBuilder<String>(
                                      valueListenable: _stage.showcasePhase,
                                      builder: (_, phase, __) =>
                                          SlayLabel(phase))
                                  : const SizedBox.shrink())),
                      Positioned(
                          top: 12,
                          right: 14,
                          child: Column(children: [
                            for (final preset in [
                              'full',
                              'face',
                              'back',
                              'feet'
                            ])
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Tooltip(
                                      message: preset == 'feet'
                                          ? 'Shoe close-up'
                                          : preset == 'back'
                                              ? 'Back view'
                                              : preset == 'face'
                                                  ? 'Face close-up'
                                                  : 'Full look',
                                      child: SlayButton.tonal(
                                          compact: true,
                                          onPressed: () => _stage.request(
                                                  'setCamera', {
                                                'preset': preset
                                              }).catchError(
                                                  (_) => <String, dynamic>{}),
                                          child: Icon(
                                              semanticLabel: preset == 'feet'
                                                  ? 'Shoe close-up'
                                                  : preset == 'back'
                                                      ? 'Back view'
                                                      : preset == 'face'
                                                          ? 'Face close-up'
                                                          : 'Full look',
                                              preset == 'feet'
                                                  ? Icons.ice_skating_outlined
                                                  : preset == 'back'
                                                      ? Icons.rotate_right
                                                      : preset == 'face'
                                                          ? Icons.face_outlined
                                                          : Icons.open_in_full,
                                              size: 20))))
                          ])),
                      Positioned(
                          bottom: 12,
                          left: 14,
                          child: Container(
                              decoration: BoxDecoration(
                                  color:
                                      context.neon.panel.withValues(alpha: .94),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                      color: context.neon.line, width: 1.5),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: kCabinetInk,
                                        offset: Offset(0, 3))
                                  ]),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        tooltip: 'Turn left',
                                        icon: const Icon(Icons.rotate_left,
                                            size: 20),
                                        onPressed: () => _stage.request(
                                                'rotateCamera', {
                                              'radians': -.785398
                                            }).catchError(
                                                (_) => <String, dynamic>{})),
                                    const SlayLabel('Rotate'),
                                    IconButton(
                                        tooltip: 'Turn right',
                                        icon: const Icon(Icons.rotate_right,
                                            size: 20),
                                        onPressed: () => _stage.request(
                                                'rotateCamera', {
                                              'radians': .785398
                                            }).catchError(
                                                (_) => <String, dynamic>{})),
                                  ])))
                    ])),
                SizedBox(
                    height: 48,
                    child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          SlayShowOffControl(
                              controller: _stage,
                              enabled: !_busy,
                              onFinished: (pose) =>
                                  _change(_look.copy(pose: pose)),
                              onError: (error) =>
                                  setState(() => _error = error.toString())),
                          const SizedBox(width: 8),
                          SlayPill(
                              label: 'Beauty',
                              icon: Icons.face_retouching_natural,
                              onPressed: _busy ? null : () => _customise()),
                          const SizedBox(width: 8),
                          SlayPill(
                              label:
                                  'Pose · ${_look.pose[0].toUpperCase()}${_look.pose.substring(1)}',
                              icon: Icons.accessibility_new,
                              onPressed: _busy
                                  ? null
                                  : () =>
                                      _pick('pose', widget.catalog['poses'])),
                          const SizedBox(width: 8),
                          SlayPill(
                              label: 'Scene',
                              icon: Icons.landscape_outlined,
                              onPressed: _busy
                                  ? null
                                  : () => _pick('background',
                                      widget.catalog['backgrounds'])),
                        ])),
                SizedBox(
                    height: 48,
                    child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final c in _categories.entries.where((c) =>
                              (widget.catalog['items'] as List).any((i) =>
                                  i['assetUrl'] != null &&
                                  i['category'] == c.key &&
                                  (i['body'] == 'unisex' ||
                                      i['body'] == _look.body))))
                            Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: SlayPill(
                                    label: c.value,
                                    selected: _category == c.key,
                                    onPressed: _busy
                                        ? null
                                        : () =>
                                            setState(() => _category = c.key)))
                        ])),
                Expanded(
                    child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 104,
                            mainAxisExtent: 112 +
                                (MediaQuery.textScalerOf(context).scale(10) -
                                            10)
                                        .clamp(0, 30) *
                                    3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8),
                        itemCount: items.length + (canRemove ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (canRemove && i == 0) {
                            return SlayWardrobeTile(
                                name: 'None',
                                selected: !_look.items.containsKey(_category),
                                owned: true,
                                onTap: _busy
                                    ? null
                                    : () => _change(_look.copy(
                                        items: {..._look.items}
                                          ..remove(_category))));
                          }
                          final item = Map<String, dynamic>.from(
                              items[i - (canRemove ? 1 : 0)]);
                          final selected = _look.items[_category] == item['id'],
                              owned = _owned.contains(item['id']);
                          return SlayWardrobeTile(
                            name: item['name'],
                            thumbnail: item['thumbnailUrl'],
                            selected: selected,
                            owned: owned,
                            coins: (item['coinCost'] as num?)?.toInt() ?? 0,
                            onTap: _busy ? null : () => _select(item),
                          );
                        })),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12))),
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                        width: double.infinity,
                        child: ValueListenableBuilder<bool>(
                            valueListenable: _stage.ready,
                            builder: (context, ready, _) => SlayButton.icon(
                                onPressed: _busy ||
                                        !ready ||
                                        (widget.deadline != null &&
                                            !DateTime.now()
                                                .isBefore(widget.deadline!))
                                    ? null
                                    : _submit,
                                icon: _busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.auto_awesome, size: 18),
                                label: Text(_busy
                                    ? (_performing
                                        ? 'Taking the stage…'
                                        : 'Saving your look…')
                                    : widget.competitionId == null
                                        ? 'Show off & see my score'
                                        : 'Show off & submit'))))),
              ]);
            })));
      }));
  Future<void> _pick(String category, List<dynamic> options) async {
    const poseDescriptions = {
      'signature': 'Relaxed arms with a little attitude',
      'confident': 'Hand on hip, ready for the spotlight',
      'editorial': 'A turned waist and tilted head',
      'celebrate': 'Arms up — own your win',
    };
    final chosen = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: context.neon.bg,
        builder: (c) => SafeArea(
                child: Wrap(children: [
              for (final option in options)
                ListTile(
                    title: Text(option.toString()[0].toUpperCase() +
                        option.toString().substring(1)),
                    subtitle: category == 'pose'
                        ? Text(poseDescriptions[option] ?? '')
                        : null,
                    leading: category == 'pose'
                        ? const Icon(Icons.accessibility_new_rounded)
                        : null,
                    trailing: Icon(
                        (category == 'pose' ? _look.pose : _look.background) ==
                                option
                            ? Icons.check_circle_rounded
                            : Icons.chevron_right,
                        color: (category == 'pose'
                                    ? _look.pose
                                    : _look.background) ==
                                option
                            ? context.neon.gold
                            : null),
                    onTap: () => Navigator.pop(c, option))
            ])));
    if (chosen != null && mounted) {
      _change(category == 'pose'
          ? _look.copy(pose: chosen)
          : _look.copy(background: chosen));
    }
  }

  Future<void> _customise() async {
    await showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.neon.bg,
        builder: (c) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SlayLabel('Make it yours'),
                      const SizedBox(height: 20),
                      Wrap(spacing: 14, children: [
                        for (final tone in widget.catalog['skinTones'] as List)
                          InkWell(
                              onTap: () {
                                _change(_look.copy(skinTone: tone));
                                Navigator.pop(c);
                              },
                              child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                      color: Color(int.parse(
                                          tone
                                              .toString()
                                              .replaceFirst('#', 'ff'),
                                          radix: 16)),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: _look.skinTone == tone
                                              ? context.neon.brand
                                              : Colors.transparent,
                                          width: 3))))
                      ]),
                      const SizedBox(height: 20),
                      Wrap(spacing: 8, children: [
                        for (final face
                            in widget.catalog['facePresets'] as List)
                          ActionChip(
                              label: Text(face),
                              onPressed: () {
                                _change(_look.copy(facePreset: face));
                                Navigator.pop(c);
                              })
                      ]),
                      const SizedBox(height: 12)
                    ]))));
  }
}
