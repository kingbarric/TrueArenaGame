import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../onboarding/guest_gate.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';
import 'huud_space_screen.dart';

/// Opens the "Make a Huud" sheet and, once made, walks straight into it.
/// Hosting a Huud already? The server hands that one back instead of making
/// a second, so this is also "take me to my Huud".
///
/// [gameType] pre-picks the first game (from the Games tab); [share] starts
/// with "Show it on the feed" switched on; [onQuickPlay] adds a way out to
/// the game's old quick lobby (bots, solo play).
Future<void> startHuud(BuildContext context, {String? gameType, bool share = false, VoidCallback? onQuickPlay}) async {
  if (!await canHostOrPromptToVerify(context)) return;
  if (!context.mounted) return;
  final made = await showHuudSheet<HuudSpace>(
    context,
    builder: (_) => CreateHuudSheet(gameType: gameType, share: share, onQuickPlay: onQuickPlay),
  );
  if (made == null || !context.mounted) return;
  await openHuudSpace(context, made.id, initial: made);
}

/// Two questions — what's it called, and who can join — then two optional
/// extras: a first game, and sharing it to the feed.
class CreateHuudSheet extends StatefulWidget {
  const CreateHuudSheet({super.key, this.gameType, this.share = false, this.onQuickPlay});

  final String? gameType;
  final bool share;
  final VoidCallback? onQuickPlay;

  @override
  State<CreateHuudSheet> createState() => _CreateHuudSheetState();
}

class _CreateHuudSheetState extends State<CreateHuudSheet> {
  final _name = TextEditingController();
  final _message = TextEditingController();
  HuudPrivacy _privacy = HuudPrivacy.friends;
  late String? _game = widget.gameType;
  late bool _share = widget.share;
  bool _busy = false;
  String? _error;
  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final raw = await AppScope.of(context).api.post('/huud-spaces', {
        'name': _name.text.trim(),
        'privacy': _privacy.wire,
        if (_game != null) 'gameType': _game,
        if (_share) 'share': true,
        if (_share && _message.text.trim().isNotEmpty) 'message': _message.text.trim(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).pop(HuudSpace.fromJson(raw));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "We couldn't reach PlayHuud. Check your internet and try again.");
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
            const Text('🎉', textAlign: TextAlign.center, style: TextStyle(fontSize: 44)),
            const SizedBox(height: 4),
            Text('Make a Huud',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: n.ink)),
            const SizedBox(height: 4),
            Text('A place to hang out and play games together',
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
              onChanged: (_) => setState(() {}),
            ),
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
                child: Text('🛡️ Anyone can come in. Be kind, and never share your address or phone number.',
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
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: n.danger)),
              ),
            const SizedBox(height: 6),
            HuudButton(
              key: const ValueKey('huud-create'),
              label: 'Make my Huud',
              icon: Icons.celebration_rounded,
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
            TextSpan(text: '  (if you like)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: n.mute)),
        ])),
      ),
    ]);
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
            onTap: () => setState(() => _game = game),
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
                        width: 44, height: 44, child: Center(child: Text('💬', style: TextStyle(fontSize: 26))))
                    : HuudGameArt(game, size: 44),
                const SizedBox(height: 4),
                Text(game == null ? 'No game yet' : huudGameName(game),
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
        for (final g in huudGameOrder) tile(g),
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
          const Text('📣', style: TextStyle(fontSize: 22)),
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
            Text(privacy.emoji, style: const TextStyle(fontSize: 28)),
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

/// A game tapped on the Games tab. Hosting a Huud already: go there, and if
/// nothing's set up yet the tapped game becomes the next one (a game that's
/// on is never replaced). No Huud: make one with that game picked — or take
/// [quickPlay] to the game's own quick lobby.
Future<void> openHuudForGame(BuildContext context, String gameType, {VoidCallback? quickPlay}) async {
  final api = AppScope.of(context).api;
  Map<String, dynamic>? current;
  try {
    final raw = await api.get('/huud-spaces/current');
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
  final game = huud.currentGame;
  if (game == null || game.finished) {
    try {
      await api.post('/huud-spaces/${huud.id}/game', {'gameType': gameType});
      huud = HuudSpace.fromJson((await api.get('/huud-spaces/${huud.id}') as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      if (context.mounted) huudSnack(context, e.message);
    } catch (_) {}
  } else if (game.gameType != gameType) {
    huudSnack(context, '${huudGameName(game.gameType)} is on in your Huud — finish it first');
  }
  if (context.mounted) await openHuudSpace(context, huud.id, initial: huud);
}
