import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_state.dart';
import 'slay_assets.dart';
import 'slay_models.dart';
import 'slay_stage.dart';
import 'slay_theme.dart';
import 'slay_ui.dart';
import '../../theme/neon_theme.dart';
import 'slay_game_menu.dart';
import 'slay_pose_picker.dart';
import 'slay_results.dart';
import 'slay_colour_picker.dart';
import 'slay_wardrobe.dart';

class SlayStudioScreen extends StatefulWidget {
  const SlayStudioScreen(
      {super.key,
      required this.catalog,
      required this.theme,
      required this.owned,
      this.competitionId,
      this.careerEventId,
      this.careerPeriod,
      this.initialBackground,
      this.initialBody = 'female',
      this.careerCharacter,
      this.deadline});
  final Map<String, dynamic> catalog, theme;
  final Set<String> owned;
  final String? competitionId, careerEventId, careerPeriod, initialBackground;
  final String initialBody;
  final DateTime? deadline;

  /// The career's chosen character, its open clothing, poses and lock reasons.
  /// When set, body and character are fixed and the stage sets the scene.
  final Map<String, dynamic>? careerCharacter;
  @override
  State<SlayStudioScreen> createState() => _SlayStudioScreenState();
}

class _SlayStudioScreenState extends State<SlayStudioScreen> {
  late SlayLook _look = SlayLook.initial(
          widget.careerCharacter?['body'] as String? ??
              ((widget.theme['bodyEligibility'] as List)
                      .contains(widget.initialBody)
                  ? widget.initialBody
                  : (widget.theme['bodyEligibility'] as List).first as String))
      .copy(
          background: widget.initialBackground,
          avatarId: widget.careerCharacter?['avatarId'] as String?);
  late final Set<String> _owned = {...widget.owned};
  bool get _career => widget.careerCharacter != null;
  late final Set<String> _careerItems =
      Set<String>.from(widget.careerCharacter?['items'] ?? const []);
  late final Map<String, String> _careerLocks =
      Map<String, String>.from(widget.careerCharacter?['locks'] ?? const {});
  static const _beauty = {'hair', 'makeup', 'eyes'};

  /// Whether this piece can be worn here: career stages gate clothing,
  /// ownership gates everything else.
  bool _usable(Map item) => _career && !_beauty.contains(item['category'])
      ? _careerItems.contains(item['id'])
      : _owned.contains(item['id']);
  final _stage = SlayStageController();
  String _category = 'outfit', _styleGroup = '';

  /// Until the player picks a tab, a career opens where there is something to wear.
  bool _categoryChosen = false;
  SlayLook? _draft;
  int? _coins;
  bool _selecting = false;
  int _walletRevision = 0;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restore();
      _wallet();
    });
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
      'slay-draft-${AppScope.of(context).user?.id}-${_look.body}${_career ? '-career' : ''}';
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final raw = prefs.getString(_draftKey);
    if (raw == null) return;
    try {
      final look =
          SlayLook.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
      final available = (widget.catalog['items'] as List)
          .where((item) => item['assetUrl'] != null && _usable(item))
          .map((item) => item['id'])
          .toSet();
      if (look.body == _look.body &&
          (look.avatarId == null ||
              (widget.catalog['avatars'] as List).any(
                  (a) => a['body'] == look.body && a['id'] == look.avatarId)) &&
          look.items.values.every(available.contains) &&
          mounted) {
        setState(() => _draft = look);
      }
    } catch (_) {}
  }

  Future<void> _wallet() async {
    final revision = ++_walletRevision;
    try {
      final wallet = await AppScope.of(context).fetchWallet(limit: 0);
      if (mounted && revision == _walletRevision) {
        setState(() => _coins = wallet.balance);
      }
    } catch (_) {/* Purchases still use the server's balance check. */}
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
    if (_busy || _selecting) return;
    setState(() => _selecting = true);
    final id = item['id'] as String;
    if (_career && !_usable(item)) {
      setState(() => _selecting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🔒 ${item['name']}: '
              '${_careerLocks[id] ?? 'not part of this career stage'}. Keep slaying!')));
      return;
    }
    try {
      if (!_owned.contains(id)) {
        final cost = (item['coinCost'] as num).toInt();
        final purchase =
            await showSlayUnlock(context, item['name'], cost, _coins);
        if (purchase != true || !mounted) return;
        await AppScope.of(context)
            .api
            .post('/slay/wardrobe/buy', {'itemId': id});
        if (!mounted) return;
        ++_walletRevision;
        setState(() {
          _owned.add(id);
          if (_coins != null) _coins = _coins! - cost;
        });
        unawaited(_wallet());
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${item['name']} unlocked!')));
      }
      if (mounted) _change(_look.equip(item));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _selecting || !_look.isDressed) return;
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
        final score = widget.careerEventId == null
            ? await api.score(widget.theme['id'], id)
            : await api.careerScore(widget.careerEventId!, id,
                period: widget.careerPeriod);
        if (!mounted) return;
        final done = await SlayResultsScreen.show(context,
            score: score,
            title: widget.theme['title'],
            location: _look.background,
            career: widget.careerEventId != null);
        if (done == true && mounted) Navigator.pop(context, true);
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
        final wardrobe = SlayWardrobe(widget.catalog, _look.body);
        final categories = _categories.entries
            .where((c) => wardrobe.categories.contains(c.key))
            .toList();
        final wearable = _career && !_categoryChosen
            ? categories
                .where((c) => wardrobe.itemsFor(c.key).any(_usable))
                .firstOrNull
                ?.key
            : null;
        final category = wearable ??
            (categories.any((c) => c.key == _category)
                ? _category
                : categories.firstOrNull?.key ?? '');
        final clothing = SlayWardrobe.clothing.contains(category);
        final groups = wardrobe.groupsFor(category);
        // A career opens on a style group with something wearable in it.
        final selectedGroup = groups.contains(_styleGroup)
            ? _styleGroup
            : (_career
                    ? groups
                        .where((g) => wardrobe
                            .itemsFor(category, clothing ? g : null)
                            .any(_usable))
                        .firstOrNull
                    : null) ??
                groups.firstOrNull;
        final items =
            wardrobe.itemsFor(category, clothing ? selectedGroup : null);
        // In a career, what you can wear now comes before what unlocks later.
        if (_career) {
          items.sort(
              (a, b) => (_usable(a) ? 0 : 1).compareTo(_usable(b) ? 0 : 1));
        }
        final equippedSlots = _look.items.entries
            .where((entry) => wardrobe.categoryForId(entry.value) == category)
            .map((entry) => entry.key)
            .toList();
        final canRemove = [
          'outfit',
          'dress',
          'tops',
          'shirts',
          'trousers',
          'skirts',
          'shoes',
          'eyes',
          'makeup',
          'jewellery',
          'watches',
          'bags',
          'glasses',
          'headwear',
          'accessories'
        ].contains(category);
        return Scaffold(
            appBar: AppBar(
                title: Text(_career ? 'Dressing room' : 'Your studio',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _career
                            ? SlayStageLook.of(_look.background).ink
                            : null)),
                foregroundColor:
                    _career ? SlayStageLook.of(_look.background).ink : null,
                flexibleSpace: _career
                    ? Container(
                        decoration: BoxDecoration(
                            gradient:
                                SlayStageLook.of(_look.background).gradient,
                            border: const Border(
                                bottom: BorderSide(
                                    color: kCabinetInk, width: 2.5))))
                    : null,
                actions: [
                  Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Center(
                          child: SlayLabel(widget.deadline == null
                              ? (_coins == null
                                  ? 'Practice look'
                                  : '$_coins coins')
                              : _timeLeft))),
                  SlayGameMenu(
                      onBrief: _brief,
                      onReset: (_busy || _selecting)
                          ? null
                          : () => _change(SlayLook.initial(_look.body).copy(
                              avatarId: _look.avatarId,
                              background: _look.background)),
                      exitLabel: 'Back to SlayHuud',
                      onExit: () => leaveSlayScreen(context)),
                ]),
            body:
                SafeArea(child: LayoutBuilder(builder: (context, constraints) {
              final stageHeight =
                  (constraints.maxHeight * .41).clamp(180.0, 400.0);
              return Column(children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            SlayLabel(_career
                                ? 'YOU’RE STYLING FOR'
                                : 'Your challenge'),
                            const SizedBox(height: 4),
                            Text(widget.theme['title'],
                                style:
                                    Theme.of(context).textTheme.headlineMedium),
                            if (_required.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _checklist(context),
                            ],
                          ])),
                      if (widget.competitionId == null && !_career)
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: [
                            for (final body in ['female', 'male'])
                              if ((widget.theme['bodyEligibility'] as List)
                                  .contains(body))
                                ButtonSegment(
                                    value: body,
                                    icon: Icon(
                                        body == 'female'
                                            ? Icons.female
                                            : Icons.male,
                                        size: 16),
                                    label:
                                        Text(body == 'female' ? 'Her' : 'Him')),
                          ],
                          selected: {_look.body},
                          style: SegmentedButton.styleFrom(
                            backgroundColor: context.neon.panel,
                            foregroundColor: context.neon.mute,
                            selectedBackgroundColor: context.neon.gold,
                            selectedForegroundColor: context.neon.onAccent,
                            side: BorderSide(color: context.neon.line),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                          onSelectionChanged: (_busy || _selecting)
                              ? null
                              : (selected) {
                                  setState(() {
                                    _look = SlayLook.initial(selected.single);
                                    _category = 'outfit';
                                    _draft = null;
                                    _styleGroup = '';
                                  });
                                  _restore();
                                },
                        )
                    ])),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(
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
                                              valueListenable:
                                                  _stage.showcasePhase,
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
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: Tooltip(
                                              message: preset == 'feet'
                                                  ? 'Shoe close-up'
                                                  : preset == 'back'
                                                      ? 'Back view'
                                                      : preset == 'face'
                                                          ? 'Face close-up'
                                                          : 'Full look',
                                              child: IconButton.filledTonal(
                                                  style: IconButton.styleFrom(
                                                    backgroundColor: context
                                                        .neon.panel
                                                        .withValues(alpha: .94),
                                                    foregroundColor:
                                                        context.neon.ink,
                                                    minimumSize:
                                                        const Size(40, 40),
                                                    shape: CircleBorder(
                                                        side: BorderSide(
                                                            color: context
                                                                .neon.line)),
                                                  ),
                                                  onPressed: () => _stage
                                                          .request(
                                                              'setCamera', {
                                                        'preset': preset
                                                      }).catchError((_) =>
                                                              <String,
                                                                  dynamic>{}),
                                                  icon: Icon(
                                                      semanticLabel: preset ==
                                                              'feet'
                                                          ? 'Shoe close-up'
                                                          : preset == 'back'
                                                              ? 'Back view'
                                                              : preset == 'face'
                                                                  ? 'Face close-up'
                                                                  : 'Full look',
                                                      preset == 'feet'
                                                          ? Icons
                                                              .ice_skating_outlined
                                                          : preset == 'back'
                                                              ? Icons
                                                                  .rotate_right
                                                              : preset == 'face'
                                                                  ? Icons
                                                                      .face_outlined
                                                                  : Icons
                                                                      .open_in_full,
                                                      size: 20))))
                                  ])),
                              Positioned(
                                  bottom: 12,
                                  left: 14,
                                  child: Container(
                                      decoration: BoxDecoration(
                                          color: context.neon.panel
                                              .withValues(alpha: .94),
                                          borderRadius:
                                              BorderRadius.circular(100),
                                          border: Border.all(
                                              color: context.neon.line,
                                              width: 1.5),
                                          boxShadow: const [
                                            BoxShadow(
                                                color: kCabinetInk,
                                                blurRadius: 6,
                                                offset: Offset(0, 2))
                                          ]),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                                tooltip: 'Turn left',
                                                icon: const Icon(
                                                    Icons.rotate_left,
                                                    size: 20),
                                                onPressed: () => _stage.request(
                                                        'rotateCamera', {
                                                      'radians': -.785398
                                                    }).catchError((_) =>
                                                        <String, dynamic>{})),
                                            const SlayLabel('Rotate'),
                                            IconButton(
                                                tooltip: 'Turn right',
                                                icon: const Icon(
                                                    Icons.rotate_right,
                                                    size: 20),
                                                onPressed: () => _stage.request(
                                                        'rotateCamera', {
                                                      'radians': .785398
                                                    }).catchError((_) =>
                                                        <String, dynamic>{})),
                                          ])))
                            ])))),
                const SizedBox(height: 12),
                SizedBox(
                    height: 48,
                    child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          if (_draft != null &&
                              !_look.isDressed &&
                              _draft!.isDressed) ...[
                            SlayPill(
                                label: 'My last look',
                                icon: Icons.history_rounded,
                                onPressed: (_busy || _selecting)
                                    ? null
                                    : () => _change(_draft!)),
                            const SizedBox(width: 8),
                          ],
                          SlayShowOffControl(
                              controller: _stage,
                              enabled: !_busy && !_selecting,
                              onFinished: (pose) =>
                                  _change(_look.copy(pose: pose)),
                              onError: (error) =>
                                  setState(() => _error = error.toString())),
                          const SizedBox(width: 8),
                          SlayPill(
                              label: 'Face & hair',
                              icon: Icons.face_retouching_natural,
                              onPressed: (_busy || _selecting)
                                  ? null
                                  : () => _customise()),
                          const SizedBox(width: 8),
                          SlayPill(
                              label:
                                  'Pose · ${slayPoses[_look.pose]?.label ?? _look.pose}',
                              icon: Icons.accessibility_new,
                              onPressed: (_busy || _selecting)
                                  ? null
                                  : () => _pick(
                                      'pose',
                                      _career
                                          ? widget.careerCharacter!['poses']
                                          : widget.catalog['poses'])),
                          const SizedBox(width: 8),
                          if (!_career)
                            SlayPill(
                                label: 'Background',
                                icon: Icons.landscape_outlined,
                                onPressed: (_busy || _selecting)
                                    ? null
                                    : () => _pick('background',
                                        widget.catalog['backgrounds'])),
                        ])),
                const SizedBox(height: 4),
                Divider(
                    height: 16,
                    thickness: 1,
                    indent: 16,
                    endIndent: 16,
                    color: context.neon.line),
                SizedBox(
                    height: 42,
                    child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final c in categories)
                            Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: SlayTab(
                                    label:
                                        '${slayCategoryEmoji[c.key] ?? '✨'} ${c.value}',
                                    selected: category == c.key,
                                    onPressed: (_busy || _selecting)
                                        ? null
                                        : () => setState(() {
                                              _category = c.key;
                                              _categoryChosen = true;
                                              _styleGroup = '';
                                            })))
                        ])),
                if (clothing) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                      height: 36,
                      child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            for (final group in groups)
                              Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: SlayTab(
                                      pill: true,
                                      label: group,
                                      selected: selectedGroup == group,
                                      onPressed: (_busy || _selecting)
                                          ? null
                                          : () => setState(
                                              () => _styleGroup = group)))
                          ])),
                ],
                if ({'shoes', 'shirts', 'tops'}.contains(category) &&
                    _look.items.containsKey(category))
                  SlayColourPicker(
                      palette: Map<String, String>.from(
                          widget.catalog['itemColourPalette'] ?? {}),
                      selected: _look.itemColours[category],
                      enabled: !_busy && !_selecting,
                      onChanged: (colour) {
                        final colours = {..._look.itemColours};
                        if (colour == null) {
                          colours.remove(category);
                        } else {
                          colours[category] = colour;
                        }
                        _change(_look.copy(itemColours: colours));
                      }),
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
                                selected: equippedSlots.isEmpty,
                                owned: true,
                                onTap: (_busy || _selecting)
                                    ? null
                                    : () => _change(_look.copy(
                                        items: {..._look.items}
                                          ..removeWhere((slot, _) =>
                                              equippedSlots.contains(slot)))));
                          }
                          final item = Map<String, dynamic>.from(
                              items[i - (canRemove ? 1 : 0)]);
                          final selected = _look.items.values.any((id) =>
                                  wardrobe.canonicalId(id) == item['id']),
                              owned = _usable(item);
                          return SlayWardrobeTile(
                            name: item['name'],
                            thumbnail: item['thumbnailUrl'],
                            dye: (widget.catalog['wardrobePresentation']
                                as Map?)?[item['id']]?['dye'],
                            selected: selected,
                            owned: owned,
                            lockLabel: _career && !owned
                                ? (_careerLocks[item['id']] ?? 'Locked')
                                : null,
                            coins: (item['coinCost'] as num?)?.toInt() ?? 0,
                            onTap: (_busy || _selecting)
                                ? null
                                : () => _select(item),
                          );
                        })),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12))),
                if (!_busy)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: _tipBubble(context)),
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                        width: double.infinity,
                        child: ValueListenableBuilder<bool>(
                            valueListenable: _stage.ready,
                            builder: (context, ready, _) => _hopWhenReady(
                                ready &&
                                    !_busy &&
                                    !_selecting &&
                                    _missing.isEmpty,
                                SlayButton.icon(
                                    onPressed: _busy ||
                                            _selecting ||
                                            !_look.isDressed ||
                                            !ready ||
                                            (widget.deadline != null &&
                                                !DateTime.now()
                                                    .isBefore(widget.deadline!))
                                        ? null
                                        : _submit,
                                    icon: (_busy || _selecting)
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Icon(Icons.auto_awesome,
                                            size: 18),
                                    label: Text(_selecting
                                        ? 'Updating wardrobe…'
                                        : _busy
                                            ? (_performing
                                                ? 'Taking the stage…'
                                                : 'Saving your look…')
                                            : !_look.isDressed
                                                ? 'Add a look or top + bottoms'
                                                : widget.competitionId == null
                                                    ? 'Show off & see my score'
                                                    : 'Show off & submit')))))),
              ]);
            })));
      }));
  Future<void> _pick(String category, List<dynamic> options) async {
    final chosen = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: context.neon.bg,
        builder: (c) => category == 'pose'
            ? SlayPosePicker(
                selected: _look.pose,
                available: options.cast<String>(),
                onSelected: (pose) => Navigator.pop(c, pose))
            : SafeArea(
                child: Wrap(children: [
                for (final option in options)
                  ListTile(
                      title: Text(option.toString()[0].toUpperCase() +
                          option.toString().substring(1)),
                      trailing: Icon(
                          _look.background == option
                              ? Icons.check_circle_rounded
                              : Icons.chevron_right,
                          color: _look.background == option
                              ? context.neon.gold
                              : null),
                      onTap: () => Navigator.pop(c, option))
              ])));
    if (chosen != null && mounted) {
      if (category == 'pose') {
        await _previewPose(chosen);
      } else {
        _change(_look.copy(background: chosen));
      }
    }
  }

  Future<void> _previewPose(String pose) async {
    if (_busy || _selecting) return;
    setState(() {
      _busy = true;
      _performing = true;
      _error = null;
    });
    _change(_look.copy(pose: pose));
    try {
      // Let the stage's look-change update queue before our acknowledgement;
      // a later automatic apply would otherwise interrupt the new catwalk.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      // Acknowledge the selected finish before starting its runway preview.
      await _stage.request('applyLook', {'look': _look.toJson()});
      if (!mounted) return;
      await _stage.showOff();
    } catch (error) {
      if (mounted &&
          !error.toString().contains('cancelled') &&
          !error.toString().contains('restarted')) {
        setState(() => _error = error.toString());
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

  List<String> get _required =>
      List<String>.from(widget.theme['requiredCategories'] ?? const []);

  String? _categoryOf(String id) => (widget.catalog['items'] as List)
      .cast<Map>()
      .where((i) => i['id'] == id)
      .firstOrNull?['category'] as String?;

  bool _wearing(String category) => category == 'outfit'
      ? _look.isDressed
      : _look.items.values.any((id) => _categoryOf(id) == category);

  /// Brief items still missing from the look.
  List<String> get _missing => _required.where((c) => !_wearing(c)).toList();

  Widget _checklist(BuildContext context) {
    final n = context.neon;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final category in _required)
        Builder(builder: (context) {
          final done = _wearing(category);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: done ? n.jade.withValues(alpha: .22) : n.plate,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: done ? n.jade : n.line, width: 1.5),
            ),
            child: Text(
                '${done ? '✅' : '⬜'} ${slayCategoryEmoji[category] ?? '✨'} ${slayCategoryName(category)}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          );
        }),
    ]);
  }

  /// One friendly sentence that always says what to do next.
  String get _tip {
    if (!_look.isDressed) {
      return '👗 Tap a dress, or a top and some bottoms, to get dressed!';
    }
    final missing = _missing.where((c) => c != 'outfit').firstOrNull;
    if (missing != null) {
      return 'Your brief needs ${slayCategoryEmoji[missing] ?? '✨'} ${slayCategoryName(missing)}. '
          'Tap the ${_categories[missing] ?? missing} tab!';
    }
    return '✨ Looking great! Tap the big button to show it off!';
  }

  Widget _tipBubble(BuildContext context) {
    final n = context.neon;
    return Semantics(
      liveRegion: true,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Container(
          key: ValueKey(_tip),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: n.gold.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: n.gold.withValues(alpha: .7), width: 1.5),
          ),
          child: Text(_tip,
              style: TextStyle(
                  color: n.ink, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _hopWhenReady(bool ready, Widget button) =>
      ready ? IdleBounce(child: button) : button;

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
                      const SizedBox(height: 12),
                      if (!_career) ...[
                        const SlayLabel('Your character'),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: [
                          for (final avatar
                              in widget.catalog['avatars'] as List)
                            if (avatar['body'] == _look.body)
                              ChoiceChip(
                                avatar: avatar['thumbnailUrl'] == null ||
                                        SlayAssets.instance.thumbnail(
                                                avatar['thumbnailUrl']) ==
                                            null
                                    ? const Icon(Icons.face_rounded, size: 18)
                                    : CircleAvatar(
                                        radius: 14,
                                        backgroundImage: SlayAssets.instance
                                            .thumbnail(avatar['thumbnailUrl'])),
                                label: Text(avatar['name'] ?? 'Original'),
                                selected: (_look.avatarId ?? _look.body) ==
                                    (avatar['id'] ?? avatar['body']),
                                onSelected: (_) {
                                  _change(_look.copy(
                                      avatarId:
                                          avatar['id'] ?? avatar['body']));
                                  Navigator.pop(c);
                                },
                              )
                        ]),
                      ],
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
