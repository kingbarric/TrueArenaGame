import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_state.dart';
import '../features/friends/friends_screen.dart';
import '../theme/neon_theme.dart';
import 'neon.dart';

/// "Add a player" — pick friends and invite them straight into this room.
///
/// Each invite opens (or reuses) the DM with that friend and drops a
/// `game_invite` message into it, which their chat renders as a real
/// "Join game" button, and which also pings their inbox. That's why this
/// reuses the chat plumbing rather than inventing a second invite channel:
/// an invite that lives in the conversation is one they can still find
/// tomorrow, unlike a notification they swiped away.
///
/// Returns the number of invites actually sent.
Future<int?> showInvitePlayersSheet(BuildContext context, {required String roomId}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: kScrim,
    builder: (_) => _InvitePlayersSheet(roomId: roomId),
  );
}

class _InvitePlayersSheet extends StatefulWidget {
  const _InvitePlayersSheet({required this.roomId});
  final String roomId;

  @override
  State<_InvitePlayersSheet> createState() => _InvitePlayersSheetState();
}

class _InvitePlayersSheetState extends State<_InvitePlayersSheet> {
  List<FriendUser>? _friends;
  String? _error;
  bool _sending = false;
  final _picked = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = AppScope.of(context);
    try {
      final res = await app.api.get('/friends') as List;
      if (!mounted) return;
      setState(() => _friends = res
          .map((e) => FriendUser.fromJson((e as Map).cast<String, dynamic>()))
          // `/friends` also carries your own Cyber Agents, because they show
          // in the friends list — but an agent has no inbox to invite to.
          // You add one with the Cyber Agent button instead.
          .where((f) => !f.isAgent)
          .toList());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your friends');
    }
  }

  Future<void> _invite() async {
    if (_picked.isEmpty) return;
    setState(() => _sending = true);
    final app = AppScope.of(context);
    var sent = 0;
    String? firstFailure;
    for (final friendId in _picked) {
      try {
        final conv = await app.api.post('/conversations/dm/$friendId') as Map<String, dynamic>;
        await app.api.post('/conversations/${conv['conversationId']}/invites', {'roomId': widget.roomId});
        sent++;
      } on ApiException catch (e) {
        // One friend failing (blocked, unfriended mid-flight) shouldn't sink
        // the rest of the batch — but keep the reason. Reporting "no invites
        // sent" with no explanation leaves nothing to act on.
        firstFailure ??= e.message;
      } catch (_) {
        firstFailure ??= 'Could not reach the server';
      }
    }
    if (!mounted) return;
    if (sent == 0 && firstFailure != null) {
      setState(() {
        _sending = false;
        _error = firstFailure;
      });
      return;
    }
    Navigator.of(context).pop(sent);
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final friends = _friends;
    return NeonGlass(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.viewInsetsOf(context).bottom + 26),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: n.line, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 18),
          Text('ADD A PLAYER',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, letterSpacing: 2)),
          const SizedBox(height: 4),
          Text('They get an invite in their chat with a Join button.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(_error!, style: TextStyle(color: n.danger)),
            )
          else if (friends == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (friends.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('No friends yet — add some from the Friends tab, or share the room code instead.',
                  style: TextStyle(color: n.mute)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: friends.length,
                itemBuilder: (context, i) {
                  final f = friends[i];
                  final on = _picked.contains(f.userId);
                  return CheckboxListTile(
                    value: on,
                    onChanged: _sending
                        ? null
                        : (_) => setState(() => on ? _picked.remove(f.userId) : _picked.add(f.userId)),
                    title: Text(f.displayName),
                    subtitle: Text('@${f.username}', style: TextStyle(color: n.mute)),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  );
                },
              ),
            ),
          const SizedBox(height: 14),
          NeonButton(
            _sending
                ? 'Inviting…'
                : _picked.isEmpty
                    ? 'Pick someone to invite'
                    : 'Invite ${_picked.length} ${_picked.length == 1 ? 'friend' : 'friends'}',
            onPressed: (_sending || _picked.isEmpty) ? null : _invite,
          ),
        ]),
      ),
    );
  }
}
