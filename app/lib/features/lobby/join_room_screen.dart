import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';
import '../spectate/spectate_screen.dart';
import 'joined_room_screen.dart';

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
      final displayName = AppScope.of(context).user?.displayName;
      if (displayName != null && mounted) setState(() => _nicknameController.text = displayName);
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

  Future<void> _watch() async {
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
      final raw = await AppScope.of(context).api.post('/rooms/watch', {'code': code})
          as Map<String, dynamic>;
      final room = RoomView.fromJson(raw);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SpectateScreen(
                roomId: room.id,
                gameType: room.gameType,
                title: 'Watching ${room.gameType == 'draughts' ? 'Draft' : room.gameType}',
              )));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
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
                onPressed: _joining ? null : _watch,
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
