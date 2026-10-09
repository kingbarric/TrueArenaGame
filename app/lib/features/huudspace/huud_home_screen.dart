import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../lobby/joined_room_screen.dart';
import 'create_huud_sheet.dart';
import 'go_live_sheet.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';
import 'huud_space_screen.dart';

/// The Huud tab: your Huud (Go Live, or step back in), a box for a friend's
/// code, and every Huud you belong to — Live ones first. A Huud stays; going
/// Live is when people hang out in it.
class HuudHomeScreen extends StatefulWidget {
  const HuudHomeScreen({super.key});

  @override
  State<HuudHomeScreen> createState() => _HuudHomeScreenState();
}

class _HuudHomeScreenState extends State<HuudHomeScreen> {
  List<MyHuud>? _huuds;
  String? _error;
  bool _loading = false;
  final _code = TextEditingController();
  bool _joining = false;
  String? _goingLive;
  StreamSubscription? _events;
  Timer? _refresh;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _events = AppScope.of(context).huudSpaceEvents.listen((_) => _load());
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _events?.cancel();
    _refresh?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = AppScope.of(context);
    if (app.api.bearer == null || _loading) return;
    _loading = true;
    try {
      final raw = await app.api.get('/huud-spaces/mine') as List;
      if (!mounted) return;
      setState(() {
        _huuds = raw.map((e) => MyHuud.fromJson((e as Map).cast<String, dynamic>())).toList();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "We couldn't reach PlayHuud. Pull down to try again.");
    } finally {
      _loading = false;
    }
  }

  Future<void> _open(String id) async {
    await openHuudSpace(context, id);
    if (mounted) _load();
  }

  Future<void> _make() async {
    await startHuud(context);
    if (mounted) _load();
  }

  Future<void> _goLive(MyHuud huud) async {
    setState(() => _goingLive = huud.id);
    final live = await goLive(context, huud.id);
    if (mounted) setState(() => _goingLive = null);
    if (live != null && mounted) {
      await openHuudSpace(context, live.id, initial: live);
      if (mounted) _load();
    }
  }

  Future<void> _joinWithCode() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length != 6) {
      huudSnack(context, 'A code has 6 letters and numbers.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _joining = true);
    final app = AppScope.of(context);
    try {
      final raw = await app.api.post('/huud-spaces/join', {'code': code}) as Map<String, dynamic>;
      _code.clear();
      if (!mounted) return;
      final huud = HuudSpace.fromJson(raw);
      await openHuudSpace(context, huud.id, initial: huud);
      if (mounted) _load();
    } on ApiException catch (e) {
      if (e.status != 404) {
        if (mounted) huudSnack(context, e.message);
        return;
      }
      // Not a Huud code — maybe it's a game code someone shared.
      try {
        final room =
            RoomView.fromJson((await app.api.post('/rooms/join', {'code': code}) as Map).cast<String, dynamic>());
        _code.clear();
        await app.rememberActiveRoom(room.id);
        if (mounted) await Navigator.of(context).push(MaterialPageRoute(builder: (_) => JoinedRoomScreen(room: room)));
      } catch (_) {
        if (mounted) huudSnack(context, e.message);
      }
    } catch (_) {
      if (mounted) huudSnack(context, "We couldn't reach PlayHuud. Check your internet.");
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final huuds = _huuds ?? const <MyHuud>[];
    final mine = huuds.where((h) => h.youOwn).firstOrNull;
    final others = huuds.where((h) => !h.youOwn).toList();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                sliver: SliverToBoxAdapter(child: _header(n)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                sliver: SliverList.list(children: [
                  if (_huuds == null && _error == null)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                  else if (_huuds == null)
                    HuudFriendlyState(
                      emoji: '📡',
                      title: 'Hmm, no connection',
                      message: _error!,
                      action: HuudButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: _load),
                    )
                  else if (mine == null)
                    _makeHero()
                  else
                    _yourHuud(mine),
                  const SizedBox(height: 14),
                  _codeCard(n),
                  const SizedBox(height: 28),
                  HuudSectionTitle("Huuds you're in",
                      emoji: '🏠',
                      trailing: others.isEmpty
                          ? null
                          : HuudChip('${others.length}', color: HuudColors.of(context).orangeText)),
                  if (_huuds != null && others.isEmpty)
                    const HuudFriendlyState(
                      emoji: '🌱',
                      title: 'None yet',
                      message: "Join a friend's Huud with their code. You'll hear from it whenever it goes Live.",
                    ),
                  for (final h in others) ...[_otherHuud(n, h), const SizedBox(height: 12)],
                ]),
              ),
              // Clear of the shell's floating nav.
              const SliverToBoxAdapter(child: SizedBox(height: 130)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(NeonColors n) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Image.asset(huudIcon, width: 44, height: 44),
          const SizedBox(width: 10),
          Text('Huud', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: n.ink, height: 1.05)),
        ]),
        const SizedBox(height: 4),
        Text('Your place to hang out — it stays, you go Live',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: n.mid)),
      ]);

  Widget _makeHero() => HuudHeroCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Image.asset(huudIcon, width: 60, height: 60),
          const SizedBox(height: 6),
          const Text('Make your Huud',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kCabinetInk, height: 1.1)),
          const SizedBox(height: 6),
          const Text('Your own place for your people. Make it once — go Live whenever you want to hang out.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kCabinetInk, height: 1.3)),
          const SizedBox(height: 16),
          _InkButton(key: const ValueKey('huud-make'), label: 'Make my Huud', icon: Icons.add_rounded, onTap: _make),
        ]),
      );

  /// Your Huud: Live now, or offline with a big Go Live.
  Widget _yourHuud(MyHuud h) {
    final status = huudStatusLine(
        live: h.live,
        liveCount: h.liveCount,
        memberCount: h.memberCount,
        game: h.gameType == null ? null : huudGameName(h.gameType),
        gameStatus: h.gameStatus);
    return HuudBackdrop(
      background: null,
      child: HuudHeroCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            h.live
                ? const HuudChip('Live', emoji: '🔴', onOrange: true)
                : const HuudChip('Offline', emoji: '🌙', onOrange: true),
            HuudChip(h.privacy.label, emoji: h.privacy.emoji, onOrange: true),
            const HuudChip('Yours', emoji: '👑', onOrange: true),
          ]),
          const SizedBox(height: 10),
          Text(h.name,
              key: ValueKey('your-huud-${h.id}'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kCabinetInk, height: 1.1)),
          const SizedBox(height: 6),
          Text(status, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kCabinetInk)),
          const SizedBox(height: 12),
          HuudAvatarStack(people: h.members, total: h.memberCount, size: 34),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            if (h.live)
              _InkButton(
                  key: ValueKey('huud-go-in-${h.id}'),
                  label: 'Go in',
                  icon: Icons.arrow_forward_rounded,
                  onTap: () => _open(h.id))
            else ...[
              _InkButton(
                  key: ValueKey('huud-go-live-${h.id}'),
                  label: _goingLive == h.id ? 'Going Live…' : 'Go Live',
                  icon: Icons.sensors_rounded,
                  onTap: () => _goLive(h)),
              _LightButton(key: ValueKey('huud-open-${h.id}'), label: 'Open', onTap: () => _open(h.id)),
            ],
          ]),
        ]),
      ),
    );
  }

  /// A Huud you belong to: Live (go in) or offline (you'll hear when it's Live).
  Widget _otherHuud(NeonColors n, MyHuud h) {
    final hc = HuudColors.of(context);
    final status = huudStatusLine(
        live: h.live,
        liveCount: h.liveCount,
        memberCount: h.memberCount,
        game: h.gameType == null ? null : huudGameName(h.gameType),
        gameStatus: h.gameStatus);
    return HuudCard(
      key: ValueKey('member-huud-${h.id}'),
      highlight: h.live,
      onTap: () => _open(h.id),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Avatar(h.host?.name ?? h.name, size: 46, imageUrl: h.host?.avatarUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(h.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: n.ink)),
              ),
              if (h.muted) ...[const SizedBox(width: 6), const Text('🔕', style: TextStyle(fontSize: 14))],
            ]),
            const SizedBox(height: 2),
            Text(status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: h.live ? hc.orangeText : n.mute)),
          ]),
        ),
        const SizedBox(width: 8),
        h.live ? const HuudLiveChip() : Icon(Icons.chevron_right_rounded, color: n.mute, size: 28),
      ]),
    );
  }

  Widget _codeCard(NeonColors n) {
    final h = HuudColors.of(context);
    return HuudCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('🔑', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 8),
          Text('Got a code?', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: n.ink)),
        ]),
        const SizedBox(height: 4),
        Text('Type the 6-letter code a friend sent you', style: TextStyle(fontSize: 14, color: n.mid)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('huud-code-input'),
              controller: _code,
              maxLength: 6,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                TextInputFormatter.withFunction((_, v) => v.copyWith(text: v.text.toUpperCase())),
              ],
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _joinWithCode(),
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontSize: 24, letterSpacing: 6, fontWeight: FontWeight.w900, color: n.ink),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'ABC234',
                hintStyle: TextStyle(color: n.mute.withValues(alpha: 0.28), letterSpacing: 6),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: h.orange, width: 2.4)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          HuudButton(
            key: const ValueKey('huud-code-join'),
            label: 'Join',
            icon: Icons.login_rounded,
            busy: _joining,
            onPressed: _code.text.length == 6 ? _joinWithCode : null,
          ),
        ]),
      ]),
    );
  }
}

/// Dark ink button for sitting on the orange hero card.
class _InkButton extends StatelessWidget {
  const _InkButton({super.key, required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Bouncy(
          onTap: onTap,
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(color: kCabinetInk, borderRadius: BorderRadius.circular(28)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
            ]),
          ),
        ),
      );
}

/// The quieter partner to [_InkButton] on the orange card.
class _LightButton extends StatelessWidget {
  const _LightButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Bouncy(
          onTap: onTap,
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: kCabinetInk.withValues(alpha: 0.4), width: 1.4),
            ),
            child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kCabinetInk)),
          ),
        ),
      );
}
