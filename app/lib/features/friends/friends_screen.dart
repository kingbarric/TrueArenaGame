import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/cyber_agent_sheet.dart';
import '../../widgets/compact_list_row.dart';
import '../../widgets/neon.dart';
import '../calls/call_screen.dart';
import '../games/game_select_screen.dart';
import '../chat/conversation_screen.dart';
import '../status/victory_status.dart';
import 'invite_contacts_screen.dart';

class FriendUser {
  const FriendUser({
    required this.userId,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    this.publicKey,
    this.agentGameType,
    this.agentDifficulty,
  });
  final String userId;
  final String displayName;
  final String username;
  final String? avatarUrl;

  /// Their X25519 public key, when their device has published one — what
  /// makes a DM call end-to-end encrypted (see `E2eCrypto`, `CallScreen`).
  final String? publicKey;

  /// Set only on the viewer's own Cyber Agents — they're listed here
  /// because an agent is a player you can add to a room, but they can't be
  /// messaged, called or unfriended (see `_agentTile`).
  final String? agentGameType;
  final String? agentDifficulty;

  bool get isAgent => agentGameType != null;

  factory FriendUser.fromJson(Map<String, dynamic> j) => FriendUser(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String? ?? '',
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        publicKey: j['publicKey'] as String?,
        agentGameType: j['agentGameType'] as String?,
        agentDifficulty: j['agentDifficulty'] as String?,
      );
}

class FriendRequest {
  const FriendRequest(
      {required this.id, required this.from, required this.createdAt});
  final String id;
  final FriendUser from;
  final DateTime createdAt;

  factory FriendRequest.fromJson(Map<String, dynamic> j) => FriendRequest(
        id: j['id'] as String,
        from: FriendUser.fromJson((j['from'] as Map).cast<String, dynamic>()),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// Friends, requests, chat/call actions, and live online presence.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  List<FriendUser>? _friends;
  List<FriendRequest> _incoming = [];
  List<FriendRequest> _outgoing = [];
  String? _error;
  bool _loading = true;
  bool _sending = false;
  final _usernameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final app = AppScope.of(context);
    try {
      final results = await Future.wait(
          [app.api.get('/friends'), app.api.get('/friends/requests')]);
      final friendsJson = results[0] as List;
      final requestsJson = (results[1] as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _friends = friendsJson
            .map((e) => FriendUser.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        _incoming = ((requestsJson['incoming'] as List?) ?? const [])
            .map((e) =>
                FriendRequest.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        _outgoing = ((requestsJson['outgoing'] as List?) ?? const [])
            .map((e) =>
                FriendRequest.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendRequest() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return;
    setState(() => _sending = true);
    final app = AppScope.of(context);
    try {
      await app.api.post('/friends/requests', {'username': username});
      _usernameController.clear();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Friend request sent')));
      await _load();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not send the request')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _respond(FriendRequest req, bool accept) async {
    final app = AppScope.of(context);
    try {
      await app.api
          .post('/friends/requests/${req.id}/${accept ? 'accept' : 'decline'}');
      await _load();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _unfriend(FriendUser f) async {
    final app = AppScope.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove ${f.displayName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await app.api.delete('/friends/${f.userId}');
      await _load();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _call(FriendUser f) async {
    final app = AppScope.of(context);
    try {
      final res = await app.api.post('/calls/dm/${f.userId}/token')
          as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CallScreen(
          roomName: res['roomName'] as String,
          token: res['token'] as String,
          livekitUrl: res['livekitUrl'] as String,
          title: f.displayName,
          peerPublicKey: f.publicKey, // 1:1 → end-to-end encrypted media
        ),
      ));
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not start the call')));
    }
  }

  Future<void> _message(FriendUser f) async {
    final app = AppScope.of(context);
    try {
      final res = await app.api.post('/conversations/dm/${f.userId}')
          as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConversationScreen(
            conversationId: res['conversationId'] as String,
            title: f.displayName),
      ));
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the chat')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: const Text('Friends'), actions: [
        IconButton(
            tooltip: 'Victory statuses',
            icon: const Icon(Icons.auto_stories_rounded),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const StatusScreen()))),
        IconButton(
          tooltip: 'Start a game',
          icon: Icon(Icons.sports_esports_rounded, color: n.jade),
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GameSelectScreen())),
        ),
        IconButton(
          tooltip: 'Invite from contacts',
          icon: const Icon(Icons.contact_page_outlined),
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InviteContactsScreen())),
        ),
      ]),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    if (_error != null) ...[
                      NeonCard(
                        accent: n.danger,
                        child: Row(children: [
                          Expanded(
                              child: Text(_error!,
                                  style: TextStyle(color: n.mid))),
                          TextButton(
                              onPressed: _load, child: const Text('Retry')),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text('ADD A FRIEND',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: n.mute, letterSpacing: 2)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _usernameController,
                          decoration:
                              const InputDecoration(hintText: 'Their username'),
                          onSubmitted: (_) => _sendRequest(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // expand: false is required inside a Row — the default
                      // sets width: double.infinity, which is invalid under
                      // the unbounded width a Row hands its non-flex children.
                      NeonButton(_sending ? '…' : 'Add',
                          expand: false,
                          onPressed: _sending ? null : _sendRequest),
                    ]),
                    const SizedBox(height: 8),
                    Bouncy(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const InviteContactsScreen())),
                      child: Row(children: [
                        Icon(Icons.contact_page_outlined,
                            size: 14, color: n.gold),
                        const SizedBox(width: 6),
                        Text('Find friends from your contacts',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: n.gold)),
                      ]),
                    ),
                    if (_incoming.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('REQUESTS',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: n.mute, letterSpacing: 2)),
                      const SizedBox(height: 8),
                      for (final r in _incoming) _requestTile(n, r),
                    ],
                    if (_outgoing.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('SENT',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: n.mute, letterSpacing: 2)),
                      const SizedBox(height: 8),
                      for (final r in _outgoing) _pendingTile(n, r),
                    ],
                    const SizedBox(height: 24),
                    Text('YOUR FRIENDS',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: n.mute, letterSpacing: 2)),
                    const SizedBox(height: 8),
                    if ((_friends ?? const []).isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                            'No friends yet — add one by username above.',
                            style: TextStyle(color: n.mute)),
                      )
                    else
                      for (final f in _friends!) _friendTile(n, f),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _requestTile(NeonColors n, FriendRequest r) {
    return CompactListRow(
      leading: Avatar(r.from.displayName, size: 32),
      title: Text(r.from.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
      subtitle: Text('@${r.from.username}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            icon: Icon(Icons.check_circle, color: n.jade),
            tooltip: 'Accept request',
            onPressed: () => _respond(r, true)),
        IconButton(
            icon: Icon(Icons.cancel, color: n.mute),
            tooltip: 'Decline request',
            onPressed: () => _respond(r, false)),
      ]),
    );
  }

  Widget _pendingTile(NeonColors n, FriendRequest r) {
    return CompactListRow(
      leading: Avatar(r.from.displayName, size: 32),
      title: Text('Waiting on @${r.from.username}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: n.mid)),
      trailing: Text('PENDING',
          style: TextStyle(
              color: n.mute,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6)),
    );
  }

  static const _gameLabels = {
    'draughts': 'Draft',
    'goosi': 'Oware',
    'wordbluff': 'Word Bluff',
    'truearena': 'Traitors',
  };

  Future<void> _renameAgent(FriendUser agent) async {
    final name = await showRenameAgentDialog(context, agent.displayName);
    if (name == null || !mounted) return;
    try {
      await AppScope.of(context)
          .api
          .patch('/agents/${agent.userId}', {'name': name});
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not rename that agent')));
      }
    }
  }

  Widget _agentTile(NeonColors n, FriendUser f) {
    final game = _gameLabels[f.agentGameType] ?? f.agentGameType!;
    return CompactListRow(
      leading: OnlineAvatar(f.displayName,
          size: 32, imageUrl: f.avatarUrl, emoji: '🤖', online: true),
      title: Text(f.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
      subtitle: Text('Cyber Agent · $game',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
      trailing: IconButton(
          icon: Icon(Icons.edit_outlined, color: n.gold, size: 20),
          tooltip: 'Rename',
          onPressed: () => _renameAgent(f)),
    );
  }

  Widget _friendTile(NeonColors n, FriendUser f) {
    if (f.isAgent) return _agentTile(n, f);
    return CompactListRow(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              StatusScreen(userId: f.userId, title: f.displayName))),
      leading: ValueListenableBuilder<Set<String>>(
        valueListenable: AppScope.of(context).onlineFriends,
        builder: (_, online, __) => OnlineAvatar(f.displayName,
            size: 32, imageUrl: f.avatarUrl, online: online.contains(f.userId)),
      ),
      title: Text(f.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
      subtitle: Text('@${f.username} · View status',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            icon: Icon(Icons.chat_bubble_rounded, color: n.gold, size: 20),
            tooltip: 'Message',
            onPressed: () => _message(f)),
        IconButton(
            icon: Icon(Icons.call_rounded, color: n.jade),
            tooltip: 'Call',
            onPressed: () => _call(f)),
        IconButton(
            icon: Icon(Icons.more_horiz, color: n.mute),
            tooltip: 'More options',
            onPressed: () => _unfriend(f)),
      ]),
    );
  }
}
