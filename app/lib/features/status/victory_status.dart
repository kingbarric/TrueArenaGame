import '../../core/player_identity.dart';
import '../../widgets/game_artwork.dart';
import '../../core/share_origin.dart';
import '../../core/api_client.dart' show userErrorMessage, userRetryMessage;
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
  'draughts': 'Draughts',
  'chess': 'Chess',
  'goosi': 'Macala',
  'truearena': 'Traitors',
  'monopoly': 'Huudpoly',
  'slayhuud': 'SlayHuud',
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
    aspectRatio: .78,
    child: ClipRRect(borderRadius: BorderRadius.circular(24),
      child: LayoutBuilder(builder: (context, box) {
        final scale = box.maxWidth / 300;
        Widget gap(double height) => SizedBox(height: height * scale);
        Widget words(String text, double size, Color color, {int lines = 2}) =>
          Text(text, textAlign: TextAlign.center, maxLines: lines, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'MonopolySans', decoration: TextDecoration.none, color: color, fontSize: size * scale, height: 1.15,
              fontWeight: FontWeight.w800));
        return Stack(fit: StackFit.expand, children: [
          Image.asset(gameArtworkAsset(gameType), fit: BoxFit.cover, excludeFromSemantics: true),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x66101622), Color(0xbb101622), Color(0xff101622)]))),
          Padding(padding: EdgeInsets.all(20 * scale), child: Column(children: [
            Image.asset('assets/images/branding/playhuud-wordmark-transparent.png',
              height: 30 * scale, fit: BoxFit.contain, semanticLabel: 'PlayHuud'),
            gap(10),
            words(gameStatusNames[gameType] ?? gameType, 20, const Color(0xffffd36b)),
            const Spacer(),
            Icon(Icons.emoji_events_rounded, color: const Color(0xffffd36b), size: 42 * scale),
            gap(6), words('VICTORY', 32, Colors.white),
            gap(6), words(firstName(playerName), 23, Colors.white, lines: 1),
            if (detail != null) ...[gap(8), words(detail!, 13, Colors.white70)],
            const Spacer(),
            words(gameInvitationHook(gameType), 16, Colors.white),
            gap(10),
            words('Think you can beat me? Join the game.', 13, const Color(0xffffd36b)),
            gap(8), words('playhuud.com', 12, Colors.white70, lines: 1),
          ])),
        ]);
      })),
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
                Text(userRetryMessage)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final origin = shareOrigin(context);
    setState(() => _busy = true);
    try {
      await precacheImage(AssetImage(gameArtworkAsset(widget.gameType)), context);
      if (!mounted) return;
      await precacheImage(const AssetImage('assets/images/branding/playhuud-wordmark-transparent.png'), context);
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
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
      await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')],
          sharePositionOrigin: origin,
          text:
              'I won ${gameStatusNames[widget.gameType] ?? widget.gameType} on PlayHuud! ${gameInvitationHook(widget.gameType)} Think you can beat me? Join me: https://playhuud.com');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(userRetryMessage)));
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
      if (mounted) setState(() => _error = userErrorMessage);
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
                  if (_error != null) const Center(child: Text(userErrorMessage)),
                  if (active?.isEmpty == true)
                    const Center(
                        child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('No active victory statuses'))),
                  for (final status in active ?? const <VictoryStatus>[]) ...[
                    ListTile(
                      leading: const Icon(Icons.circle,
                          size: 13, color: Color(0xff4ade80)),
                      title: Text(playerHandle(status.username, displayName: status.displayName)),
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
