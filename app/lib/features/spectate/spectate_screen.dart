import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/game_socket.dart';
import '../../theme/neon_theme.dart';
import '../whot/whot_watch_screen.dart';
import '../ludo/ludo_watch_screen.dart';

class _Comment {
  const _Comment(this.from, this.text);
  final String from;
  final String text;
}

/// Read-only public game state and the spectator comment channel.
class SpectateScreen extends StatefulWidget {
  const SpectateScreen(
      {super.key, required this.roomId, required this.title, this.gameType});
  final String roomId;
  final String title;
  final String? gameType;

  @override
  State<SpectateScreen> createState() => _SpectateScreenState();
}

class _SpectateScreenState extends State<SpectateScreen> {
  GameSocket? _socket;
  StreamSubscription? _sub;
  String? _phase;
  int _round = 1;
  List<String> _players = [];
  Set<String> _alive = {};
  Map<String, String> _revealedRoles = {};
  Map<String, String> _allRoles = {};
  int _votesLocked = 0;
  int _votesTotal = 0;
  String? _winner;
  int _spectatorCount = 0;
  bool _muted = false;
  final _comments = <_Comment>[];
  final _events = <String>[];
  final _input = TextEditingController();
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.gameType == 'whot' || widget.gameType == 'ludo') return;
    final app = AppScope.of(context);
    _socket = GameSocket.connect(app.api, widget.roomId, spectate: true);
    _sub = _socket!.envelopes.listen(_onEnvelope);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _socket?.close();
    _input.dispose();
    super.dispose();
  }

  void _onEnvelope(Map<String, dynamic> env) {
    if (!mounted) return;
    final type = env['type'] as String?;
    final payload = (env['payload'] as Map?)?.cast<String, dynamic>();
    if (type == 'SNAPSHOT' && payload != null) {
      setState(() {
        _phase = payload['phase'] as String? ?? _phase;
        _round = (payload['round'] as num?)?.toInt() ?? _round;
        _spectatorCount = (payload['spectatorCount'] as num?)?.toInt() ?? _spectatorCount;
        _muted = payload['spectatorsMuted'] as bool? ?? _muted;
        _players = ((payload['players'] as List?) ?? const []).cast<String>();
        _alive =
            ((payload['alive'] as List?) ?? const []).cast<String>().toSet();
        _revealedRoles = ((payload['revealedRoles'] as Map?) ?? const {})
            .cast<String, String>();
        _allRoles =
            ((payload['allRoles'] as Map?) ?? const {}).cast<String, String>();
        _winner = payload['winningSide'] as String? ?? _winner;
        final progress =
            (payload['voteProgress'] as Map?)?.cast<String, dynamic>();
        _votesLocked = (progress?['locked'] as num?)?.toInt() ?? 0;
        _votesTotal = (progress?['total'] as num?)?.toInt() ?? 0;
      });
      return;
    }
    if (type == 'PHASE') {
      setState(() {
        _phase = payload?['phase'] as String?;
        _round = (payload?['round'] as num?)?.toInt() ?? _round;
      });
      return;
    }
    if (type == 'ERROR' && payload?['code'] == 'SPECTATORS_MUTED') {
      setState(() =>
          _muted = true); // our own state was stale — a send bounced, sync up
      return;
    }
    if (type != 'EVENT' || payload == null) return;
    final innerType = payload['type'] as String?;
    if (innerType == 'SPECTATOR_COUNT') {
      final data = (payload['data'] as Map?)?.cast<String, dynamic>();
      setState(() => _spectatorCount =
          (data?['count'] as num?)?.toInt() ?? _spectatorCount);
      return;
    }
    if (innerType == 'SPECTATORS_MUTED') {
      setState(() => _muted = true);
      return;
    }
    if (innerType == 'SPECTATORS_UNMUTED') {
      setState(() => _muted = false);
      return;
    }
    if (innerType == 'CHAT_MESSAGE') {
      final data = (payload['data'] as Map?)?.cast<String, dynamic>();
      if (data?['channel'] == 'spectate') {
        setState(() => _comments.add(_Comment(
            (data?['from'] as String?)?.substring(0, 6) ?? '???',
            data?['text'] as String? ?? '')));
      }
      return;
    }
    final data = (payload['data'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    setState(() {
      if (innerType == 'GAME_STARTED') {
        _players = ((data['players'] as List?) ?? const []).cast<String>();
        _alive = _players.toSet();
      } else if (innerType == 'PLAYER_ELIMINATED') {
        final id = data['id'] as String?;
        if (id != null) {
          _alive.remove(id);
          if (data['roleShown'] == true && data['role'] is String) {
            _revealedRoles[id] = data['role'] as String;
          }
        }
      } else if (innerType == 'VOTE_PROGRESS') {
        _votesLocked = (data['locked'] as num?)?.toInt() ?? _votesLocked;
        _votesTotal = (data['total'] as num?)?.toInt() ?? _votesTotal;
      } else if (innerType == 'GAME_OVER') {
        _winner = data['winningSide'] as String?;
      } else if (innerType == 'FULL_REVEAL') {
        _allRoles =
            ((data['roles'] as Map?) ?? const {}).cast<String, String>();
      }
      final line = _eventLine(innerType, data);
      if (line != null) _events.insert(0, line);
    });
  }

  String _name(String id) => id.length > 6 ? id.substring(0, 6) : id;

  String? _eventLine(String? type, Map<String, dynamic> data) => switch (type) {
        'NIGHT_FALLS' => 'Night falls.',
        'NO_MURDER' => 'No one was murdered.',
        'PLAYER_ELIMINATED' =>
          '${_name(data['id']?.toString() ?? '')} was eliminated${data['roleShown'] == true ? ' (${data['role']})' : ''}.',
        'ROUND_TABLE_OPEN' => 'The round table opens.',
        'ALL_VOTES_IN' => 'All votes are in.',
        'VOTE_REVEALED' =>
          '${_name(data['voter']?.toString() ?? '')} voted for ${_name(data['target']?.toString() ?? '')}.',
        'TIE_NO_ELIMINATION' => 'Tie: no banishment.',
        'TIE_RESOLVED' =>
          'Tie resolved: ${_name(data['chosen']?.toString() ?? '')}.',
        'BANISHED' => '${_name(data['id']?.toString() ?? '')} was banished.',
        'GAME_OVER' =>
          '${data['winningSide'] == 'traitors' ? 'Traitors' : 'Faithful'} win.',
        _ => null,
      };

  void _sendComment() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _socket?.send('CHAT_SEND', {'channel': 'spectate', 'text': text});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.gameType == 'whot') {
      return WhotWatchScreen(roomId: widget.roomId);
    }
    if (widget.gameType == 'ludo') {
      return LudoWatchScreen(roomId: widget.roomId);
    }
    final n = context.neon;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              _pill(n, Icons.visibility_rounded, '$_spectatorCount watching'),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: _phase == null
                    ? const SizedBox.shrink(key: ValueKey('nophase'))
                    : _pill(n, Icons.theater_comedy_rounded, _phase!,
                        key: ValueKey(_phase)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (widget.gameType == 'truearena') ...[
                Text('ROUND $_round · ${_phase ?? 'Connecting…'}',
                    style:
                        TextStyle(color: n.gold, fontWeight: FontWeight.bold)),
                if (_winner != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                          '${_winner == 'traitors' ? 'Traitors' : 'Faithful'} win',
                          style: TextStyle(
                              color: n.jade,
                              fontSize: 18,
                              fontWeight: FontWeight.bold))),
                if (_phase == 'Vote')
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Votes locked: $_votesLocked / $_votesTotal',
                          style: TextStyle(color: n.mid))),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final id in _players)
                    Chip(
                        label: Text(
                            '${_name(id)}${_alive.contains(id) ? '' : ' · out'}${(_allRoles[id] ?? _revealedRoles[id]) == null ? '' : ' · ${_allRoles[id] ?? _revealedRoles[id]}'}'),
                        backgroundColor: n.panel,
                        labelStyle: TextStyle(
                            color: _alive.contains(id) ? n.ink : n.mute)),
                ]),
                const SizedBox(height: 18),
              ],
              if (_events.isEmpty)
                Text('Watching live — nothing to report yet.',
                    style: TextStyle(color: n.mute)),
              for (final event in _events)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(event,
                        style: TextStyle(color: n.mid, fontSize: 13))),
            ]),
          ),
          if (_comments.isNotEmpty)
            SizedBox(
              height: 120,
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _comments.length,
                itemBuilder: (context, i) {
                  final c = _comments[_comments.length - 1 - i];
                  return _CommentBubble(comment: c);
                },
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _muted
                    ? Container(
                        key: const ValueKey('muted'),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: n.panel,
                            borderRadius: BorderRadius.circular(12)),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.comments_disabled_rounded,
                                  size: 16, color: n.mute),
                              const SizedBox(width: 8),
                              Text('The players have muted spectator chat',
                                  style:
                                      TextStyle(color: n.mute, fontSize: 12)),
                            ]),
                      )
                    : Row(key: const ValueKey('open'), children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            maxLength: 240,
                            decoration: const InputDecoration(
                                hintText: 'Say something…', counterText: ''),
                            onSubmitted: (_) => _sendComment(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                            onPressed: _sendComment,
                            icon: const Icon(Icons.send_rounded)),
                      ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pill(NeonColors n, IconData icon, String text, {Key? key}) =>
      Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: n.panel,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: n.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: n.jade),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(
                  color: n.mid, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// A comment bounces up from the bottom, same "arriving" language as the
/// chat conversation bubbles — TikTok-style scrolling comments, but the
/// same fade+slide vocabulary the rest of the app uses.
class _CommentBubble extends StatefulWidget {
  const _CommentBubble({required this.comment});
  final _Comment comment;

  @override
  State<_CommentBubble> createState() => _CommentBubbleState();
}

class _CommentBubbleState extends State<_CommentBubble>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
            .animate(curved),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: RichText(
            text: TextSpan(children: [
              TextSpan(
                  text: '${widget.comment.from}  ',
                  style: TextStyle(
                      color: n.jade,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
              TextSpan(
                  text: widget.comment.text,
                  style: TextStyle(color: n.mid, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}
