import 'dart:async';

import 'package:flutter/material.dart';

import 'package:cryptography/cryptography.dart' show SecretKey;

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/e2e_crypto.dart';
import '../../core/models.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/game_badge.dart';
import '../../widgets/neon.dart';
import '../games/game_select_screen.dart';
import '../lobby/joined_room_screen.dart';
import '../onboarding/guest_gate.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.kind,
    this.text,
    this.roomId,
    this.roomCode,
    this.gameType,
    required this.createdAt,
  });

  final String id;
  final String senderId;
  final String kind; // 'text' | 'game_invite'
  final String? text;
  final String? roomId;
  final String? roomCode;
  final String? gameType;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        senderId: j['senderId'] as String,
        kind: j['kind'] as String,
        text: j['text'] as String?,
        roomId: j['roomId'] as String?,
        roomCode: j['roomCode'] as String?,
        gameType: j['gameType'] as String?,
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

const _gameNames = {'truearena': 'Traitors', 'wordbluff': 'Word Bluff', 'draughts': 'Draft', 'goosi': 'Goosi'};

/// One DM or group thread. Live push rides `AppState.chatMessages` (the
/// `/ws/inbox` `NEW_MESSAGE` frame `ChatService` fans out right after every
/// send — see ta-api) — no polling. A `game_invite` message renders its own
/// "Join game" button, which actually joins the real room (`POST
/// /rooms/join` with the invite's code) and hands off to the right game
/// screen — the same path `JoinRoomScreen` uses.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversationId, required this.title});
  final String conversationId;
  final String title;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  List<ChatMessage> _messages = [];
  bool _loading = true;
  String? _error;
  bool _joining = false;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription? _chatSub;
  AppState? _app;
  bool _started = false;

  /// Non-null once we've learned the other participant's public key and
  /// derived the DM's shared secret — that's also what makes this thread
  /// show as encrypted. Null for a group thread, or a DM where the peer
  /// hasn't published a key yet: those stay plaintext (see `E2eCrypto`).
  SecretKey? _secret;
  bool _encrypted = false;

  /// Decrypted bodies by message id, so a rebuild doesn't re-run AES for
  /// every bubble on every frame (decryption is async; the render path is
  /// not).
  final _plaintext = <String, String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _setUpEncryption();
      await _load();
    });
  }

  /// Looks up this conversation to find the other participant's public key
  /// (DMs only — a group thread has no single peer) and derives the shared
  /// secret. Silent no-op on any failure: the thread just stays plaintext,
  /// exactly as it behaved before encryption existed.
  Future<void> _setUpEncryption() async {
    final app = AppScope.of(context);
    try {
      final conv = await app.api.get('/conversations/${widget.conversationId}') as Map<String, dynamic>;
      if (conv['type'] != 'dm') return;
      final other = (conv['other'] as Map?)?.cast<String, dynamic>();
      final secret = await E2eCrypto.sharedSecretWith(other?['publicKey'] as String?);
      if (secret == null || !mounted) return;
      setState(() {
        _secret = secret;
        _encrypted = true;
      });
    } catch (_) {
      // no key / no lookup — stay plaintext
    }
  }

  /// Decrypts any `e2e1:` bodies we haven't already cached, then repaints.
  Future<void> _decryptPending(List<ChatMessage> messages) async {
    final secret = _secret;
    if (secret == null) return;
    var changed = false;
    for (final m in messages) {
      final body = m.text;
      if (body == null || _plaintext.containsKey(m.id) || !E2eCrypto.isEncrypted(body)) continue;
      final clear = await E2eCrypto.decrypt(secret, body);
      _plaintext[m.id] = clear ?? '🔒 Couldn\'t decrypt this message';
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  /// What to actually render for a text bubble: the decrypted body if this
  /// was an encrypted message, otherwise the raw text (a group message, or
  /// a DM from before both sides had keys).
  String _displayText(ChatMessage m) {
    final body = m.text ?? '';
    if (!E2eCrypto.isEncrypted(body)) return body;
    return _plaintext[m.id] ?? '…';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _app = AppScope.of(context);
    _chatSub = _app!.chatMessages.listen(_onPush);
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A `NEW_MESSAGE` push for this thread — appended straight into the list
  /// (each bubble's own entrance fade/slide handles the "arriving" feel)
  /// rather than a full reload, so an open conversation feels instant.
  void _onPush(Map<String, dynamic> data) {
    if (data['conversationId'] != widget.conversationId) return;
    final m = ChatMessage.fromJson((data['message'] as Map).cast<String, dynamic>());
    if (!mounted || _messages.any((e) => e.id == m.id)) return;
    final wasAtBottom = !_scroll.hasClients || _scroll.position.pixels >= _scroll.position.maxScrollExtent - 40;
    setState(() => _messages = [..._messages, m]);
    _decryptPending([m]);
    if (wasAtBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
        }
      });
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final app = AppScope.of(context);
    try {
      final res = await app.api.get('/conversations/${widget.conversationId}/messages') as Map<String, dynamic>;
      final list = ((res['messages'] as List?) ?? const [])
          .map((e) => ChatMessage.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      if (!mounted) return;
      final wasAtBottom = !_scroll.hasClients || _scroll.position.pixels >= _scroll.position.maxScrollExtent - 40;
      setState(() {
        _messages = list;
        _error = null;
      });
      await _decryptPending(list);
      if (wasAtBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } on ApiException catch (e) {
      if (mounted && !silent) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && !silent) setState(() => _error = 'Could not reach the server');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    final app = AppScope.of(context);
    try {
      // Encrypted before it ever leaves the device when this DM has a shared
      // secret — the server stores and relays an opaque `e2e1:` blob.
      final secret = _secret;
      final body = secret == null ? text : await E2eCrypto.encrypt(secret, text);
      // The sender doesn't get their own NEW_MESSAGE push (ChatService only
      // fans out to the *other* participants), so reload just this once to
      // pick up our own message — every message after that arrives live.
      await app.api.post('/conversations/${widget.conversationId}/messages', {'text': body});
      await _load(silent: true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _joinInvite(ChatMessage m) async {
    if (m.roomCode == null || _joining) return;
    setState(() => _joining = true);
    final app = AppScope.of(context);
    try {
      final res = await app.api.post('/rooms/join', {'code': m.roomCode}) as Map<String, dynamic>;
      if (!mounted) return;
      final room = RoomView.fromJson(res);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => JoinedRoomScreen(room: room)));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  String _selfId(AppState app) => app.user?.id ?? '';

  /// The "Start game" button: pick a game from a bottom sheet, create the
  /// room, drop a `game_invite` into this thread for the other side, then
  /// carry the host straight into their own lobby for it. The other
  /// participant sees the same invite the next time their thread polls and
  /// gets the identical "Join game" button already built into every
  /// `game_invite` bubble — no separate notification path needed.
  Future<void> _startGame() async {
    if (!await canHostOrPromptToVerify(context)) return;
    if (!mounted) return;
    final picked = await showModalBottomSheet<GameCatalogEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _GameStartSheet(),
    );
    if (picked == null || !mounted) return;

    final app = AppScope.of(context);
    try {
      final roomRes = await app.api.post('/rooms', {'gameType': picked.id}) as Map<String, dynamic>;
      final room = RoomView.fromJson(roomRes);
      await app.api.post('/conversations/${widget.conversationId}/invites', {'roomId': room.id});
      await _load(silent: true);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => JoinedRoomScreen(room: room)));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start the game')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final app = AppScope.of(context);
    final selfId = _selfId(app);
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Flexible(child: Text(widget.title, overflow: TextOverflow.ellipsis)),
          if (_encrypted) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'End-to-end encrypted',
              child: Icon(Icons.lock_rounded, size: 14, color: n.jade),
            ),
          ],
        ]),
        actions: [
        IconButton(
          tooltip: 'Start a game',
          icon: Icon(Icons.sports_esports_rounded, color: n.jade),
          onPressed: _startGame,
        ),
      ]),
      body: SafeArea(
        child: Column(children: [
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: n.danger))),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(child: Text('No messages yet — say hi 👋', style: TextStyle(color: n.mute)))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final mine = m.senderId == selfId;
                          return _BubbleEntrance(
                            key: ValueKey(m.id),
                            alignEnd: mine,
                            child: m.kind == 'game_invite' ? _inviteBubble(n, m) : _textBubble(n, m, mine),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    maxLength: 2000,
                    decoration: const InputDecoration(hintText: 'Message…', counterText: ''),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _send, icon: const Icon(Icons.send_rounded)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _textBubble(NeonColors n, ChatMessage m, bool mine) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: mine ? n.brand.withValues(alpha: 0.85) : n.panel,
        borderRadius: BorderRadius.circular(16),
        border: mine ? null : Border.all(color: n.line),
      ),
      child: Text(_displayText(m), style: TextStyle(color: mine ? Colors.white : n.ink)),
    );
  }

  Widget _inviteBubble(NeonColors n, ChatMessage m) {
    final gameName = _gameNames[m.gameType] ?? m.gameType ?? 'a game';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: n.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: n.jade.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.sports_esports_rounded, color: n.jade, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('Invited you to $gameName', style: TextStyle(color: n.ink, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 10),
        NeonButton(_joining ? 'Joining…' : 'Join game', onPressed: _joining ? null : () => _joinInvite(m)),
      ]),
    );
  }
}

/// The "pick a game" sheet `_startGame` opens — each tile fades/scales in
/// with a short staggered delay so the menu feels like it's popping up
/// rather than just appearing.
class _GameStartSheet extends StatelessWidget {
  const _GameStartSheet();

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final available = gameCatalog.where((g) => g.available).toList();
    return Container(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.viewInsetsOf(context).bottom + 28),
      decoration: BoxDecoration(
        color: n.panel.withValues(alpha: 0.9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(width: 40, height: 4, decoration: BoxDecoration(color: n.line, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 18),
        Text('START A GAME', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute, letterSpacing: 2)),
        const SizedBox(height: 4),
        Text('Whoever you pick shows up right here as a Join button.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: n.mute)),
        const SizedBox(height: 18),
        Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            for (var i = 0; i < available.length; i++)
              _AnimatedTile(
                delay: Duration(milliseconds: 70 * i),
                child: Bouncy(
                  onTap: () => Navigator.of(context).pop(available[i]),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    GameBadge(gameId: available[i].id, size: 68),
                  ]),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}

/// Every message bubble's entrance — a short fade + upward slide, keyed by
/// message id so `ListView.builder` treats it as the same element across
/// rebuilds (a scrolled-past bubble doesn't replay this when it comes back
/// into view). Applies to both the initial load and a live `NEW_MESSAGE`
/// arrival alike — one animation, not a special case for "just arrived".
class _BubbleEntrance extends StatefulWidget {
  const _BubbleEntrance({super.key, required this.alignEnd, required this.child});
  final bool alignEnd;
  final Widget child;

  @override
  State<_BubbleEntrance> createState() => _BubbleEntranceState();
}

class _BubbleEntranceState extends State<_BubbleEntrance> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return Align(
      alignment: widget.alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(curved),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fades + scales its child in, `delay` after first appearing — that gap
/// per tile is what makes a row of them read as popping up in sequence
/// rather than all at once.
class _AnimatedTile extends StatefulWidget {
  const _AnimatedTile({required this.delay, required this.child});
  final Duration delay;
  final Widget child;

  @override
  State<_AnimatedTile> createState() => _AnimatedTileState();
}

class _AnimatedTileState extends State<_AnimatedTile> {
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
    return AnimatedScale(
      scale: _shown ? 1 : 0.6,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: widget.child,
      ),
    );
  }
}
