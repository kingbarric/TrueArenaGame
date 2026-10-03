import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/compact_list_row.dart';
import '../../widgets/neon.dart';
import '../games/game_select_screen.dart';
import '../groups/groups_screen.dart';
import 'conversation_screen.dart';
import '../status/victory_status.dart';

class _ConversationSummary {
  const _ConversationSummary({
    required this.id,
    required this.type,
    this.otherName,
    this.otherUserId,
    this.otherAvatarUrl,
    this.otherUsername,
    this.groupName,
    this.lastMessageText,
    this.lastMessageAt,
    this.lastMessageIsInvite = false,
  });

  final String id;
  final String type; // 'dm' | 'group'
  final String? otherName;
  final String? otherUserId;
  final String? otherAvatarUrl;
  final String? otherUsername;
  final String? groupName;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final bool lastMessageIsInvite;

  String get title => type == 'dm' ? (otherName ?? otherUsername ?? 'Direct message') : (groupName ?? 'Group chat');
  String get preview => lastMessageIsInvite ? '🎮 Game invite'
      : (lastMessageText?.startsWith('e2e1:') == true ? '🔒 Encrypted message'
          : (lastMessageText ?? 'No messages yet'));

  factory _ConversationSummary.fromJson(Map<String, dynamic> j) {
    final other = j['other'] as Map?;
    final last = j['lastMessage'] as Map?;
    return _ConversationSummary(
      id: j['id'] as String,
      type: j['type'] as String,
      otherName: other?['displayName'] as String?,
      otherUserId: other?['userId'] as String?,
      otherAvatarUrl: other?['avatarUrl'] as String?,
      otherUsername: other?['username'] as String?,
      groupName: j['groupName'] as String?,
      lastMessageText: last?['text'] as String?,
      lastMessageAt: DateTime.tryParse(last?['createdAt']?.toString() ?? ''),
      lastMessageIsInvite: last?['kind'] == 'game_invite',
    );
  }
}

/// Every DM and group thread, newest activity first — the "all conversations"
/// counterpart to jumping straight into one DM from `FriendsScreen`.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<_ConversationSummary>? _conversations;
  String? _error;
  bool _loading = true;
  StreamSubscription? _chatSub;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Any live message anywhere reorders/refreshes previews — cheap enough
    // (one list call) and keeps "newest activity first" honest without a
    // per-conversation diff.
    _chatSub = AppScope.of(context).chatMessages.listen((_) => _load(silent: true));
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    final app = AppScope.of(context);
    try {
      final res = await app.api.get('/conversations') as List;
      if (!mounted) return;
      final conversations = res.map((e) => _ConversationSummary.fromJson(
          (e as Map).cast<String, dynamic>())).toList()
        ..sort((a, b) => (b.lastMessageAt ?? DateTime(1970))
            .compareTo(a.lastMessageAt ?? DateTime(1970)));
      setState(() => _conversations = conversations);
    } on ApiException catch (e) {
      if (mounted && !silent) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && !silent) setState(() => _error = 'Could not reach the server');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: const Text('Chats'), actions: [
        IconButton(tooltip: 'Victory statuses', icon: const Icon(Icons.auto_stories_rounded),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const StatusScreen()))),
        IconButton(
          tooltip: 'Groups',
          icon: const Icon(Icons.groups_rounded),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GroupsScreen())),
        ),
        // Chats → Games directly: starting a game is the point of the app,
        // so it shouldn't need a trip back to Home first.
        IconButton(
          tooltip: 'Start a game',
          icon: Icon(Icons.sports_esports_rounded, color: n.jade),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GameSelectScreen())),
        ),
      ]),
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
                              Expanded(child: Text(_error!, style: TextStyle(color: n.mid))),
                              TextButton(onPressed: _load, child: const Text('Retry')),
                            ]),
                          ),
                        ),
                      ])
                    : (_conversations ?? const []).isEmpty
                        ? ListView(children: [
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text('No conversations yet — message a friend to start one.',
                                  textAlign: TextAlign.center, style: TextStyle(color: n.mute)),
                            ),
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            itemCount: _conversations!.length,
                            itemBuilder: (context, i) {
                              final c = _conversations![i];
                              return CompactListRow(
                                onTap: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => ConversationScreen(conversationId: c.id, title: c.title),
                                  )).then((_) => _load());
                                },
                                leading: c.otherUserId == null
                                    ? Avatar(c.title, size: 32)
                                    : ValueListenableBuilder<Set<String>>(
                                        valueListenable: AppScope.of(context).onlineFriends,
                                        builder: (_, online, __) => OnlineAvatar(c.title,
                                            size: 32,
                                            imageUrl: c.otherAvatarUrl,
                                            online: online.contains(c.otherUserId)),
                                      ),
                                title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                                subtitle: Text(c.preview, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
                              );
                            },
                          ),
              ),
      ),
    );
  }
}
