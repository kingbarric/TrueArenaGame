import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../widgets/neon.dart';
import 'call_screen.dart';

class HangoutsScreen extends StatefulWidget {
  const HangoutsScreen({super.key});
  @override
  State<HangoutsScreen> createState() => _HangoutsScreenState();
}

class _HangoutsScreenState extends State<HangoutsScreen> {
  List<Map<String, dynamic>>? _sessions;
  String? _error;
  final Set<String> _requested = {};
  StreamSubscription? _events;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _events = AppScope.of(context).callEvents.listen((event) {
        if (event['type'] == 'VOICE_JOIN_ANSWERED') {
          final data = (event['data'] as Map).cast<String, dynamic>();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(data['approved'] == true
                  ? 'Your join request was approved. Tap Join.'
                  : 'Your join request was declined.')));
          _load();
        }
      });
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final raw = await AppScope.of(context)
          .api
          .get('/calls/sessions/discoverable') as List;
      if (mounted)
        setState(() {
          _sessions =
              raw.map((r) => (r as Map).cast<String, dynamic>()).toList();
          _error = null;
        });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load hangouts');
    }
  }

  Future<void> _join(Map<String, dynamic> session) async {
    final api = AppScope.of(context).api;
    final name = session['roomName'] as String;
    final path = '/calls/rooms/$name/token';
    try {
      final token = await api.post(path) as Map<String, dynamic>;
      if (!mounted) return;
      await CallScreen.open(
          context,
          CallScreen(
            roomName: name,
            token: token['token'] as String,
            livekitUrl: token['livekitUrl'] as String,
            title: 'Huud hangout',
            refreshToken: () async => ((await api.post(path)
                as Map<String, dynamic>)['token'] as String),
          ));
    } on ApiException catch (error) {
      if (error.status == 403) {
        try {
          await api
              .post('/calls/sessions/${session['voiceSessionId']}/request');
          if (mounted) {
            setState(() => _requested.add(name));
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Join request sent to the host')));
          }
        } catch (_) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not request to join')));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Hangouts')),
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(children: [
              if (_error != null) ListTile(title: Text(_error!), onTap: _load),
              if (_sessions == null && _error == null)
                const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator())),
              if (_sessions?.isEmpty == true)
                const ListTile(
                    title: Text('No open hangouts yet'),
                    subtitle:
                        Text('Call a friend or group to start hanging out.')),
              for (final session in _sessions ?? <Map<String, dynamic>>[]) ...[
                ListTile(
                  leading: const Icon(Icons.headset_rounded),
                  title: const Text('Voice hangout'),
                  subtitle: Text(
                      '${session['privacy']} · ${(session['participants'] as List).length} people'),
                  trailing: TextButton(
                      onPressed: () => _join(session),
                      child: Text(_requested.contains(session['roomName'])
                          ? 'Check request'
                          : 'Join')),
                ),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(spacing: 12, children: [
                      for (final raw in session['participants'] as List)
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Avatar((raw as Map)['displayName'] as String? ?? '?',
                              size: 38, imageUrl: raw['avatarUrl'] as String?),
                          Text(raw['displayName'] as String? ?? '',
                              style: const TextStyle(fontSize: 11)),
                        ]),
                    ])),
                const Divider(),
              ],
            ])),
      );
}
