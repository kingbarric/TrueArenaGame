import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/push_notifications.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.createdAt,
    required this.readAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory NotificationItem.fromJson(Map<String, dynamic> json) => NotificationItem(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'GENERIC',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        createdAt: DateTime.parse(json['createdAt'] as String),
        readAt: json['readAt'] != null ? DateTime.parse(json['readAt'] as String) : null,
      );
}

/// The in-app notification history — reached from Settings and the Profile
/// bell. Separate from `PushNotifications`, which only ever handles the one
/// that just arrived; this is "what have I missed", fed by the same events
/// via the backend's `user_notifications` table.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Future<List<NotificationItem>>? _future;

  /// Swiped away — hidden straight away, deleted on the server behind it.
  final _removed = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final pending = _fetch();
    setState(() {
      _future = pending;
    });
  }

  Future<List<NotificationItem>> _fetch() async {
    final app = AppScope.of(context);
    final raw = await app.api.get('/notifications') as List;
    return raw.map((e) => NotificationItem.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<void> _openItem(NotificationItem item) async {
    if (item.isUnread) {
      final app = AppScope.of(context);
      unawaited(app.api.post('/notifications/${item.id}/read'));
      setState(() {
        _future = _future?.then((items) => items
            .map((i) => i.id == item.id
                ? NotificationItem(
                    id: i.id,
                    type: i.type,
                    title: i.title,
                    body: i.body,
                    data: i.data,
                    createdAt: i.createdAt,
                    readAt: DateTime.now())
                : i)
            .toList());
      });
    }
    await PushNotifications.open(item.data);
  }

  Future<void> _delete(NotificationItem item) async {
    setState(() => _removed.add(item.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppScope.of(context).api.delete('/notifications/${item.id}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _removed.remove(item.id));
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't delete that — try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(
        child: FutureBuilder<List<NotificationItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError || !snap.hasData) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('Could not load your notifications', style: TextStyle(color: n.mid)),
                    const SizedBox(height: 12),
                    NeonButton('Retry', style: NeonStyle.ghost, expand: false, onPressed: _load),
                  ]),
                ),
              );
            }
            final items = snap.data!.where((i) => !_removed.contains(i.id)).toList();
            if (items.isEmpty) {
              return Center(
                child: Text(
                    'Nothing yet — messages, invites and your turn\n'
                    'reminders will show up here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: n.mute)),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                itemCount: items.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Text('Swipe one sideways to delete it',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: n.mute));
                  }
                  final item = items[i - 1];
                  return Dismissible(
                    key: ValueKey('notification-${item.id}'),
                    background: const _DeleteBackground(alignment: Alignment.centerLeft),
                    secondaryBackground: const _DeleteBackground(alignment: Alignment.centerRight),
                    onDismissed: (_) => _delete(item),
                    child: _NotificationTile(item: item, onTap: () => _openItem(item)),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// What shows under a notification as it's swiped away.
class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground({required this.alignment});
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Container(
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(color: const Color(0xFFE5484D), borderRadius: BorderRadius.circular(18)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.delete_rounded, color: Colors.white, size: 24),
          SizedBox(width: 6),
          Text('Delete', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
        ]),
      );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});
  final NotificationItem item;
  final VoidCallback onTap;

  IconData get _icon => switch (item.type) {
        'NEW_MESSAGE' => Icons.chat_bubble_rounded,
        'GAME_INVITE' => Icons.sports_esports_rounded,
        'YOUR_TURN' => Icons.timelapse_rounded,
        'BROADCAST' => Icons.campaign_rounded,
        _ => Icons.notifications_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return NeonCard(
      onTap: onTap,
      accent: item.isUnread ? n.gold : null,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(_icon, color: item.isUnread ? n.gold : n.mute, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: item.isUnread ? FontWeight.w800 : FontWeight.w600)),
            const SizedBox(height: 2),
            Text(item.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: n.mid)),
            const SizedBox(height: 6),
            Text(_relativeTime(item.createdAt), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
          ]),
        ),
        if (item.isUnread) ...[
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: n.gold, shape: BoxShape.circle),
          ),
        ],
      ]),
    );
  }
}

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
