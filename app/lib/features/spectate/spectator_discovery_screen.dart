import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/compact_list_row.dart';
import '../../widgets/neon.dart';
import 'spectate_screen.dart';

const _gameNames = {
  'truearena': 'Traitors',
  'wordbluff': 'Word Bluff',
  'draughts': 'Draft',
  'goosi': 'Macala',
  'whot': 'Whot',
  'ludo': 'Ludo'
};

class DiscoverableRoom {
  const DiscoverableRoom(
      {required this.roomId,
      required this.code,
      required this.gameType,
      required this.hostName,
      required this.connectedCount});
  final String roomId;
  final String code;
  final String gameType;
  final String hostName;
  final int connectedCount;

  factory DiscoverableRoom.fromJson(Map<String, dynamic> j) => DiscoverableRoom(
        roomId: j['roomId'] as String,
        code: j['code'] as String,
        gameType: j['gameType'] as String,
        hostName: j['hostName'] as String,
        connectedCount: (j['connectedCount'] as num).toInt(),
      );
}

/// Friends' games in progress right now — tap one to drop in as a spectator
/// (`GET /rooms/discoverable`, backed by the live in-memory runtimes, not
/// the DB — see `RoomService.discoverable`). Watching never requires an
/// invite code: spectating skips the room-membership check entirely.
class SpectatorDiscoveryScreen extends StatefulWidget {
  const SpectatorDiscoveryScreen({super.key});

  @override
  State<SpectatorDiscoveryScreen> createState() =>
      _SpectatorDiscoveryScreenState();
}

class _SpectatorDiscoveryScreenState extends State<SpectatorDiscoveryScreen> {
  List<DiscoverableRoom>? _rooms;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final app = AppScope.of(context);
    try {
      final res = await app.api.get('/rooms/discoverable') as List;
      if (!mounted) return;
      setState(() => _rooms = res
          .map((e) =>
              DiscoverableRoom.fromJson((e as Map).cast<String, dynamic>()))
          .toList());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: const Text('Watch Live')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _error != null
                    ? ListView(children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: NeonCard(
                            accent: n.danger,
                            child: Row(children: [
                              Expanded(
                                  child: Text(_error!,
                                      style: TextStyle(color: n.mid))),
                              TextButton(
                                  onPressed: _load, child: const Text('Retry')),
                            ]),
                          ),
                        ),
                      ])
                    : (_rooms ?? const []).isEmpty
                        ? ListView(children: [
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(children: [
                                Icon(Icons.visibility_outlined,
                                    size: 40, color: n.mute),
                                const SizedBox(height: 12),
                                Text('No friends are playing right now.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: n.mute)),
                              ]),
                            ),
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            itemCount: _rooms!.length,
                            itemBuilder: (context, i) => _RoomTile(
                                room: _rooms![i],
                                delay: Duration(milliseconds: 40 * i)),
                          ),
              ),
      ),
    );
  }
}

class _RoomTile extends StatefulWidget {
  const _RoomTile({required this.room, required this.delay});
  final DiscoverableRoom room;
  final Duration delay;

  @override
  State<_RoomTile> createState() => _RoomTileState();
}

class _RoomTileState extends State<_RoomTile> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final room = widget.room;
    return AnimatedSlide(
      offset: _shown ? Offset.zero : const Offset(0, 0.12),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: CompactListRow(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SpectateScreen(
                roomId: room.roomId,
                gameType: room.gameType,
                title:
                    '${room.hostName}\'s ${_gameNames[room.gameType] ?? room.gameType}'),
          )),
          leading: Stack(alignment: Alignment.bottomRight, children: [
            Avatar(room.hostName, size: 32),
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: n.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: n.panel, width: 2))),
          ]),
          title: Text(
              '${room.hostName}\'s ${_gameNames[room.gameType] ?? room.gameType}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text('${room.connectedCount} playing',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: n.mute)),
          trailing: IconButton(
              tooltip: 'Watch game',
              icon: Icon(Icons.visibility_rounded, color: n.gold),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SpectateScreen(
                        roomId: room.roomId,
                        gameType: room.gameType,
                        title:
                            '${room.hostName}\'s ${_gameNames[room.gameType] ?? room.gameType}'),
                  ))),
        ),
      ),
    );
  }
}
