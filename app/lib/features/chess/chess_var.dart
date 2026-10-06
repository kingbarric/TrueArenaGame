import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chess_piece.dart';
import 'chess_view.dart';

/// One move as VAR remembers it: the board just before it, the board just
/// after, and what was played.
class ChessVarMove {
  const ChessVarMove({
    required this.side,
    required this.san,
    required this.from,
    required this.to,
    required this.before,
    required this.after,
  });

  /// 'white' or 'black' — who played it.
  final String side;
  final String san;
  final int from;
  final int to;
  final List<String?> before;
  final List<String?> after;

  /// The rook's hop when this move castled, else null.
  (int, int)? get castleRook {
    final piece = before[from];
    if (piece == null ||
        piece[1] != 'K' ||
        (fileOf(to) - fileOf(from)).abs() != 2) {
      return null;
    }
    final rank = rankOf(from);
    return fileOf(to) > fileOf(from)
        ? (rank * 8 + 7, rank * 8 + 5)
        : (rank * 8, rank * 8 + 3);
  }

  /// What the move took, if anything — including a pawn taken en passant.
  String? get captured {
    if (before[to] != null) return before[to];
    final piece = before[from];
    if (piece != null && piece[1] == 'P' && fileOf(from) != fileOf(to)) {
      return before[rankOf(from) * 8 + fileOf(to)];
    }
    return null;
  }

  bool get promoted => before[from]?[1] == 'P' && after[to]?[1] != 'P';
}

/// The chess VAR: replays the opponent's last move on its own board, the
/// way Draughts' VAR replays a capture sequence — same controls (replay,
/// pause, 0.5x/1x/2x), same idea of letting you watch what just happened.
class ChessVarSheet extends StatefulWidget {
  const ChessVarSheet({
    super.key,
    required this.move,
    required this.playerName,
    required this.flipped,
  });

  final ChessVarMove move;
  final String playerName;
  final bool flipped;

  @override
  State<ChessVarSheet> createState() => _ChessVarSheetState();
}

class _ChessVarSheetState extends State<ChessVarSheet>
    with SingleTickerProviderStateMixin {
  static const _gold = Color(0xffffcf66);
  static const _cream = Color(0xfffff1dc);
  static const _mute = Color(0xffa894c4);

  late final AnimationController _slide = AnimationController(vsync: this);

  /// 0 = before the move, 1 = sliding, 2 = landed.
  int _stage = 0;
  bool _paused = false;
  double _speed = 1;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void dispose() {
    _token++;
    _slide.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    final token = ++_token;
    setState(() {
      _stage = 0;
      _paused = false;
    });
    _slide.value = 0;
    await Future<void>.delayed(Duration(milliseconds: (700 / _speed).round()));
    if (!mounted || token != _token) return;
    while (_paused) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted || token != _token) return;
    }
    setState(() => _stage = 1);
    _slide.duration = Duration(milliseconds: (650 / _speed).round());
    await _slide.forward(from: 0).orCancel.catchError((_) {});
    if (!mounted || token != _token) return;
    setState(() => _stage = 2);
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_stage == 1) {
      _paused ? _slide.stop() : _slide.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.move;
    final taken = m.captured;
    final detail = [
      if (taken != null) 'takes ${_pieceName(taken)}',
      if (m.castleRook != null) 'castles',
      if (m.promoted) 'promotes',
      if (m.san.endsWith('#')) 'checkmate',
      if (m.san.endsWith('+')) 'check',
    ].join(' · ');
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('chess-var-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.76,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: Column(children: [
            Row(children: [
              const Text('VAR REPLAY',
                  style: TextStyle(
                      color: _gold, fontSize: 15, fontWeight: FontWeight.w900)),
              const Spacer(),
              IconButton(
                tooltip: 'Close replay',
                color: _cream,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  '${widget.playerName} played ${m.san}${detail.isEmpty ? '' : ' · $detail'}',
                  key: const ValueKey('chess-var-caption'),
                  style: const TextStyle(color: _mute, fontSize: 12)),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: LayoutBuilder(builder: (context, limits) {
                final side = math.min(limits.maxWidth, limits.maxHeight);
                final cell = (side - 16) / 8;
                return Center(
                  child: Container(
                    width: side,
                    height: side,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(colors: [
                        Color(0xff8a5a2b),
                        Color(0xff5a3416),
                        Color(0xff7a4a20)
                      ]),
                    ),
                    child: AnimatedBuilder(
                      animation: _slide,
                      builder: (context, _) => Stack(children: [
                        _squares(cell),
                        ..._pieces(cell),
                      ]),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            // Scales down rather than overflowing on a narrow phone.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Replay from start',
                  color: _cream,
                  onPressed: _play,
                  icon: const Icon(Icons.replay_rounded),
                ),
                IconButton(
                  tooltip: _paused ? 'Resume replay' : 'Pause replay',
                  color: _cream,
                  onPressed: _stage == 2 ? _play : _togglePause,
                  icon: Icon(_stage == 2 || _paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded),
                ),
                const SizedBox(width: 12),
                SegmentedButton<double>(
                  segments: const [
                    ButtonSegment(value: 0.5, label: Text('0.5x')),
                    ButtonSegment(value: 1, label: Text('1x')),
                    ButtonSegment(value: 2, label: Text('2x')),
                  ],
                  selected: {_speed},
                  onSelectionChanged: (speed) =>
                      setState(() => _speed = speed.first),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Offset _cellOffset(int sq, double cell) {
    final col = widget.flipped ? 7 - fileOf(sq) : fileOf(sq);
    final row = widget.flipped ? rankOf(sq) : 7 - rankOf(sq);
    return Offset(col * cell, row * cell);
  }

  Widget _squares(double cell) {
    final m = widget.move;
    return Column(children: [
      for (var row = 0; row < 8; row++)
        Row(children: [
          for (var col = 0; col < 8; col++)
            Builder(builder: (_) {
              final sq = squareAtCell(row, col, flipped: widget.flipped);
              final light = (fileOf(sq) + rankOf(sq)) % 2 == 1;
              final lit = _stage > 0 && (sq == m.from || sq == m.to);
              return Container(
                width: cell,
                height: cell,
                color: lit
                    ? Color.alphaBlend(
                        const Color(0x88f6e96b),
                        light
                            ? const Color(0xffeeeed2)
                            : const Color(0xff769656))
                    : (light
                        ? const Color(0xffeeeed2)
                        : const Color(0xff769656)),
              );
            }),
        ]),
    ]);
  }

  List<Widget> _pieces(double cell) {
    final m = widget.move;
    if (_stage == 2) {
      return [
        for (var sq = 0; sq < 64; sq++)
          if (m.after[sq] != null) _at(sq, m.after[sq]!, cell),
      ];
    }
    final rook = m.castleRook;
    final t = Curves.easeInOutCubic.transform(_slide.value);
    final out = <Widget>[];
    for (var sq = 0; sq < 64; sq++) {
      final code = m.before[sq];
      if (code == null) continue;
      if (_stage == 1 && (sq == m.from || sq == rook?.$1)) continue;
      // The captured piece fades as the attacker arrives.
      final victim = _stage == 1 &&
          m.captured != null &&
          (sq == m.to ||
              (m.before[m.to] == null &&
                  sq == rankOf(m.from) * 8 + fileOf(m.to)));
      out.add(
          _at(sq, code, cell, opacity: victim ? (1 - t).clamp(0.0, 1.0) : 1));
    }
    if (_stage == 1) {
      if (rook != null) {
        out.add(_sliding(rook.$1, rook.$2, m.before[rook.$1]!, t, cell));
      }
      out.add(_sliding(m.from, m.to, m.before[m.from]!, t, cell));
    }
    return out;
  }

  Widget _at(int sq, String code, double cell, {double opacity = 1}) {
    final o = _cellOffset(sq, cell);
    return Positioned(
      left: o.dx,
      top: o.dy,
      width: cell,
      height: cell,
      child: Opacity(
        opacity: opacity,
        child: Center(child: ChessPieceGlyph(code: code, size: cell * 0.86)),
      ),
    );
  }

  Widget _sliding(int from, int to, String code, double t, double cell) {
    final o = Offset.lerp(_cellOffset(from, cell), _cellOffset(to, cell), t)!;
    return Positioned(
      left: o.dx,
      top: o.dy,
      width: cell,
      height: cell,
      child: Center(child: ChessPieceGlyph(code: code, size: cell * 0.9)),
    );
  }

  static String _pieceName(String code) => switch (code[1]) {
        'Q' => 'queen',
        'R' => 'rook',
        'B' => 'bishop',
        'N' => 'knight',
        'K' => 'king',
        _ => 'pawn',
      };
}
