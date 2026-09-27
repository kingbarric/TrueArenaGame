import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import 'neon.dart';

/// One line in a game's table talk: something a person (or an agent) said,
/// or a note about the game itself. System lines carry no speaker, which is
/// what makes them render quietly rather than as a message.
class TableChatLine {
  const TableChatLine({
    this.who,
    required this.text,
    this.isAgent = false,
    this.isSpectator = false,
  }) : isSystem = false;

  const TableChatLine.system(this.text)
      : who = null,
        isSystem = true,
        isAgent = false,
        isSpectator = false;

  final String? who;
  final String text;
  final bool isSystem;
  final bool isAgent;
  final bool isSpectator;
}

/// The chat every game screen carries: players, Cyber Agents and spectators
/// in one frosted panel, newest at the bottom, with the box to type in built
/// into the same surface.
///
/// There is deliberately no sheet to open — chat you have to go and find is
/// chat nobody reads during a game — and no separate spectator bar, because
/// splitting the two meant most of what was said went unseen.
///
/// [lines] is newest-first; the list is reversed on screen so the newest sits
/// at the bottom, which also keeps it pinned there as messages arrive without
/// a scroll controller to manage.
class TableChatPanel extends StatelessWidget {
  const TableChatPanel({
    super.key,
    required this.lines,
    required this.controller,
    required this.onSend,
    required this.spectatorCount,
    required this.amSpectator,
    this.height = 146,
    this.canSend = true,
    this.disabledHint,
  });

  final List<TableChatLine> lines;
  final TextEditingController controller;
  final VoidCallback onSend;
  final int spectatorCount;
  final bool amSpectator;

  /// Roughly five compact messages by default — enough to follow an
  /// exchange without the board losing the screen.
  final double height;

  /// Whether this viewer may talk right now. Traitors, for one, only opens
  /// table talk during the round table — outside it the box still shows
  /// everything said, it just can't be typed in.
  final bool canSend;

  /// Why they can't, shown in place of the input.
  final String? disabledHint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              // A pale wash over the board so the panel is plainly its own
              // surface, without going opaque and boxing the game in.
              color: Colors.white.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: height, child: _messages()),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.16)),
              _composer(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _messages() {
    if (lines.isEmpty) {
      return Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Text('Say something — anyone watching can join in.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
        ),
      );
    }
    // Older messages dissolve upward instead of hitting a hard edge, which
    // is what keeps the stack feeling live.
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black, Colors.black],
        stops: [0.0, 0.3, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        itemCount: lines.length,
        itemBuilder: (_, i) => _row(lines[i], depth: i),
      ),
    );
  }

  /// One message: a small avatar, then the name and what they said running
  /// together on a single flowing line the way live chat does. Capped at two
  /// lines — past that it's a speech, and it would push the board off the
  /// screen.
  Widget _row(TableChatLine line, {required int depth}) {
    // Newest is fully lit; each one above sits back a little further.
    final fade = (1.0 - depth * 0.13).clamp(0.45, 1.0);

    if (line.isSystem) {
      return Opacity(
        opacity: fade,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            line.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62), fontSize: 11, fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    final who = line.who ?? '';
    final nameColor = line.isAgent
        ? const Color(0xffff8fab)
        : line.isSpectator
            ? const Color(0xffb9e4c0)
            : const Color(0xfff2c368);
    return Opacity(
      opacity: fade,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Avatar(who, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: const TextStyle(fontSize: 13, height: 1.32, color: Colors.white),
                children: [
                  TextSpan(
                    text: who,
                    style: TextStyle(color: nameColor, fontWeight: FontWeight.w800, fontSize: 12.5),
                  ),
                  if (line.isAgent || line.isSpectator)
                    TextSpan(
                      text: line.isAgent ? '  AGENT' : '  WATCHING',
                      style: TextStyle(
                          color: nameColor.withValues(alpha: 0.75),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6),
                    ),
                  const TextSpan(text: '   '),
                  TextSpan(text: line.text),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _composer() {
    if (!canSend) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(children: [
          Icon(Icons.lock_outline_rounded, size: 13, color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              disabledHint ?? 'You can\'t talk right now.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
            ),
          ),
          Icon(Icons.remove_red_eye_rounded, size: 13, color: Colors.white.withValues(alpha: 0.5)),
          const SizedBox(width: 4),
          Text('$spectatorCount',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w800)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            maxLength: 240,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              border: InputBorder.none,
              hintText: amSpectator ? 'Add a comment…' : 'Say something…',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13.5),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            Icon(Icons.remove_red_eye_rounded, size: 13, color: Colors.white.withValues(alpha: 0.6)),
            const SizedBox(width: 4),
            Text('$spectatorCount',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75), fontSize: 11, fontWeight: FontWeight.w800)),
          ]),
        ),
        GestureDetector(
          onTap: onSend,
          child: Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.symmetric(vertical: 5),
            decoration: const BoxDecoration(color: Color(0xffc02b52), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}
