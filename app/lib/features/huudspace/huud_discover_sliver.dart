import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import 'huud_kit.dart';
import 'huud_space_models.dart';
import 'huud_space_screen.dart';
import 'huud_swipe_screen.dart';
import 'live_now_panel.dart';

/// Suggestions use the server's existing visibility and join permissions.
/// Membership Huuds stay in the neighbouring tab rather than being suggested.
class HuudDiscoverSliver extends StatefulWidget {
  const HuudDiscoverSliver(
      {super.key, required this.excludeIds, required this.onJoined});

  final Set<String> excludeIds;
  final Future<void> Function() onJoined;

  @override
  HuudDiscoverSliverState createState() => HuudDiscoverSliverState();
}

class HuudDiscoverSliverState extends State<HuudDiscoverSliver> {
  List<LiveHuud>? _huuds;
  String? _error, _joining;
  bool _loading = false, _started = false;
  StreamSubscription? _events;
  Timer? _poll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _events = AppScope.of(context).huudSpaceEvents.listen((_) => refresh());
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  void dispose() {
    _events?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    final api = AppScope.of(context).api;
    if (_loading || api.bearer == null) return;
    _loading = true;
    try {
      final raw = await api.get('/huud-spaces/live') as List;
      if (!mounted) return;
      setState(() {
        _huuds = raw
            .map((h) => LiveHuud.fromJson((h as Map).cast<String, dynamic>()))
            .toList();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = userErrorMessage);
    } finally {
      _loading = false;
    }
  }

  Future<void> _join(LiveHuud huud) async {
    if (_joining != null) return;
    setState(() => _joining = huud.id);
    try {
      if (huud.findingPlayers) {
        await requestPublicHuudSeat(context, huud.id);
      } else {
        final raw = await AppScope.of(context)
            .api
            .post('/huud-spaces/${huud.id}/join') as Map;
        if (!mounted) return;
        final joined = HuudSpace.fromJson(raw.cast<String, dynamic>());
        if (joined.youAreIn) {
          setState(() => _huuds?.removeWhere((h) => h.id == huud.id));
          await widget.onJoined();
        } else {
          huudSnack(
              context, "Asked the host — you'll get in when they say yes ⏳");
        }
        if (!mounted) return;
        await openHuudSpace(context, joined.id, initial: joined);
      }
    } on ApiException catch (e) {
      if (mounted) huudSnack(context, e.message);
    } catch (_) {
      if (mounted) huudSnack(context, userErrorMessage);
    } finally {
      if (mounted) {
        setState(() => _joining = null);
        await widget.onJoined();
        if (mounted) refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final suggestions = (_huuds ?? const <LiveHuud>[])
        .where((h) => !h.youAreIn && !widget.excludeIds.contains(h.id))
        .toList();
    return SliverMainAxisGroup(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        sliver: SliverToBoxAdapter(
            child: Text('Live Huuds to meet new people. Tap a card to look in.',
                style: TextStyle(fontSize: 13, height: 1.4, color: n.mid))),
      ),
      if (_error != null)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
              child: HuudFriendlyState(
            emoji: '📡',
            title: "Couldn't load suggestions",
            message: _error!,
            action: HuudButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                onPressed: refresh),
          )),
        )
      else if (_huuds == null)
        const SliverToBoxAdapter(
            child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator())))
      else if (suggestions.isEmpty)
        SliverToBoxAdapter(
            child: HuudFriendlyState(
          emoji: '🏠',
          title: 'More Huuds soon',
          message:
              "No new Huuds are live right now. Check back soon, or join a friend's with their code.",
          action: HuudButton(
              label: 'Refresh',
              icon: Icons.refresh_rounded,
              onPressed: refresh),
        )),
      if (_huuds != null)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: suggestions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 106),
              child: LiveHuudCard(
                huud: suggestions[i],
                busy: _joining == suggestions[i].id,
                onEnter: () => _join(suggestions[i]),
                onPeek: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          HuudSwipeScreen(huuds: suggestions, start: i)));
                  if (!mounted) return;
                  await widget.onJoined();
                  if (mounted) refresh();
                },
              ),
            ),
          ),
        ),
    ]);
  }
}
