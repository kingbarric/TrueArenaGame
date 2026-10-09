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
import 'huud_kit.dart';
import 'huud_space_models.dart';
import 'huud_space_screen.dart';

/// The Huud tab: make a Huud, hop into one with a code, and every Huud you
/// made or joined — with the people who were there.
class HuudHomeScreen extends StatefulWidget {
  const HuudHomeScreen({super.key});

  @override
  State<HuudHomeScreen> createState() => _HuudHomeScreenState();
}

enum _HistoryFilter { all, mine, joined }

class _HuudHomeScreenState extends State<HuudHomeScreen> {
  List<HuudHistoryEntry>? _history;
  String? _error;
  bool _loading = false;
  _HistoryFilter _filter = _HistoryFilter.all;
  final _code = TextEditingController();
  bool _joining = false;
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
    if (app.api.bearer == null) return;
    if (_loading) return;
    _loading = true;
    try {
      final raw = await app.api.get('/huud-spaces/history') as List;
      if (!mounted) return;
      setState(() {
        _history = raw.map((e) => HuudHistoryEntry.fromJson((e as Map).cast<String, dynamic>())).toList();
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
    final history = _history ?? const <HuudHistoryEntry>[];
    final liveNow = history.where((e) => e.live).toList();
    final hosting = liveNow.any((e) => e.youAreHost);
    final past = history
        .where((e) => !e.live)
        .where((e) => switch (_filter) {
              _HistoryFilter.all => true,
              _HistoryFilter.mine => e.youCreated,
              _HistoryFilter.joined => !e.youCreated,
            })
        .toList();

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
                  for (final e in liveNow) ...[_liveCard(e), const SizedBox(height: 14)],
                  if (!hosting) ...[
                    liveNow.isEmpty ? _makeHero() : _makeSmall(n),
                    const SizedBox(height: 14),
                  ],
                  _codeCard(n),
                  const SizedBox(height: 28),
                  HuudSectionTitle('Your Huuds',
                      emoji: '📚',
                      trailing: _history == null
                          ? null
                          : HuudChip('${history.where((e) => !e.live).length}',
                              color: HuudColors.of(context).orangeText)),
                  _filters(n),
                  const SizedBox(height: 14),
                  if (_error != null && _history == null)
                    HuudFriendlyState(
                      emoji: '📡',
                      title: 'Hmm, no connection',
                      message: _error!,
                      action: HuudButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: _load),
                    )
                  else if (_history == null)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                  else if (past.isEmpty)
                    HuudFriendlyState(
                      emoji: '🌱',
                      title: _filter == _HistoryFilter.all ? 'Nothing here yet' : 'None of these yet',
                      message: 'Huuds you make or join will show up here, with everyone you played with.',
                    ),
                ]),
              ),
              if (past.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      mainAxisExtent: 230,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _HistoryCard(entry: past[i], onTap: () => _showPast(past[i], hosting)),
                      childCount: past.length,
                    ),
                  ),
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
        Text('Hang out, talk and play games together',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: n.mid)),
      ]);

  Widget _makeHero() => HuudHeroCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Image.asset(huudIcon, width: 60, height: 60),
          const SizedBox(height: 6),
          const Text('Make a Huud',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kCabinetInk, height: 1.1)),
          const SizedBox(height: 6),
          const Text('Your own place to hang out with friends and play game after game.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kCabinetInk, height: 1.3)),
          const SizedBox(height: 16),
          _InkButton(
            key: const ValueKey('huud-make'),
            label: 'Make a Huud',
            icon: Icons.add_rounded,
            onTap: _make,
          ),
        ]),
      );

  Widget _makeSmall(NeonColors n) {
    final h = HuudColors.of(context);
    return HuudCard(
      onTap: _make,
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
              color: h.orange, shape: BoxShape.circle, border: Border.all(color: kCabinetInk, width: 2.2)),
          child: Icon(Icons.add_rounded, color: h.onOrange, size: 30),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Make your own Huud', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: n.ink)),
            Text('You choose the games', style: TextStyle(fontSize: 14, color: n.mid)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: h.orangeText, size: 30),
      ]),
    );
  }

  Widget _liveCard(HuudHistoryEntry e) {
    final here = e.participants;
    return HuudHeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          const HuudChip("You're in", emoji: '🟢', onOrange: true),
          if (e.youAreHost) const HuudChip('Host', emoji: '👑', onOrange: true),
          HuudChip(e.privacy.label, emoji: e.privacy.emoji, onOrange: true),
        ]),
        const SizedBox(height: 10),
        Text(e.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kCabinetInk, height: 1.1)),
        const SizedBox(height: 12),
        Row(children: [
          HuudAvatarStack(people: here, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(here.length == 1 ? 'Just you so far' : '${here.length} people',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kCabinetInk)),
          ),
        ]),
        const SizedBox(height: 16),
        _InkButton(
          key: ValueKey('huud-go-in-${e.id}'),
          label: 'Go in',
          icon: Icons.arrow_forward_rounded,
          onTap: () => _open(e.id),
        ),
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

  Widget _filters(NeonColors n) {
    final h = HuudColors.of(context);
    Widget chip(_HistoryFilter f, String label) {
      final on = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Semantics(
          selected: on,
          button: true,
          child: GestureDetector(
            key: ValueKey('huud-filter-${f.name}'),
            onTap: () => setState(() => _filter = f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? h.orange : n.panel,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: on ? kCabinetInk : n.line, width: on ? 2.2 : 1.4),
              ),
              child: Text(label,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: on ? h.onOrange : n.mid)),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip(_HistoryFilter.all, 'All'),
        chip(_HistoryFilter.mine, 'Made by me'),
        chip(_HistoryFilter.joined, 'Joined'),
      ]),
    );
  }

  Future<void> _showPast(HuudHistoryEntry e, bool hosting) => showHuudSheet<void>(
        context,
        builder: (sheet) {
          final n = sheet.neon;
          final h = HuudColors.of(sheet);
          final me = AppScope.of(context).user?.id;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.8),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(e.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: n.ink)),
                  const SizedBox(height: 6),
                  Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                    HuudChip(e.youCreated ? 'Made by you' : 'Joined',
                        emoji: e.youCreated ? '⭐' : '🙌', color: h.orangeText),
                    HuudChip(huudWhen(e.createdAt), emoji: '📅'),
                    HuudChip(e.privacy.label, emoji: e.privacy.emoji),
                  ]),
                  const SizedBox(height: 18),
                  Text('Games played', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: n.ink)),
                  const SizedBox(height: 8),
                  if (e.games.isEmpty)
                    Text('No games this time — just hanging out 😄', style: TextStyle(fontSize: 15, color: n.mid))
                  else
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      for (final g in e.games)
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          HuudGameArt(g, size: 52),
                          const SizedBox(height: 4),
                          Text(huudGameName(g),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: n.mid)),
                        ]),
                    ]),
                  const SizedBox(height: 18),
                  Text('Who was there (${e.participants.length})',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: n.ink)),
                  const SizedBox(height: 8),
                  for (final p in e.participants)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Avatar(p.name, size: 42, imageUrl: p.avatarUrl),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(p.userId == me ? '${p.name} (you)' : p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: n.ink)),
                        ),
                        if (p.host) const HuudChip('Host', emoji: '👑'),
                      ]),
                    ),
                  if (!hosting) ...[
                    const SizedBox(height: 18),
                    HuudButton(
                      label: 'Make a new Huud',
                      icon: Icons.add_rounded,
                      expand: true,
                      big: true,
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        _make();
                      },
                    ),
                  ],
                ]),
              ),
            ),
          );
        },
      );
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

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry, required this.onTap});
  final HuudHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final e = entry;
    return Semantics(
      button: true,
      label: '${e.name}, ${huudWhen(e.createdAt)}, ${e.participants.length} people',
      excludeSemantics: true,
      child: HuudCard(
        key: ValueKey('huud-history-${e.id}'),
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (e.games.isEmpty)
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: h.orangeSoft, borderRadius: BorderRadius.circular(12)),
                child: const Text('💬', style: TextStyle(fontSize: 20)),
              )
            else
              for (final g in e.games.take(3))
                Padding(padding: const EdgeInsets.only(right: 4), child: HuudGameArt(g, size: 40)),
            const Spacer(),
            if (e.youCreated) const Text('⭐', style: TextStyle(fontSize: 18)),
          ]),
          const SizedBox(height: 10),
          Text(e.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, height: 1.15, fontWeight: FontWeight.w900, color: n.ink)),
          const SizedBox(height: 4),
          Text(huudWhen(e.createdAt), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: n.mute)),
          const Spacer(),
          HuudAvatarStack(people: e.participants, size: 30, max: 4),
          const SizedBox(height: 8),
          Text(
            e.gamesPlayed == 0 ? 'Hung out' : (e.gamesPlayed == 1 ? '1 game played' : '${e.gamesPlayed} games played'),
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: h.orangeText),
          ),
        ]),
      ),
    );
  }
}
