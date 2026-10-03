import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc show PermissionStatus;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/compact_list_row.dart';
import '../../widgets/neon.dart';

enum _Status { requesting, denied, loading, ready, error }

class _MatchedContact {
  const _MatchedContact({
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

  factory _MatchedContact.fromJson(Map<String, dynamic> j) => _MatchedContact(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String? ?? '',
        username: j['username'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        isFriend: j['isFriend'] as bool? ?? false,
        requestPending: j['requestPending'] as bool? ?? false,
      );
}

class _UnmatchedContact {
  const _UnmatchedContact(this.name, this.phone);
  final String name;
  final String phone;
}

/// Reads the device's contact list (with permission), matches phone numbers
/// against `POST /friends/contacts/match`, and shows two groups: people
/// already on PlayHuud (one-tap Add) and everyone else (one-tap share-sheet
/// invite). Phone numbers never leave the device except as the normalized
/// digit candidates sent to the match endpoint — full contact details
/// (names, other fields) stay local.
class InviteContactsScreen extends StatefulWidget {
  const InviteContactsScreen({super.key});

  @override
  State<InviteContactsScreen> createState() => _InviteContactsScreenState();
}

class _InviteContactsScreenState extends State<InviteContactsScreen> {
  _Status _status = _Status.requesting;
  String? _error;
  List<_MatchedContact> _matched = const [];
  List<_UnmatchedContact> _unmatched = const [];
  final _sendingTo = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = AppScope.of(context); // captured before any await — see use_build_context_synchronously
    setState(() => _status = _Status.requesting);
    // Read-only: this never writes to the address book, and "limited" (the
    // iOS partial-access grant) is a perfectly usable yes — we just see
    // fewer contacts.
    final permission = await FlutterContacts.permissions.request(PermissionType.read);
    if (permission != fc.PermissionStatus.granted && permission != fc.PermissionStatus.limited) {
      if (mounted) setState(() => _status = _Status.denied);
      return;
    }
    setState(() => _status = _Status.loading);
    try {
      final contacts = await FlutterContacts.getAll(properties: {ContactProperty.name, ContactProperty.phone});
      // Every normalized candidate per phone, plus a name lookup so an
      // unmatched result can still show whose number it was.
      final candidateToName = <String, String>{};
      for (final c in contacts) {
        final name = c.displayName ?? '';
        for (final p in c.phones) {
          for (final candidate in _normalize(p.number)) {
            candidateToName.putIfAbsent(candidate, () => name);
          }
        }
      }
      if (candidateToName.isEmpty) {
        if (mounted) setState(() { _status = _Status.ready; _matched = const []; _unmatched = const []; });
        return;
      }
      final res = await app.api.post('/friends/contacts/match', {'phones': candidateToName.keys.toList()}) as List;
      final matched = res.map((e) => _MatchedContact.fromJson((e as Map).cast<String, dynamic>())).toList();
      final matchedPhones = res.map((e) => (e as Map)['matchedPhone'] as String).toSet();
      // Unmatched: one row per contact (not per candidate), first candidate not already matched.
      final seenNames = <String>{};
      final unmatched = <_UnmatchedContact>[];
      for (final c in contacts) {
        final name = c.displayName ?? '';
        if (c.phones.isEmpty || name.isEmpty || seenNames.contains(name)) continue;
        final firstPhone = c.phones.first.number;
        final candidates = _normalize(firstPhone);
        if (candidates.any(matchedPhones.contains)) continue;
        seenNames.add(name);
        unmatched.add(_UnmatchedContact(name, firstPhone));
      }
      if (!mounted) return;
      setState(() { _status = _Status.ready; _matched = matched; _unmatched = unmatched; });
    } catch (_) {
      if (mounted) { setState(() { _status = _Status.error; _error = 'Could not read your contacts'; }); }
    }
  }

  /// No full E.164 parser on the client (v1 scope) — just strip formatting
  /// and try the couple of shapes a US-style number commonly appears in, so
  /// "(555) 123-4567" can still match a stored "+15551234567".
  List<String> _normalize(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const [];
    final out = <String>{raw.trim()};
    out.add(digits);
    out.add('+$digits');
    if (digits.length == 10) {
      out.add('+1$digits');
      out.add('1$digits');
    } else if (digits.length == 11 && digits.startsWith('1')) {
      out.add('+$digits');
      out.add(digits.substring(1));
    }
    return out.toList();
  }

  Future<void> _addFriend(_MatchedContact c) async {
    setState(() => _sendingTo.add(c.userId));
    final app = AppScope.of(context);
    try {
      await app.api.post('/friends/requests/user/${c.userId}');
      if (mounted) {
        setState(() {
          _matched = _matched.map((m) => m.userId == c.userId
              ? _MatchedContact(userId: m.userId, displayName: m.displayName, username: m.username,
                  avatarUrl: m.avatarUrl, isFriend: m.isFriend, requestPending: true)
              : m).toList();
        });
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sendingTo.remove(c.userId));
    }
  }

  void _shareInvite(_UnmatchedContact c) {
    Share.share(
      'Hey ${c.name.split(' ').first}, come play on PlayHuud with me! 🎲',
      subject: 'Join me on PlayHuud',
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: const Text('Invite from Contacts')),
      body: SafeArea(child: _body(n)),
    );
  }

  Widget _body(NeonColors n) {
    switch (_status) {
      case _Status.requesting:
      case _Status.loading:
        return const Center(child: CircularProgressIndicator());
      case _Status.denied:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.contacts_outlined, size: 40, color: n.mute),
              const SizedBox(height: 14),
              Text('Contacts access is off',
                  style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Turn it on in Settings to find friends already on PlayHuud.',
                  textAlign: TextAlign.center, style: TextStyle(color: n.mute)),
              const SizedBox(height: 18),
              NeonButton('Open Settings', style: NeonStyle.ghost, expand: false, onPressed: () => openAppSettings()),
            ]),
          ),
        );
      case _Status.error:
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error ?? 'Something went wrong', style: TextStyle(color: n.danger)),
            const SizedBox(height: 12),
            NeonButton('Retry', style: NeonStyle.ghost, expand: false, onPressed: _load),
          ]),
        );
      case _Status.ready:
        if (_matched.isEmpty && _unmatched.isEmpty) {
          return Center(child: Text('No contacts with phone numbers found.', style: TextStyle(color: n.mute)));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_matched.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('ON PLAYHUUD', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.gold, letterSpacing: 2)),
              ),
              for (var i = 0; i < _matched.length; i++)
                _RowFade(delay: Duration(milliseconds: 30 * i), child: _matchedTile(n, _matched[i])),
              const SizedBox(height: 20),
            ],
            if (_unmatched.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('INVITE TO PLAYHUUD', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, letterSpacing: 2)),
              ),
              for (var i = 0; i < _unmatched.length; i++)
                _RowFade(delay: Duration(milliseconds: 20 * i), child: _unmatchedTile(n, _unmatched[i])),
            ],
          ],
        );
    }
  }

  Widget _matchedTile(NeonColors n, _MatchedContact c) {
    final sending = _sendingTo.contains(c.userId);
    return CompactListRow(
      leading: Avatar(c.displayName, size: 32, imageUrl: c.avatarUrl),
      title: Text(c.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
      subtitle: Text('@${c.username}', maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
      trailing: c.isFriend
          ? Text('Friends', style: TextStyle(color: n.jade, fontWeight: FontWeight.w700, fontSize: 12))
          : c.requestPending
              ? Text('Requested', style: TextStyle(color: n.mute, fontSize: 12))
              : IconButton(tooltip: 'Add friend',
                  icon: sending
                      ? const SizedBox.square(dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.person_add_alt_1_rounded, color: n.jade, size: 20),
                  onPressed: sending ? null : () => _addFriend(c)),
    );
  }

  Widget _unmatchedTile(NeonColors n, _UnmatchedContact c) {
    return CompactListRow(
      leading: Avatar(c.name, size: 32),
      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium),
      trailing: IconButton(
        tooltip: 'Invite',
        icon: Icon(Icons.ios_share_rounded, color: n.mute, size: 20),
        onPressed: () => _shareInvite(c),
      ),
    );
  }
}

/// A short fade+rise, staggered by index — same vocabulary as every other
/// list-settling-into-place moment in the app (wallet history, discovery).
class _RowFade extends StatefulWidget {
  const _RowFade({required this.delay, required this.child});
  final Duration delay;
  final Widget child;

  @override
  State<_RowFade> createState() => _RowFadeState();
}

class _RowFadeState extends State<_RowFade> {
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
    return AnimatedSlide(
      offset: _shown ? Offset.zero : const Offset(0, 0.12),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: widget.child,
      ),
    );
  }
}
