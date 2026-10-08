import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../spectate/watch_live.dart';
import 'joined_room_screen.dart';
import '../huud/social_huud_models.dart';
import '../huud/social_huud_screen.dart';

/// The other half of a lobby: `LobbyScreen`/`WordBluffLobbyScreen` only ever
/// create a new room (`POST /rooms`), so a second device could never actually
/// get into the same game — this is what calls the existing `POST /rooms/join`
/// (the room's `gameType` comes back on the response and decides which game
/// screen `JoinedRoomScreen` hands off to once it starts).
class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final _codeController = TextEditingController();
  late final TextEditingController _nicknameController;
  bool _joining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Username, not the full real name — a huud code is sometimes shared
      // outside your circle of friends, and a username is the handle you'd
      // want strangers at the table to see.
      final username = AppScope.of(context).user?.username;
      if (username != null && mounted) setState(() => _nicknameController.text = username);
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final app = AppScope.of(context);
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Huud codes are 6 characters');
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      try {
        final huud = await app.api.post('/huuds/sessions/code', {'code': code}) as Map;
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) =>
            SocialHuudScreen(initial: SocialHuud.fromJson(huud.cast<String, dynamic>()))));
        return;
      } on ApiException catch (e) {
        if (e.status != 404) rethrow;
      }
      final nickname = _nicknameController.text.trim();
      final res = await app.api.post('/rooms/join', {
        'code': code,
        if (nickname.isNotEmpty) 'nickname': nickname,
      }) as Map<String, dynamic>;
      final room = RoomView.fromJson(res);
      await app.rememberActiveRoom(room.id);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => JoinedRoomScreen(room: room)),
      );
    } on ApiException catch (e) {
      if (isAlreadyPlaying(e)) {
        // Can't sit down — the game is on. Watch it instead of showing an error.
        await _watch(announce: true);
        return;
      }
      setState(() => _error = e.status == 404
          ? 'No huud with that code'
          : e.message.toLowerCase() == 'room is full'
              ? 'This huud is full'
              : e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _watch({bool announce = false}) async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Huud codes are 6 characters');
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final opened = await watchHuudByCode(AppScope.of(context), code, context: context, messenger: messenger);
    if (!mounted) return;
    setState(() => _joining = false);
    if (opened && announce) announceWatching(messenger);
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: const Text('Join a huud')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text('HUUD CODE', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, letterSpacing: 2)),
              const SizedBox(height: 8),
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, letterSpacing: 6),
                decoration: const InputDecoration(counterText: '', hintText: 'ABC123'),
                onSubmitted: (_) => _join(),
              ),
              const SizedBox(height: 18),
              Text('YOUR NAME AT THE TABLE', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, letterSpacing: 2)),
              const SizedBox(height: 8),
              TextField(
                controller: _nicknameController,
                maxLength: 24,
                decoration: const InputDecoration(counterText: '', hintText: 'Nickname'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: n.danger)),
              ],
              const SizedBox(height: 22),
              NeonButton(_joining ? 'Joining…' : 'Join a huud', onPressed: _joining ? null : _join),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _joining ? null : () => _watch(),
                icon: const Icon(Icons.visibility_rounded),
                label: const Text('Watch live'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
