import 'dart:async';

import 'package:flutter/material.dart';

import '../core/game_socket.dart';

/// One spectator comment — the always-open `spectate` chat channel (see
/// `ChatMessage.SPECTATE`, ta-room) that's open in the lobby and mid-game,
/// in every game type, to players and spectators alike.
class _Comment {
  _Comment(this.from, this.text);
  final String from;
  final String text;
}

/// A slim bar living outside the actual playing surface — a live spectator
/// count plus the latest comment, tap to open the full TikTok-style comment
/// feed. Drop this into any game screen's `Column`
/// (`SpectatorBar(socket: widget.socket, nicknames: nicknames)`) — it wires
/// itself up against the shared `spectate` chat channel and the generic
/// `spectatorCount` SNAPSHOT field, so nothing else about the screen needs
/// to change.
class SpectatorBar extends StatefulWidget {
  const SpectatorBar({super.key, required this.socket, this.nicknames = const {}});
  final GameSocket socket;
  final Map<String, String> nicknames;

  @override
  State<SpectatorBar> createState() => _SpectatorBarState();
}

class _SpectatorBarState extends State<SpectatorBar> {
  StreamSubscription? _sub;
  int _count = 0;
  final List<_Comment> _comments = [];

  @override
  void initState() {
    super.initState();
    _sub = widget.socket.envelopes.listen(_onEnvelope);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onEnvelope(Map<String, dynamic> env) {
    if (env['type'] != 'EVENT' && env['type'] != 'SNAPSHOT') return;
    final p = (env['payload'] as Map).cast<String, dynamic>();
    if (env['type'] == 'SNAPSHOT' && p['spectatorCount'] != null) {
      if (mounted) setState(() => _count = p['spectatorCount'] as int);
      return;
    }
    if (p['type'] == 'SPECTATOR_COUNT') {
      final data = (p['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (mounted) setState(() => _count = data['count'] as int? ?? _count);
      return;
    }
    if (p['type'] == 'CHAT_MESSAGE') {
      final data = (p['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (data['channel'] != 'spectate') return;
      final from = data['from']?.toString() ?? '';
      final text = data['text']?.toString() ?? '';
      if (text.isEmpty || !mounted) return;
      setState(() {
        _comments.add(_Comment(from, text));
        if (_comments.length > 60) _comments.removeAt(0);
      });
    }
  }

  String _label(String id) => widget.nicknames[id] ?? (id.length > 6 ? id.substring(0, 6) : id);

  void _openSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff17110c),
      builder: (_) => _SpectatorChatSheet(socket: widget.socket, label: _label, comments: _comments, count: _count),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latest = _comments.isEmpty ? null : _comments.last;
    return InkWell(
      onTap: _openSheet,
      child: Container(
        height: 42,
        margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(children: [
          const Icon(Icons.remove_red_eye_rounded, size: 15, color: Colors.white70),
          const SizedBox(width: 5),
          Text('$_count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(width: 10),
          Container(width: 1, height: 16, color: Colors.white.withValues(alpha: 0.14)),
          const SizedBox(width: 10),
          Expanded(
            child: latest == null
                ? const Text('Spectators can comment here', overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white38, fontSize: 12))
                : RichText(
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(style: const TextStyle(fontSize: 12, color: Colors.white70), children: [
                      TextSpan(text: '${_label(latest.from)}  ', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                      TextSpan(text: latest.text),
                    ]),
                  ),
          ),
          const Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: Colors.white38),
        ]),
      ),
    );
  }
}

class _SpectatorChatSheet extends StatefulWidget {
  const _SpectatorChatSheet({required this.socket, required this.label, required this.comments, required this.count});
  final GameSocket socket;
  final String Function(String) label;
  final List<_Comment> comments;
  final int count;

  @override
  State<_SpectatorChatSheet> createState() => _SpectatorChatSheetState();
}

class _SpectatorChatSheetState extends State<_SpectatorChatSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription? _sub;
  late List<_Comment> _comments;

  @override
  void initState() {
    super.initState();
    _comments = List.of(widget.comments);
    _sub = widget.socket.envelopes.listen((env) {
      if (env['type'] != 'EVENT') return;
      final p = (env['payload'] as Map).cast<String, dynamic>();
      if (p['type'] != 'CHAT_MESSAGE') return;
      final data = (p['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (data['channel'] != 'spectate') return;
      final text = data['text']?.toString() ?? '';
      if (text.isEmpty || !mounted) return;
      setState(() => _comments.add(_Comment(data['from']?.toString() ?? '', text)));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    widget.socket.send('CHAT_SEND', {'channel': 'spectate', 'text': text});
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Row(children: [
              const Icon(Icons.remove_red_eye_rounded, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Text('${widget.count} watching', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20), onPressed: () => Navigator.of(context).pop()),
            ]),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: _comments.isEmpty
                ? const Center(child: Text('No comments yet — say hi 👋', style: TextStyle(color: Colors.white38, fontSize: 13)))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    itemCount: _comments.length,
                    itemBuilder: (context, i) {
                      final c = _comments[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: RichText(
                          text: TextSpan(style: const TextStyle(fontSize: 13.5, color: Colors.white, height: 1.35), children: [
                            TextSpan(text: '${widget.label(c.from)}  ', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xffe0a94a))),
                            TextSpan(text: c.text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w400)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    maxLength: 240,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Add a comment…',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _send,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  style: IconButton.styleFrom(backgroundColor: const Color(0xffe0a94a), foregroundColor: const Color(0xff241708)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
