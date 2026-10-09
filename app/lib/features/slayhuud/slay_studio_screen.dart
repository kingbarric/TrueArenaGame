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
  bool _busy = false;
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
    'shoes': 'Shoes',
    'headwear': 'Headwear',
    'jewellery': 'Jewellery',
    'bags': 'Bags',
    'makeup': 'Makeup',
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
                    FilledButton(
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
    _change(_look.equip(item));
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = SlayApi(AppScope.of(context).api);
      // Wait for the renderer to acknowledge the exact outfit before exporting its image.
      await _stage.request('applyLook', {'look': _look.toJson()});
      final image = await _stage.snapshot();
      final id = await api.save(_look, image);
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
                          child: FilledButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Back to the studio'))),
                    ]))));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
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
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const SlayLabel('The brief'),
                            const SizedBox(height: 4),
                            Text(widget.theme['title'],
                                style:
                                    Theme.of(context).textTheme.headlineMedium)
                          ])),
                      if (widget.competitionId == null)
                        SegmentedButton<String>(
                            segments: [
                              if ((widget.theme['bodyEligibility'] as List)
                                  .contains('female'))
                                const ButtonSegment(
                                    value: 'female',
                                    icon: Icon(Icons.female),
                                    tooltip: 'Female avatar'),
                              if ((widget.theme['bodyEligibility'] as List)
                                  .contains('male'))
                                const ButtonSegment(
                                    value: 'male',
                                    icon: Icon(Icons.male),
                                    tooltip: 'Male avatar')
                            ],
                            selected: {
                              _look.body
                            },
                            onSelectionChanged: _busy
                                ? null
                                : (v) {
                                    setState(() =>
                                        _look = SlayLook.initial(v.first));
                                    _restore();
                                  })
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
                          right: 14,
                          child: Column(children: [
                            for (final preset in ['full', 'face', 'back'])
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Material(
                                      color: context.neon.panel
                                          .withValues(alpha: .94),
                                      borderRadius: BorderRadius.circular(12),
                                      child: IconButton(
                                          tooltip: preset == 'back'
                                              ? 'Back view'
                                              : preset == 'face'
                                                  ? 'Face close-up'
                                                  : 'Full look',
                                          onPressed: () => _stage.request(
                                                  'setCamera', {
                                                'preset': preset
                                              }).catchError((_) {
                                                return <String, dynamic>{};
                                              }),
                                          icon: Icon(
                                              preset == 'back'
                                                  ? Icons.rotate_right
                                                  : preset == 'face'
                                                      ? Icons.face_outlined
                                                      : Icons.open_in_full,
                                              size: 20))))
                          ])),
                      const Positioned(
                          bottom: 24,
                          left: 16,
                          child: SlayLabel('Drag to rotate · pinch to zoom'))
                    ])),
                SizedBox(
                    height: 48,
                    child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          ActionChip(
                              label: const Text('Skin & face'),
                              avatar: const Icon(Icons.face_retouching_natural,
                                  size: 16),
                              onPressed: () => _customise()),
                          const SizedBox(width: 8),
                          ActionChip(
                              label: Text(_look.pose[0].toUpperCase() +
                                  _look.pose.substring(1)),
                              avatar:
                                  const Icon(Icons.accessibility_new, size: 16),
                              onPressed: () =>
                                  _pick('pose', widget.catalog['poses'])),
                          const SizedBox(width: 8),
                          ActionChip(
                              label: Text(_look.background[0].toUpperCase() +
                                  _look.background.substring(1)),
                              avatar: const Icon(Icons.landscape_outlined,
                                  size: 16),
                              onPressed: () => _pick(
                                  'background', widget.catalog['backgrounds'])),
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
                                child: ChoiceChip(
                                    label: Text(c.value),
                                    selected: _category == c.key,
                                    onSelected: _busy
                                        ? null
                                        : (_) =>
                                            setState(() => _category = c.key)))
                        ])),
                Expanded(
                    child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 150,
                                mainAxisExtent: 130,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = Map<String, dynamic>.from(items[i]);
                          final selected = _look.items[_category] == item['id'],
                              owned = _owned.contains(item['id']);
                          return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: _busy ? null : () => _select(item),
                              child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: selected
                                          ? context.neon.brand
                                              .withValues(alpha: .14)
                                          : context.neon.panel,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: selected
                                              ? context.neon.brand
                                              : context.neon.line,
                                          width: selected ? 1.5 : 1)),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                            child: Center(
                                                child: item['thumbnailUrl'] !=
                                                        null
                                                    ? SlayThumbnail(
                                                        url: item[
                                                            'thumbnailUrl'])
                                                    : Icon(
                                                        _category == 'hair'
                                                            ? Icons.face
                                                            : _category ==
                                                                    'shoes'
                                                                ? Icons
                                                                    .ice_skating_outlined
                                                                : _category ==
                                                                        'bags'
                                                                    ? Icons
                                                                        .shopping_bag_outlined
                                                                    : Icons
                                                                        .checkroom_rounded,
                                                        color: selected
                                                            ? context.neon.brand
                                                            : context.neon.mute,
                                                        size: 32))),
                                        Text(item['name'],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 3),
                                        Row(children: [
                                          Expanded(
                                              child: Text(
                                                  owned
                                                      ? (selected
                                                          ? 'Wearing'
                                                          : 'In wardrobe')
                                                      : '${item['coinCost']} coins',
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      color:
                                                          context.neon.mute))),
                                          if (selected)
                                            Icon(Icons.check_circle,
                                                size: 14,
                                                color: context.neon.brand)
                                          else if (!owned)
                                            Icon(Icons.lock_outline,
                                                size: 13,
                                                color: context.neon.mute)
                                        ])
                                      ])));
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
                            builder: (context, ready, _) => FilledButton.icon(
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
                                    ? 'Saving your look…'
                                    : widget.competitionId == null
                                        ? 'Submit & see my score'
                                        : 'Submit this look'))))),
              ]);
            })));
      }));
  Future<void> _pick(String category, List<dynamic> options) async {
    final chosen = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: context.neon.bg,
        builder: (c) => SafeArea(
                child: Wrap(children: [
              for (final option in options)
                ListTile(
                    title: Text(option.toString()[0].toUpperCase() +
                        option.toString().substring(1)),
                    trailing: const Icon(Icons.chevron_right),
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
