import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/compact_list_row.dart';
import '../../widgets/neon.dart';
import '../calls/call_screen.dart';
import '../chat/conversation_screen.dart';
import '../friends/friends_screen.dart';

class GroupSummary {
  const GroupSummary({required this.id, required this.name, this.avatarEmoji});
  final String id;
  final String name;
  final String? avatarEmoji;

  factory GroupSummary.fromJson(Map<String, dynamic> j) =>
      GroupSummary(id: j['id'] as String, name: j['name'] as String, avatarEmoji: j['avatarEmoji'] as String?);
}

/// Groups — create one from your friends, then jump into a group chat or a
/// group voice call from the same row. A LiveKit room is multi-party by
/// design (see `CallScreen`), so a group call is just `POST
/// /calls/groups/{id}/token` instead of the DM endpoint — same screen,
/// same flow, just more participants.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  List<GroupSummary>? _groups;
  String? _error;
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final app = AppScope.of(context);
    try {
      final res = await app.api.get('/groups') as List;
      if (!mounted) return;
      setState(() => _groups = res.map((e) => GroupSummary.fromJson((e as Map).cast<String, dynamic>())).toList());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createGroup() async {
    final app = AppScope.of(context);
    List<FriendUser> friends;
    try {
      final res = await app.api.get('/friends') as List;
      friends = res.map((e) => FriendUser.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load your friends')));
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<_NewGroupResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.neon.panel.withValues(alpha: 0.92),
      builder: (_) => _NewGroupSheet(friends: friends),
    );
    if (picked == null || !mounted) return;

    setState(() => _creating = true);
    try {
      final created = await app.api.post('/groups', {'name': picked.name, 'avatarEmoji': picked.avatarEmoji}) as Map<String, dynamic>;
      final groupId = created['id'] as String;
      for (final f in picked.memberIds) {
        await app.api.post('/groups/$groupId/members', {'userId': f});
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create the group')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openChat(GroupSummary g) async {
    final app = AppScope.of(context);
    try {
      final res = await app.api.post('/conversations/groups/${g.id}') as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConversationScreen(conversationId: res['conversationId'] as String, title: g.name),
      ));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _startCall(GroupSummary g) async {
    final app = AppScope.of(context);
    try {
      final res = await app.api.post('/calls/groups/${g.id}/token') as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CallScreen(
          roomName: res['roomName'] as String,
          token: res['token'] as String,
          livekitUrl: res['livekitUrl'] as String,
          title: g.name,
        ),
      ));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start the call')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      floatingActionButton: FloatingActionButton(
        onPressed: _creating ? null : _createGroup,
        child: _creating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_rounded),
      ),
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
                    : (_groups ?? const []).isEmpty
                        ? ListView(children: [
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text('No groups yet — tap + to start one with your friends.',
                                  textAlign: TextAlign.center, style: TextStyle(color: n.mute)),
                            ),
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                            itemCount: _groups!.length,
                            itemBuilder: (context, i) => _GroupTile(
                              group: _groups![i],
                              onChat: () => _openChat(_groups![i]),
                              onCall: () => _startCall(_groups![i]),
                            ),
                          ),
              ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.onChat, required this.onCall});
  final GroupSummary group;
  final VoidCallback onChat;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return CompactListRow(
      onTap: onChat,
      leading: Avatar(group.name, size: 32, emoji: group.avatarEmoji),
      title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
      trailing: IconButton(icon: Icon(Icons.call_rounded, color: n.jade),
          tooltip: 'Group call', onPressed: onCall),
    );
  }
}

class _NewGroupResult {
  const _NewGroupResult(this.name, this.avatarEmoji, this.memberIds);
  final String name;
  final String? avatarEmoji;
  final List<String> memberIds;
}

/// The "new group" sheet — name it, tick off friends to add. Kept to one
/// step rather than a multi-page wizard since a group here is lightweight
/// (no avatar/description yet, just a name + members).
class _NewGroupSheet extends StatefulWidget {
  const _NewGroupSheet({required this.friends});
  final List<FriendUser> friends;

  @override
  State<_NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends State<_NewGroupSheet> {
  final _name = TextEditingController();
  final _picked = <String>{};
  String? _avatarEmoji = kAvatarPresets.first;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(width: 40, height: 4, decoration: BoxDecoration(color: n.line, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 18),
        Text('NEW GROUP', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, letterSpacing: 2)),
        const SizedBox(height: 12),
        Row(children: [
          Avatar('', size: 52, emoji: _avatarEmoji),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _name,
              autofocus: true,
              maxLength: 60,
              decoration: const InputDecoration(hintText: 'Group name', counterText: ''),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text('AVATAR', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kAvatarPresets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final e = kAvatarPresets[i];
              final selected = _avatarEmoji == e;
              return _EmojiTile(emoji: e, selected: selected, onTap: () => setState(() => _avatarEmoji = e));
            },
          ),
        ),
        const SizedBox(height: 16),
        if (widget.friends.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Add some friends first to invite them to a group.', style: TextStyle(color: n.mute)),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.friends.length,
              itemBuilder: (context, i) {
                final f = widget.friends[i];
                final selected = _picked.contains(f.userId);
                return CheckboxListTile(
                  value: selected,
                  onChanged: (_) => setState(() => selected ? _picked.remove(f.userId) : _picked.add(f.userId)),
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(f.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('@${f.username}', maxLines: 1,
                      overflow: TextOverflow.ellipsis, style: TextStyle(color: n.mute)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        NeonButton(
          'Create group',
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_NewGroupResult(_name.text.trim(), _avatarEmoji, _picked.toList())),
        ),
      ]),
    );
  }
}

/// One emoji option in the avatar strip — a filled ring when selected, same
/// "picked" language as `SettingsScreen`'s profile-icon grid.
class _EmojiTile extends StatelessWidget {
  const _EmojiTile({required this.emoji, required this.selected, required this.onTap});
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Bouncy(
      pressScale: 0.9,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? n.jade.withValues(alpha: 0.18) : n.panel,
          border: Border.all(color: selected ? n.jade : n.line, width: selected ? 2 : 1),
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}
