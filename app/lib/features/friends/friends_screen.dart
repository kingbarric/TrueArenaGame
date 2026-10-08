import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/compact_list_row.dart';
import '../../widgets/neon.dart';
import '../calls/call_screen.dart';
import '../games/game_select_screen.dart';
import '../chat/conversation_screen.dart';
import '../competitive/player_profile_screen.dart';
import '../status/victory_status.dart';
import 'invite_contacts_screen.dart';

class FriendUser {
  const FriendUser({
    required this.userId,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    this.publicKey,
  });
  final String userId;
  final String displayName;
  final String username;
  final String? avatarUrl;

  /// Their X25519 public key, when their device has published one — what
  /// makes a DM call end-to-end encrypted (see `E2eCrypto`, `CallScreen`).
  final String? publicKey;

  factory FriendUser.fromJson(Map<String, dynamic> j) => FriendUser(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String? ?? '',
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        publicKey: j['publicKey'] as String?,
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

/// One search-as-you-type row — matches `/friends/search` either by
/// username or real name, flagged with enough status to pick the right
/// trailing action without a second round trip.
class UserSearchResult {
  const UserSearchResult({
    required this.userId,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    required this.isFriend,
    required this.requestPending,
  });
  final String userId;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final bool isFriend;
  final bool requestPending;

  factory UserSearchResult.fromJson(Map<String, dynamic> j) => UserSearchResult(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String? ?? '',
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        isFriend: j['isFriend'] as bool? ?? false,
        requestPending: j['requestPending'] as bool? ?? false,
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
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<UserSearchResult> _suggestions = [];
  bool _searching = false;
  // Guards against an earlier, slower request overwriting a later one's
  // results — only the response matching the most recent keystroke lands.
  int _searchToken = 0;
  final Set<String> _requestingUserIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
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

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _suggestions = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(trimmed));
  }

  Future<void> _search(String query) async {
    final token = ++_searchToken;
    final app = AppScope.of(context);
    try {
      final raw = await app.api
          .get('/friends/search?q=${Uri.encodeQueryComponent(query)}') as List;
      if (!mounted || token != _searchToken) return;
      setState(() {
        _suggestions = raw
            .map((e) => UserSearchResult.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        _searching = false;
      });
    } catch (_) {
      if (mounted && token == _searchToken) setState(() => _searching = false);
    }
  }

  Future<void> _sendRequestTo(UserSearchResult u) async {
    setState(() => _requestingUserIds.add(u.userId));
    final app = AppScope.of(context);
    try {
      await app.api.post('/friends/requests/user/${u.userId}');
      if (mounted) {
        setState(() {
          _suggestions = _suggestions
              .map((s) => s.userId == u.userId
                  ? UserSearchResult(
                      userId: s.userId,
                      displayName: s.displayName,
                      username: s.username,
                      avatarUrl: s.avatarUrl,
                      isFriend: s.isFriend,
                      requestPending: true)
                  : s)
              .toList();
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Friend request sent')));
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not send the request')));
      }
    } finally {
      if (mounted) setState(() => _requestingUserIds.remove(u.userId));
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

  Future<void> _cancel(FriendRequest req) async {
    final app = AppScope.of(context);
    try {
      await app.api.post('/friends/requests/${req.id}/cancel');
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

  Future<void> _nudge(FriendUser f) async {
    final app = AppScope.of(context);
    try {
      await app.api.post('/friends/${f.userId}/nudge');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('👋 Nudged ${f.displayName} — their phone is buzzing')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not send the nudge')));
      }
    }
  }

  Future<void> _call(FriendUser f) async {
    final app = AppScope.of(context);
    try {
      final res = await app.api.post('/calls/dm/${f.userId}/token')
          as Map<String, dynamic>;
      if (!mounted) return;
      await CallScreen.open(context, CallScreen(
          roomName: res['roomName'] as String,
          token: res['token'] as String,
          livekitUrl: res['livekitUrl'] as String,
          title: f.displayName,
          peerPublicKey: f.publicKey, // 1:1 → end-to-end encrypted media
          ringPeerId: f.userId, // makes their phone ring
          refreshToken: () async =>
              ((await app.api.post('/calls/dm/${f.userId}/token')
                  as Map<String, dynamic>)['token'] as String),
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
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by username or name',
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)))
                            : (_searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () {
                                      _searchController.clear();
                                      _onSearchChanged('');
                                    })
                                : null),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                    if (_suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final s in _suggestions) _suggestionTile(n, s),
                    ] else if (!_searching &&
                        _searchController.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('No one matches that search',
                            style: TextStyle(color: n.mute)),
                      ),
                    ],
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
                            'No friends yet — search for one above.',
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

  Widget _suggestionTile(NeonColors n, UserSearchResult s) {
    final requesting = _requestingUserIds.contains(s.userId);
    return CompactListRow(
      leading: Avatar(s.displayName.isEmpty ? s.username : s.displayName,
          size: 32, imageUrl: s.avatarUrl),
      title: Text(s.displayName.isEmpty ? '@${s.username}' : s.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
      subtitle: Text('@${s.username}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
      trailing: s.isFriend
          ? Text('FRIENDS',
              style: TextStyle(
                  color: n.jade, fontSize: 9, fontWeight: FontWeight.w800))
          : s.requestPending
              ? Text('PENDING',
                  style: TextStyle(
                      color: n.mute, fontSize: 9, fontWeight: FontWeight.w800))
              : NeonButton(requesting ? '…' : 'Add',
                  style: NeonStyle.ghost,
                  expand: false,
                  onPressed: requesting ? null : () => _sendRequestTo(s)),
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
      trailing: TextButton(
        onPressed: () => _cancel(r),
        child: Text('CANCEL',
            style: TextStyle(
                color: n.danger, fontSize: 9, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _friendTile(NeonColors n, FriendUser f) {
    return CompactListRow(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PlayerProfileScreen(username: f.username, statusUserId: f.userId))),
      leading: ValueListenableBuilder<Set<String>>(
        valueListenable: AppScope.of(context).onlineFriends,
        builder: (_, online, __) => OnlineAvatar(f.displayName,
            size: 32, imageUrl: f.avatarUrl, online: online.contains(f.userId)),
      ),
      title: Row(children: [
        Flexible(
          child: Text(f.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 6),
        // Right by their name: buzz their phone to come online.
        Tooltip(
          message: 'Nudge ${f.displayName}',
          child: InkWell(
            key: ValueKey('nudge-${f.userId}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => _nudge(f),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: n.gold.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: n.gold.withValues(alpha: 0.6)),
              ),
              child: Text('👋 Nudge',
                  style: TextStyle(
                      color: n.gold, fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ]),
      subtitle: Text('@${f.username} · View profile',
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
