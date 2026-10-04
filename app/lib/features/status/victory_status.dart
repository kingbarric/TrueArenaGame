import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_state.dart';

const gameStatusNames = {
  'whot': 'Whot',
  'ludo': 'Ludo',
  'wordbluff': 'Word Bluff',
  'draughts': 'Draft',
  'goosi': 'Macala',
  'truearena': 'Traitors',
};

class VictoryStatus {
  const VictoryStatus(
      {required this.id,
      required this.userId,
      required this.displayName,
      required this.username,
      required this.gameType,
      required this.createdAt,
      required this.expiresAt});
  final String id, userId, displayName, username, gameType;
  final DateTime createdAt, expiresAt;

  factory VictoryStatus.fromJson(Map<String, dynamic> json) => VictoryStatus(
        id: json['id'].toString(),
        userId: json['userId'].toString(),
        displayName: json['displayName']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        gameType: json['gameType']?.toString() ?? '',
        createdAt: DateTime.parse(json['createdAt'].toString()),
        expiresAt: DateTime.parse(json['expiresAt'].toString()),
      );
}

class VictoryCard extends StatelessWidget {
  const VictoryCard(
      {super.key,
      required this.playerName,
      required this.gameType,
      this.detail});
  final String playerName, gameType;
  final String? detail;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 0.78,
        child: Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xff181433),
                  Color(0xff39205f),
                  Color(0xff0b4352)
                ]),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.emoji_events_rounded,
                color: Color(0xffffd36b), size: 82),
            const SizedBox(height: 22),
            const Text('VICTORY',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3)),
            const SizedBox(height: 12),
            Text(playerName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(gameStatusNames[gameType] ?? gameType,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xffffd36b), fontSize: 20)),
            if (detail != null) ...[
              const SizedBox(height: 18),
              Text(detail!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15)),
            ],
            const SizedBox(height: 32),
            const Text('PLAYHUUD',
                style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4)),
          ]),
        ),
      );
}

/// Shown only on a player's own win. Sharing exports the same card shown here.
class VictoryShareButton extends StatelessWidget {
  const VictoryShareButton(
      {super.key, required this.roomId, required this.gameType, this.detail});
  final String roomId, gameType;
  final String? detail;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _PublishVictory(
                roomId: roomId, gameType: gameType, detail: detail)),
        icon: const Icon(Icons.ios_share_rounded),
        label: const Text('Share victory'),
      );
}

class _PublishVictory extends StatefulWidget {
  const _PublishVictory(
      {required this.roomId, required this.gameType, this.detail});
  final String roomId, gameType;
  final String? detail;

  @override
  State<_PublishVictory> createState() => _PublishVictoryState();
}

class _PublishVictoryState extends State<_PublishVictory> {
  final _cardKey = GlobalKey();
  bool _busy = false;
  bool _posted = false;

  Future<void> _post() async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context)
          .api
          .post('/statuses', {'roomId': widget.roomId});
      if (mounted) setState(() => _posted = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Victory added to your 24-hour status')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Could not post this victory yet. Try again shortly.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Card is not ready');
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Card could not be captured');
      final file = File(
          '${(await getTemporaryDirectory()).path}/playhuud-victory-${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)],
          text:
              'I won ${gameStatusNames[widget.gameType] ?? widget.gameType} on PlayHuud!');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the share sheet.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = AppScope.of(context).user?.displayName ?? 'Player';
    return AlertDialog(
      title: const Text('Your victory'),
      content: SizedBox(
          width: 300,
          child: RepaintBoundary(
              key: _cardKey,
              child: VictoryCard(
                  playerName: name,
                  gameType: widget.gameType,
                  detail: widget.detail))),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Close')),
        TextButton.icon(
            onPressed: _busy || _posted ? null : _post,
            icon: const Icon(Icons.add_circle_outline),
            label: Text(_posted ? 'Posted' : 'Add to status')),
        FilledButton.icon(
            onPressed: _busy ? null : _share,
            icon: const Icon(Icons.ios_share),
            label: const Text('Share')),
      ],
    );
  }
}

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key, this.userId, this.title});
  final String? userId, title;

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  List<VictoryStatus>? _statuses;
  String? _error;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _expiryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await AppScope.of(context).api.get('/statuses') as List;
      if (!mounted) return;
      setState(() {
        _statuses = result
            .map((e) =>
                VictoryStatus.fromJson((e as Map).cast<String, dynamic>()))
            .where((s) => widget.userId == null || s.userId == widget.userId)
            .toList();
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load statuses');
    }
  }

  @override
  Widget build(BuildContext context) {
    final active =
        _statuses?.where((s) => s.expiresAt.isAfter(DateTime.now())).toList();
    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.title == null ? 'Status' : '${widget.title} · Status')),
      body: _statuses == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 100),
                children: [
                  if (_error != null) Center(child: Text(_error!)),
                  if (active?.isEmpty == true)
                    const Center(
                        child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('No active victory statuses'))),
                  for (final status in active ?? const <VictoryStatus>[]) ...[
                    ListTile(
                      leading: const Icon(Icons.circle,
                          size: 13, color: Color(0xff4ade80)),
                      title: Text(status.displayName),
                      subtitle: Text(
                          '@${status.username} · expires in ${status.expiresAt.difference(DateTime.now()).inHours + 1}h'),
                    ),
                    VictoryCard(
                        playerName: status.displayName,
                        gameType: status.gameType),
                    const SizedBox(height: 24),
                  ],
                ],
              )),
    );
  }
}
