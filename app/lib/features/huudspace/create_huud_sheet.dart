import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../onboarding/guest_gate.dart';
import 'go_live_sheet.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';
import 'huud_space_screen.dart';
import 'huud_game_modes.dart';
import '../../widgets/huud_art.dart';

/// Opens the "Make a Huud" sheet and, once made, walks straight into it.
/// Someone with a Huud already makes another — up to [kMaxHuuds], one for
/// each circle — naming it themselves; with five, it says to delete one.
///
/// [gameType] pre-picks the first game (from the Games tab); [share] starts
/// with "Show it on the feed" switched on; [onQuickPlay] adds a way out to
/// the game's old quick lobby (bots, solo play).
Future<void> startHuud(BuildContext context, {String? gameType, bool share = false, VoidCallback? onQuickPlay}) async {
  if (!await canHostOrPromptToVerify(context)) return;
  if (!context.mounted) return;
  var owned = const <MyHuud>[];
  try {
    owned = await ownHuuds(AppScope.of(context).api);
  } catch (_) {
    // Can't tell — the sheet makes a first Huud, and the server reopens yours if you have one.
  }
  if (!context.mounted) return;
  if (owned.length >= kMaxHuuds) {
    huudSnack(context, "You have $kMaxHuuds Huuds — that's the most. Delete one in its settings to make another.");
    return;
  }
  final made = await showHuudSheet<HuudSpace>(
    context,
    builder: (_) => CreateHuudSheet(
        gameType: gameType,
        share: share,
        onQuickPlay: onQuickPlay,
        another: owned.isNotEmpty,
        otherLive: owned.where((h) => h.live).firstOrNull),
  );
  if (made == null || !context.mounted) return;
  await openHuudSpace(context, made.id, initial: made,
      startOnGame: gameType != null || made.currentGame != null);
}

/// Two questions — what's it called, and who can join — then two optional
/// extras: a first game, and sharing it to the feed.
class CreateHuudSheet extends StatefulWidget {
  const CreateHuudSheet(
      {super.key, this.gameType, this.share = false, this.onQuickPlay, this.another = false, this.otherLive});

  final String? gameType;
  final bool share;
  final VoidCallback? onQuickPlay;

  /// You have a Huud already: this one is another, for another circle, and
  /// needs a name of its own.
  final bool another;

  /// Your Huud that's Live now — a new one goes Live, so that one stops.
  final MyHuud? otherLive;

  @override
  State<CreateHuudSheet> createState() => _CreateHuudSheetState();
}

class _CreateHuudSheetState extends State<CreateHuudSheet> {
  final _name = TextEditingController();
  final _message = TextEditingController();
  HuudPrivacy _privacy = HuudPrivacy.friends;
  late String? _game = widget.gameType;

  /// Whot's "classic" or "tell", SlayHuud's "battle" or "group" — asked when the game is picked.
  String? _mode;
  Map<String, dynamic>? _gameConfig;
  late bool _share = widget.share;
  bool _busy = false;
  String? _error;

  /// Something to fix that's safe to say as it is: no name yet, or the server's own reason.
  String? _notice;
  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    if (widget.another) return; // a second Huud gets a name of its own
    final user = AppScope.of(context).user;
    final first =
        (user?.displayName.isNotEmpty == true ? user!.displayName : (user?.username ?? 'My')).split(' ').first;
    _name.text = first.endsWith('s') ? "$first' Huud" : "$first's Huud";
  }

  @override
  void dispose() {
    _name.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    if (widget.another && _name.text.trim().isEmpty) {
      setState(() => _notice = 'Give it a name first — like Family or Friends');
      return;
    }
    final otherLive = widget.otherLive;
    if (otherLive != null && !await confirmSwitchLive(context, otherLive, yes: 'End it and make this one Live')) return;
    if (!mounted) return;
    // A game with modes came already picked: still ask which one.
    final game = _game;
    if (game != null && huudGameHasModes(game) && _mode == null) {
      final setup = await askHuudGameSetup(context, game);
      if (setup == null || !mounted) return;
      setState(() { _mode = setup.mode; _gameConfig = setup.gameConfig; });
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final raw = await AppScope.of(context).api.post('/huud-spaces', {
        'name': _name.text.trim(),
        'privacy': _privacy.wire,
        if (_game != null) 'gameType': _game,
        if (huudGameHasModes(_game) && _mode != null) 'mode': _mode,
        if (_gameConfig != null) 'gameConfig': _gameConfig,
        if (_share) 'share': true,
        if (_share && _message.text.trim().isNotEmpty) 'message': _message.text.trim(),
        if (widget.another) 'another': true,
        if (otherLive != null) 'switchLive': true,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).pop(HuudSpace.fromJson(raw));
    } on ApiException catch (e) {
      // A refusal (five already, one Live, mid-game) says why in its own words.
      if (mounted) {
        setState(() {
          if (e.status == 409) {
            _notice = huudRefusal(e);
          } else {
            _error = e.message;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = userErrorMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Image.asset(huudIcon, width: 72, height: 72)),
            const SizedBox(height: 4),
            Text(widget.another ? 'Make another Huud' : 'Make a Huud',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: n.ink)),
            const SizedBox(height: 4),
            Text(widget.another ? 'One for each circle — family, friends, everyone' : 'A place to hang out and play games together',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: n.mid)),
            const SizedBox(height: 22),
            _label(n, '1', 'Give it a name'),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('huud-name'),
              controller: _name,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: n.ink),
              decoration: InputDecoration(
                counterText: '',
                prefixIcon: Icon(Icons.edit_rounded, color: h.orangeText),
                suffixIcon: _name.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear name',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(_name.clear),
                      ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: h.orange, width: 2.4),
                ),
              ),
              onChanged: (_) => setState(() => _notice = null),
            ),
            if (widget.another) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final pick in const ['Family', 'Friends', 'Game night', 'Work crew', 'Neighbours'])
                  ActionChip(
                    key: ValueKey('huud-name-pick-$pick'),
                    label: Text(pick, style: const TextStyle(fontWeight: FontWeight.w800)),
                    onPressed: () => setState(() {
                      _name.text = pick;
                      _notice = null;
                    }),
                  ),
              ]),
            ],
            const SizedBox(height: 18),
            _label(n, '2', 'Who can join?'),
            const SizedBox(height: 8),
            for (final p in HuudPrivacy.values) ...[
              _PrivacyChoice(
                privacy: p,
                selected: _privacy == p,
                onTap: () => setState(() => _privacy = p),
              ),
              const SizedBox(height: 10),
            ],
            if (_privacy == HuudPrivacy.public)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: HuudText('🛡️ Anyone can come in. Be kind, and never share your address or phone number.',
                    style: TextStyle(fontSize: 14, height: 1.35, color: n.mid)),
              ),
            const SizedBox(height: 8),
            _label(n, '3', 'Pick a game', optional: true),
            const SizedBox(height: 8),
            _gamePicker(n),
            const SizedBox(height: 18),
            _label(n, '4', 'Show it on the feed', optional: true),
            const SizedBox(height: 8),
            _shareBox(n),
            const SizedBox(height: 16),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_notice!,
                    key: const ValueKey('huud-create-notice'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: n.danger)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(userErrorMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: n.danger)),
              ),
            const SizedBox(height: 6),
            HuudButton(
              key: const ValueKey('huud-create'),
              label: widget.another ? 'Make this Huud' : 'Make my Huud',
              icon: Icons.add_rounded,
              image: huudIcon,
              big: true,
              expand: true,
              busy: _busy,
              onPressed: _create,
            ),
            if (widget.onQuickPlay != null) ...[
              const SizedBox(height: 6),
              TextButton(
                key: const ValueKey('huud-quick-play'),
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onQuickPlay!();
                },
                child: Text('Just play a quick game instead',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: HuudColors.of(context).orangeText)),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _label(NeonColors n, String step, String text, {bool optional = false}) {
    final h = HuudColors.of(context);
    return Row(children: [
      Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: h.orange, shape: BoxShape.circle, border: Border.all(color: kCabinetInk, width: 2)),
        child: Text(step, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: h.onOrange)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text.rich(TextSpan(children: [
          TextSpan(text: text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: n.ink)),
          if (optional)
            TextSpan(
                text: '  (if you like)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: n.mute)),
        ])),
      ),
    ]);
  }

  /// Whot and SlayHuud are two games each: ask which as it's picked.
  Future<void> _pick(String? game) async {
    if (game != null && huudGameHasModes(game)) {
      final setup = await askHuudGameSetup(context, game);
      if (setup == null || !mounted) return;
      setState(() {
        _game = game;
        _mode = setup.mode;
        _gameConfig = setup.gameConfig;
      });
      return;
    }
    setState(() {
      _game = game;
      _mode = null;
      _gameConfig = null;
    });
  }

  Widget _gamePicker(NeonColors n) {
    final h = HuudColors.of(context);
    Widget tile(String? game) {
      final on = _game == game;
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Semantics(
          button: true,
          selected: on,
          label: game == null ? 'No game yet' : huudGameName(game),
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('huud-first-game-${game ?? 'none'}'),
            onTap: () => _pick(game),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 84,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: on ? h.orangeSoft : n.panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: on ? h.orange : n.line, width: on ? 2.6 : 1.4),
              ),
              child: Column(children: [
                game == null
                    ? const SizedBox(
                        width: 44, height: 44, child: Center(child: HuudText('💬', style: TextStyle(fontSize: 26))))
                    : HuudGameArt(game, size: 44),
                const SizedBox(height: 4),
                Text(
                    game == null
                        ? 'No game yet'
                        : game == 'whot' && on && _mode == 'tell'
                            ? 'The Tell'
                            : game == 'slayhuud' && on && _mode == 'group'
                                ? 'Group Show'
                                : huudGameName(game),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: n.ink)),
              ]),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 92,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        tile(null),
        // The game the Huud was opened for leads, so it's in view already picked.
        if (huudGameOrder.contains(widget.gameType)) tile(widget.gameType),
        for (final g in huudGameOrder)
          if (g != widget.gameType) tile(g),
      ]),
    );
  }

  Widget _shareBox(NeonColors n) {
    final h = HuudColors.of(context);
    final hint = _game == null ? 'Come hang out!' : 'Who wants to play ${huudGameName(_game)}?';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      decoration: BoxDecoration(
        color: _share ? h.orangeSoft : n.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _share ? h.orange : n.line, width: _share ? 2.2 : 1.4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const HuudText('📣', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_share ? 'People will see it on the feed' : 'Keep it off the feed',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: n.ink)),
          ),
          Switch(
            key: const ValueKey('huud-share-switch'),
            value: _share,
            activeThumbColor: h.onOrange,
            activeTrackColor: h.orange,
            onChanged: (v) => setState(() => _share = v),
          ),
        ]),
        if (_share)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 6, 8),
            child: TextField(
              key: const ValueKey('huud-share-message'),
              controller: _message,
              maxLength: 140,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: n.ink),
              decoration: InputDecoration(
                counterText: '',
                hintText: hint,
                filled: true,
                fillColor: n.panel,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
      ]),
    );
  }
}

class _PrivacyChoice extends StatelessWidget {
  const _PrivacyChoice({required this.privacy, required this.selected, required this.onTap});
  final HuudPrivacy privacy;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    return Semantics(
      selected: selected,
      button: true,
      label: '${privacy.label}. ${privacy.explain}',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('huud-privacy-${privacy.wire}'),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? h.orangeSoft : n.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? h.orange : n.line, width: selected ? 2.6 : 1.4),
          ),
          child: Row(children: [
            HuudText(privacy.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(privacy.label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: n.ink)),
                const SizedBox(height: 2),
                Text(privacy.explain, style: TextStyle(fontSize: 14, color: n.mid)),
              ]),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? h.orange : Colors.transparent,
                border: Border.all(color: selected ? kCabinetInk : n.mute, width: 2),
              ),
              child: selected ? Icon(Icons.check_rounded, size: 18, color: h.onOrange) : null,
            ),
          ]),
        ),
      ),
    );
  }
}

/// A game tapped on the Games tab. With a Huud of your own: go there (with
/// several, you pick which — the Live one first), and if nothing's set up yet
/// the tapped game becomes the next one (a game that's on is never replaced).
/// No Huud: make one with that game picked — or take [quickPlay] to the
/// game's own quick lobby.
Future<void> openHuudForGame(BuildContext context, String gameType, {VoidCallback? quickPlay}) async {
  final api = AppScope.of(context).api;
  var owned = const <MyHuud>[];
  try {
    owned = await ownHuuds(api);
  } catch (_) {
    // Can't tell — carry on as with one Huud.
  }
  if (!context.mounted) return;
  String? picked;
  if (owned.length > 1) {
    picked = await showHuudSheet<String>(context, builder: (_) => _HuudForGameSheet(gameType: gameType, huuds: owned));
    if (picked == null || !context.mounted) return;
    if (picked == _newHuud) {
      await startHuud(context, gameType: gameType, onQuickPlay: quickPlay);
      return;
    }
  }
  Map<String, dynamic>? current;
  try {
    // One Huud (or none): "yours" — the server's Live one, else the newest.
    final raw = await api.get(picked == null ? '/huud-spaces/current' : '/huud-spaces/$picked');
    if (raw is Map && raw.isNotEmpty) current = raw.cast<String, dynamic>();
  } catch (_) {
    // Can't tell — offer to make one; the server reopens yours if it exists.
  }
  if (!context.mounted) return;
  if (current == null) {
    await startHuud(context, gameType: gameType, onQuickPlay: quickPlay);
    return;
  }
  var huud = HuudSpace.fromJson(current);
  if (!huud.live) {
    // Your Huud is offline — Go Live first, then the game goes on.
    final live = await goLive(context, huud.id);
    if (!context.mounted) return;
    if (live == null) return;
    huud = live;
  }
  final game = huud.currentGame;
  if (game == null || game.finished) {
    // Which Traitors, Whot or SlayHuud — asked before the table is set.
    HuudGameSetup? setup;
    if (huudGameHasModes(gameType)) {
      setup = await askHuudGameSetup(context, gameType);
      if (setup == null || !context.mounted) return;
    }
    try {
      await api.post('/huud-spaces/${huud.id}/game', {'gameType': gameType, if (setup != null) 'mode': setup.mode,
          if (setup?.gameConfig != null) 'gameConfig': setup!.gameConfig});
      huud = HuudSpace.fromJson((await api.get('/huud-spaces/${huud.id}') as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      if (context.mounted) huudSnack(context, huudRefusal(e));
      return;
    } catch (_) {
      if (context.mounted) huudSnack(context, userErrorMessage);
      return;
    }
  }
  final notice = game != null && !game.finished && game.gameType != gameType
      ? 'You already have ${huudGameName(game.gameType)} open. End it or put it away from this Games tab before choosing ${huudGameName(gameType)}.'
      : null;
  if (context.mounted) await openHuudSpace(context, huud.id, initial: huud, startOnGame: true, gameNotice: notice);
}

/// What the picker returns for "make another Huud instead".
const _newHuud = 'new';

/// Which of your Huuds gets the game — the Live one first — or another new one.
class _HuudForGameSheet extends StatelessWidget {
  const _HuudForGameSheet({required this.gameType, required this.huuds});
  final String gameType;
  final List<MyHuud> huuds;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: HuudGameArt(gameType, size: 64)),
          const SizedBox(height: 8),
          Text('Play ${huudGameName(gameType)} in…',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: n.ink)),
          const SizedBox(height: 4),
          Text('Pick one of your Huuds', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: n.mid)),
          const SizedBox(height: 16),
          for (final huud in huuds) ...[
            HuudCard(
              key: ValueKey('game-huud-${huud.id}'),
              highlight: huud.live,
              onTap: () => Navigator.of(context).pop(huud.id),
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(huud.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: n.ink)),
                    const SizedBox(height: 2),
                    Text(huud.live ? 'Live now' : 'Offline — it goes Live for the game',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: huud.live ? h.orangeText : n.mute)),
                  ]),
                ),
                if (huud.live) const HuudLiveChip() else Icon(Icons.chevron_right_rounded, color: n.mute, size: 28),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          if (huuds.length < kMaxHuuds)
            HuudButton(
              key: const ValueKey('game-huud-new'),
              label: 'Make another Huud',
              icon: Icons.add_rounded,
              kind: HuudButtonKind.soft,
              expand: true,
              onPressed: () => Navigator.of(context).pop(_newHuud),
            ),
        ]),
      ),
    );
  }
}
