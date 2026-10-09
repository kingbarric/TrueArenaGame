import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../widgets/neon.dart';
import 'social_huud_models.dart';
import 'social_huud_entry.dart';
import 'social_huud_screen.dart';
import 'huud_screen.dart';
import '../lobby/join_room_screen.dart';

class SocialHuudHome extends StatefulWidget {
  const SocialHuudHome({super.key});
  @override
  State<SocialHuudHome> createState() => _SocialHuudHomeState();
}

class _SocialHuudHomeState extends State<SocialHuudHome> {
  List<SocialHuud> _huuds = [];
  SocialHuud? _owned;
  Timer? _timer;
  bool _started = false, _loading = false;
  String? _error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final api = AppScope.of(context).api;
    final saved = api.cached('/huuds/sessions');
    final owned = api.cached('/huuds/sessions/owned');
    if (saved is List) {
      _huuds = saved
          .map((h) => SocialHuud.fromJson((h as Map).cast<String, dynamic>()))
          .toList();
    }
    if (owned is Map) {
      _owned = SocialHuud.fromJson(owned.cast<String, dynamic>());
    }
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final api = AppScope.of(context).api;
      final raw = await api.get('/huuds/sessions') as List;
      final owned = await api.get('/huuds/sessions/owned');
      if (!mounted) return;
      setState(() {
        _huuds = raw
            .map((h) => SocialHuud.fromJson((h as Map).cast<String, dynamic>()))
            .toList();
        _owned = owned is Map
            ? SocialHuud.fromJson(owned.cast<String, dynamic>())
            : null;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Could not load live Huuds. Pull down to retry.');
      }
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Home'), actions: [
        IconButton(
            tooltip: 'Activity',
            icon: const Icon(Icons.track_changes),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const HuudScreen())))
      ]),
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                Text('Find your people. Play together.',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                FilledButton.icon(
                    icon:
                        Icon(_owned == null ? Icons.add : Icons.home_outlined),
                    label: Text(_owned == null
                        ? 'Create Huud'
                        : 'Return to ${_owned!.name}'),
                    onPressed: () async {
                      await openOwnedHuud(context);
                      await _load();
                    }),
                OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const JoinRoomScreen())),
                    child: const Text('Enter Huud Code')),
                const SizedBox(height: 20),
                Text('Live Huuds',
                    style: Theme.of(context).textTheme.titleLarge),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.all(12), child: Text(_error!)),
                if (_huuds.isEmpty && _error == null)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                          'No live Huuds yet. Start one and invite your friends.')),
                for (final h in _huuds)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: NeonCard(
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => SocialHuudScreen(
                                    initial: h, browseHuuds: _huuds)));
                            await _load();
                          },
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(h.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                Text(h.gameType == null
                                    ? 'Just hanging out'
                                    : '${h.playing ? 'Playing' : 'Next up:'} ${h.gameName}'),
                                Text(
                                    '${h.viewerCount} watching · ${h.participantCount} in Huud'),
                                if (h.waiting) const Text('Game requests open'),
                              ]))),
              ])));
}
