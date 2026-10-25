import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'draughts_rules.dart';

const draughtsFinishers = ['royal', 'thunder', 'fire', 'neon', 'confetti'];

class DraughtsCue {
  const DraughtsCue(this.id, this.kind,
      {this.square,
      this.victimSquare,
      this.trail = const [],
      this.count = 0,
      this.chainId = 0,
      this.king = false,
      this.effect = 'royal',
      this.blocked = false});
  final int id, count, chainId;
  final String kind, effect;
  final int? square, victimSquare;
  final List<int> trail;
  final bool king, blocked;
  String get title => switch (kind) {
        'capture' => [
            if (king) 'KING DOWN',
            if (count >= 2)
              count == 2
                  ? 'DOUBLE TAKE'
                  : count == 3
                      ? 'TRIPLE TAKE'
                      : 'BOARD SWEEP ×$count'
          ].join(' · '),
        'crown' => 'KING ME',
        'seize' => 'SEIZED',
        'decisive' => blocked ? 'NO WAY OUT' : 'FINAL TAKE',
        'finish' => 'VICTORY',
        _ => '',
      };
}

/// Presentation only. Bounded cues follow confirmed events, never legal-move
/// predictions. A snapshot establishes the sequence floor; reconnect and VAR
/// discard celebrations instead of replaying them.
class DraughtsEffects extends ChangeNotifier {
  DraughtsCue? current;
  final _queue = <DraughtsCue>[];
  Timer? _advance;
  bool ready = false;
  int _seq = -1, _serial = 0, _captures = 0, _chainId = 0;
  int? _lastSquare;
  final _trail = <int>[];
  bool _finishing = false;
  int get captureCount => _captures;
  bool get holdFinalBoard => _finishing && current?.kind != 'finish';

  void synchronize(int seq) {
    silence();
    _seq = math.max(_seq, seq);
    _captures = 0;
    _chainId++;
    _trail.clear();
    _lastSquare = null;
    ready = true;
  }

  void suspend() {
    ready = false;
    silence();
  }

  void silence() {
    _advance?.cancel();
    _advance = null;
    current = null;
    _queue.clear();
    _finishing = false;
    notifyListeners();
  }

  void event(String type, Map<String, dynamic> data, int? seq,
      {bool muted = false}) {
    if (!ready || seq == null || seq <= _seq) return;
    _seq = seq;
    if (type == 'TURN_STARTED') {
      _chainId++;
      _captures = 0;
      _trail.clear();
    }
    if (type == 'UNDO_ACCEPTED') {
      silence();
      _captures = 0;
      _trail.clear();
    }
    if (type == 'GAME_PAUSED') silence();
    if (muted) return;
    switch (type) {
      case 'PIECE_MOVED':
        _lastSquare = data['to'] as int?;
      case 'PIECE_CAPTURED':
        final from = data['from'] as int, to = data['to'] as int;
        if (_trail.isEmpty) _trail.add(from);
        _trail.add(to);
        _lastSquare = to;
        _captures = (data['captureCount'] as num?)?.toInt() ?? _captures + 1;
        _enqueue(DraughtsCue(++_serial, 'capture',
            square: to,
            victimSquare: data['captured'] as int?,
            trail: List.of(_trail),
            count: _captures,
            chainId: _chainId,
            king: data['capturedKing'] == true));
      case 'PIECE_PROMOTED':
        _enqueue(
            DraughtsCue(++_serial, 'crown', square: data['square'] as int));
      case 'PIECE_SEIZED':
        _lastSquare = data['square'] as int;
        _enqueue(DraughtsCue(++_serial, 'seize', square: _lastSquare));
      case 'GAME_OVER':
        if (!['A', 'B'].contains(data['winningSide'])) return;
        _finishing = true;
        if (data['reason'] == 'capture' || data['reason'] == 'blocked') {
          _enqueue(DraughtsCue(++_serial, 'decisive',
              square: _lastSquare, blocked: data['reason'] == 'blocked'));
        }
        final effect = data['finishEffect'];
        _enqueue(DraughtsCue(++_serial, 'finish',
            effect: draughtsFinishers.contains(effect)
                ? effect as String
                : 'royal'));
    }
  }

  void _enqueue(DraughtsCue cue) {
    // Long chains arrive as a burst. Keep the latest complete trail and count
    // rather than delaying the next turn behind every individual jump.
    if (cue.kind == 'capture' &&
        _queue.isNotEmpty &&
        _queue.last.kind == 'capture' &&
        _queue.last.chainId == cue.chainId) {
      final last = _queue.removeLast();
      if (last.king && !cue.king) {
        cue = DraughtsCue(cue.id, cue.kind,
            square: cue.square,
            victimSquare: last.victimSquare,
            trail: cue.trail,
            count: cue.count,
            chainId: cue.chainId,
            king: true);
      }
    }
    if (_queue.length >= 4) _queue.removeAt(0);
    _queue.add(cue);
    if (current == null) _next();
    notifyListeners();
  }

  void _next() {
    current = _queue.isEmpty ? null : _queue.removeAt(0);
    if (current == null) {
      _finishing = false;
      notifyListeners();
      return;
    }
    final ms = switch (current!.kind) {
      'finish' => 1400,
      'crown' => 700,
      'decisive' => 550,
      _ => 400
    };
    _advance = Timer(Duration(milliseconds: ms), _next);
    notifyListeners();
  }

  @override
  void dispose() {
    _advance?.cancel();
    super.dispose();
  }
}

class DraughtsEffectStage extends StatefulWidget {
  const DraughtsEffectStage(
      {super.key,
      required this.effects,
      required this.child,
      this.flipped = false,
      this.finishOnly = false,
      this.inset = 0,
      this.tray = 0});
  final DraughtsEffects effects;
  final Widget child;
  final bool flipped, finishOnly;
  final double inset, tray;
  @override
  State<DraughtsEffectStage> createState() => _DraughtsEffectStageState();
}

class _DraughtsEffectStageState extends State<DraughtsEffectStage>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400));
  int? _shown;
  @override
  void initState() {
    super.initState();
    widget.effects.addListener(_changed);
    _changed();
  }

  void _changed() {
    final cue = widget.effects.current;
    if (cue?.id != _shown) {
      _shown = cue?.id;
      _animation.duration = Duration(
          milliseconds: switch (cue?.kind) {
        'finish' => 1400,
        'crown' => 700,
        'decisive' => 550,
        _ => 400
      });
      _animation.forward(from: 0);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.effects.removeListener(_changed);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final cue = widget.effects.current;
        final show = cue != null && (cue.kind == 'finish') == widget.finishOnly;
        return Stack(fit: StackFit.expand, children: [
          widget.child,
          if (show)
            Positioned.fill(
                child: IgnorePointer(
                    child: CustomPaint(
              key: ValueKey('draughts-effect-${cue.kind}'),
              painter: _DraughtsPainter(
                  cue,
                  _animation.value,
                  MediaQuery.disableAnimationsOf(context),
                  widget.flipped,
                  widget.inset,
                  widget.tray),
            ))),
        ]);
      });
}

class _DraughtsPainter extends CustomPainter {
  _DraughtsPainter(
      this.cue, this.p, this.reduced, this.flipped, this.inset, this.tray);
  final DraughtsCue cue;
  final double p, inset, tray;
  final bool reduced, flipped;
  @override
  void paint(Canvas canvas, Size size) {
    final alpha = (1 - p * p).clamp(0.0, 1.0);
    const gold = Color(0xffffcf65);
    final color = switch (cue.effect) {
      'fire' => const Color(0xffff7548),
      'neon' => const Color(0xff6aeafa),
      _ => gold
    };
    final finish = cue.kind == 'finish';
    final boardSide = size.width;
    final cell = (boardSide - 2 * inset) / 10;
    Offset point(int sq) => Offset(inset + (colOf(sq) + .5) * cell,
        tray + inset + ((flipped ? rowOf(sq) : 9 - rowOf(sq)) + .5) * cell);
    final center = finish
        ? Offset(size.width / 2, size.height * .4)
        : cue.square == null
            ? Offset(size.width / 2, tray + boardSide / 2)
            : point(cue.square!);
    final stroke = Paint()
      ..color = color.withValues(alpha: alpha * .85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    if (!reduced) {
      if (cue.trail.length > 1) {
        final path = Path()
          ..moveTo(point(cue.trail.first).dx, point(cue.trail.first).dy);
        for (final square in cue.trail.skip(1)) {
          final at = point(square);
          path.lineTo(at.dx, at.dy);
        }
        canvas.drawPath(
            path, stroke..strokeWidth = math.min(6, 2 + cue.count).toDouble());
      }
      final radius =
          finish ? size.shortestSide * (.1 + .55 * p) : cell * (.45 + .35 * p);
      canvas.drawCircle(center, radius, stroke);
      if (cue.kind == 'crown' || (finish && cue.effect == 'royal')) {
        _crown(canvas, center.translate(0, -18 * (1 - p)),
            finish ? 68 : cell * .95, gold.withValues(alpha: alpha));
      }
      if (cue.king) {
        final victim =
            cue.victimSquare == null ? center : point(cue.victimSquare!);
        // The captured king's crown cracks where that king stood.
        for (final direction in [-1, 1]) {
          canvas.save();
          final at = victim.translate(direction * p * cell * .6, p * cell * .3);
          canvas.clipRect(Rect.fromLTWH(at.dx + (direction < 0 ? -cell : 0),
              at.dy - cell, cell, cell * 2));
          _crown(canvas, at, cell, gold.withValues(alpha: alpha));
          canvas.restore();
        }
      }
      if (cue.kind == 'seize') {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: center, width: cell * 1.1, height: cell * 1.1),
                const Radius.circular(7)),
            stroke);
      }
      if (finish) {
        for (var i = 0; i < 24; i++) {
          final angle = i * math.pi * 2 / 24;
          final travel = size.shortestSide * (.08 + .55 * p);
          final at = center + Offset(math.cos(angle), math.sin(angle)) * travel;
          if (cue.effect == 'thunder') {
            final path = Path()
              ..moveTo(at.dx - 4, at.dy - 12)
              ..lineTo(at.dx + 3, at.dy)
              ..lineTo(at.dx - 2, at.dy + 3)
              ..lineTo(at.dx + 5, at.dy + 14);
            canvas.drawPath(path, stroke);
          } else if (cue.effect == 'confetti') {
            canvas.drawRect(
                Rect.fromCenter(center: at, width: 5, height: 10),
                Paint()
                  ..color = Colors.primaries[i % Colors.primaries.length]
                      .withValues(alpha: alpha));
          } else if (cue.effect == 'fire') {
            canvas.drawOval(
                Rect.fromCenter(center: at, width: 5 + 8 * (1 - p), height: 15),
                Paint()..color = color.withValues(alpha: alpha));
          } else {
            canvas.drawCircle(at, cue.effect == 'neon' ? 3 : 2,
                Paint()..color = color.withValues(alpha: alpha));
          }
        }
      }
    }
    if (cue.title.isNotEmpty) {
      final at =
          finish ? center.translate(0, 58) : Offset(size.width / 2, tray + 20);
      _text(canvas, cue.title, at, finish ? 28 : 17,
          gold.withValues(alpha: alpha));
    }
  }

  void _crown(Canvas canvas, Offset center, double size, Color color) {
    final path = Path()
      ..moveTo(-.42, -.26)
      ..lineTo(-.22, -.06)
      ..lineTo(0, -.4)
      ..lineTo(.22, -.06)
      ..lineTo(.42, -.26)
      ..lineTo(.32, .25)
      ..lineTo(-.32, .25)
      ..close();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(size);
    canvas.drawPath(path,
        Paint()..color = const Color(0xff38220c).withValues(alpha: color.a));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = .06);
    canvas.drawLine(
        const Offset(-.3, .34),
        const Offset(.3, .34),
        Paint()
          ..color = color
          ..strokeWidth = .07);
    canvas.restore();
  }

  void _text(Canvas canvas, String value, Offset at, double size, Color color) {
    final text = TextPainter(
        text: TextSpan(
            text: value,
            style: TextStyle(
                fontSize: size,
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w900,
                color: color,
                shadows: const [Shadow(color: Colors.black, blurRadius: 5)])),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center)
      ..layout();
    text.paint(canvas, at - Offset(text.width / 2, text.height / 2));
  }

  @override
  bool shouldRepaint(covariant _DraughtsPainter old) =>
      old.p != p ||
      old.cue.id != cue.id ||
      old.reduced != reduced ||
      old.flipped != flipped;
}
