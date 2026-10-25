import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/game_sfx.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/huud_art.dart';
import 'table_ring.dart';

/// Someone leaving the table, and — when the rules show it — what they were.
class RevealSubject {
  const RevealSubject({required this.id, required this.name, this.role});
  final String id;
  final String name;

  /// "traitor", "recruited_traitor" or "faithful"; null when it stays hidden.
  final String? role;

  bool get traitor => role == 'traitor' || role == 'recruited_traitor';
}

enum _Stage { drumroll, name, role, nobody, waiting }

/// The morning (or the banishment) told at the round table: a spotlight
/// runs round the seats for a few seconds and stops on whoever's gone; their
/// name comes up in the middle; a few seconds later, what they were — a
/// Traitor caught is a celebration, a Faithful lost is a sad moment.
class EliminationReveal extends StatefulWidget {
  const EliminationReveal({
    super.key,
    required this.players,
    required this.subjects,
    required this.nobody,
    required this.heading,
    required this.seat,
    this.onDone,
    this.nameSeconds = 5,
    this.roleSeconds = 3,
  });

  final List<String> players;
  final List<RevealSubject> subjects;

  /// Nobody left the table this time (no murder, no banishment).
  final bool nobody;

  /// "Who was taken in the night?" / "The table has spoken…"
  final String heading;
  final Widget Function(String id, double size, bool spotlight) seat;

  /// Everything's been shown.
  final VoidCallback? onDone;
  final int nameSeconds, roleSeconds;

  @override
  State<EliminationReveal> createState() => _EliminationRevealState();
}

class _EliminationRevealState extends State<EliminationReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _fx =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  _Stage _stage = _Stage.drumroll;
  int _index = 0;
  late int _count = widget.nameSeconds;
  int _spot = 0;
  Timer? _tick, _spin, _hold;

  RevealSubject? get _subject => _index < widget.subjects.length ? widget.subjects[_index] : null;

  @override
  void initState() {
    super.initState();
    _drumroll();
  }

  @override
  void didUpdateWidget(covariant EliminationReveal old) {
    super.didUpdateWidget(old);
    // The news arrived after the drumroll finished: carry on with it.
    if (_stage == _Stage.waiting && (_subject != null || widget.nobody)) _afterDrumroll();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _spin?.cancel();
    _hold?.cancel();
    _fx.dispose();
    super.dispose();
  }

  void _drumroll() {
    _stage = _Stage.drumroll;
    _count = widget.nameSeconds;
    _spin?.cancel();
    if (widget.players.isNotEmpty) {
      _spin = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (mounted) setState(() => _spot = (_spot + 1) % widget.players.length);
      });
    }
    _countdown(widget.nameSeconds, _afterDrumroll);
  }

  void _countdown(int seconds, VoidCallback then) {
    _tick?.cancel();
    // Callers rebuild (or are building); this just sets the starting number.
    _count = seconds;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_count <= 1) {
        t.cancel();
        then();
        return;
      }
      GameSfx.select();
      setState(() => _count--);
    });
  }

  void setStateSafe(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  void _afterDrumroll() {
    _spin?.cancel();
    final subject = _subject;
    if (subject == null) {
      setStateSafe(() => _stage = widget.nobody ? _Stage.nobody : _Stage.waiting);
      if (widget.nobody) _finish();
      return;
    }
    GameSfx.capture();
    setStateSafe(() => _stage = _Stage.name);
    _countdown(widget.roleSeconds, _showRole);
  }

  void _showRole() {
    final subject = _subject;
    if (subject == null) return;
    subject.traitor ? GameSfx.king() : GameSfx.captured();
    setStateSafe(() => _stage = _Stage.role);
    _fx.forward(from: 0);
    _hold = Timer(const Duration(milliseconds: 3200), () {
      if (!mounted) return;
      if (_index + 1 < widget.subjects.length) {
        setState(() => _index++);
        _drumroll();
      } else {
        _finish();
      }
    });
  }

  void _finish() => widget.onDone?.call();

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final subject = _subject;
    final showing = _stage == _Stage.name || _stage == _Stage.role ? subject?.id : null;
    final spotlit = showing ?? (_stage == _Stage.drumroll && widget.players.isNotEmpty ? widget.players[_spot] : null);
    final mood = _stage == _Stage.role && subject?.role != null ? (subject!.traitor ? _Mood.joy : _Mood.grief) : _Mood.none;
    return Stack(fit: StackFit.expand, children: [
      // A Faithful lost: the table goes dark around them.
      AnimatedOpacity(
        opacity: mood == _Mood.grief ? 1 : 0,
        duration: const Duration(milliseconds: 900),
        child: const ColoredBox(color: Color(0x660B1220)),
      ),
      TableRing(
        players: widget.players,
        tableTint: switch (mood) {
          _Mood.joy => const Color(0xff5a3a10),
          _Mood.grief => const Color(0xff1c2433),
          _Mood.none => null,
        },
        seat: (id, size) => widget.seat(id, size, id == spotlit),
        centre: (width) => SizedBox(width: math.max(width, 170), child: _centre(n, subject)),
      ),
      if (mood != _Mood.none)
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _fx,
            builder: (_, __) => CustomPaint(
              painter: mood == _Mood.joy
                  ? _ConfettiPainter(_fx.value, seed: subject.hashCode)
                  : _TearsPainter(_fx.value, seed: subject.hashCode),
            ),
          ),
        ),
    ]);
  }

  Widget _centre(NeonColors n, RevealSubject? subject) {
    final theme = Theme.of(context).textTheme;
    Widget big(String text, Color color, {double size = 46}) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          transitionBuilder: (child, a) => ScaleTransition(scale: Tween(begin: 1.6, end: 1.0).animate(a), child: child),
          child: Text(text,
              key: ValueKey(text),
              style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: color, height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        );
    return switch (_stage) {
      _Stage.drumroll => Column(key: const ValueKey('reveal-drumroll'), mainAxisSize: MainAxisSize.min, children: [
          Text(widget.heading, textAlign: TextAlign.center, style: theme.bodyMedium?.copyWith(color: n.mid)),
          const SizedBox(height: 8),
          KeyedSubtree(key: const ValueKey('reveal-count'), child: big('$_count', n.gold)),
        ]),
      _Stage.waiting => Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.heading, textAlign: TextAlign.center, style: theme.bodyMedium?.copyWith(color: n.mid)),
          const SizedBox(height: 8),
          big('…', n.gold),
        ]),
      _Stage.nobody => Column(key: const ValueKey('reveal-nobody'), mainAxisSize: MainAxisSize.min, children: [
          const HuudText('🌅', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 6),
          Text('Nobody left the table',
              textAlign: TextAlign.center, style: theme.displayLarge?.copyWith(fontSize: 22, color: n.jade)),
          const SizedBox(height: 4),
          Text('Everyone made it through.', style: theme.bodyMedium?.copyWith(color: n.mid)),
        ]),
      _Stage.name => Column(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.4, end: 1),
            duration: const Duration(milliseconds: 520),
            curve: Curves.elasticOut,
            builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
            child: Text(subject?.name ?? '',
                key: const ValueKey('reveal-name'),
                textAlign: TextAlign.center,
                style: theme.displayLarge?.copyWith(fontSize: 30, color: n.ink)),
          ),
          const SizedBox(height: 4),
          Text('was…', style: theme.bodyMedium?.copyWith(color: n.mid)),
          const SizedBox(height: 6),
          KeyedSubtree(key: const ValueKey('reveal-count'), child: big('$_count', n.gold, size: 34)),
        ]),
      _Stage.role => _role(n, subject!),
    };
  }

  Widget _role(NeonColors n, RevealSubject subject) {
    final theme = Theme.of(context).textTheme;
    final (emoji, title, line, color) = subject.role == null
        ? ('🎭', 'Their role stays hidden', 'The table will have to keep guessing.', n.mid)
        : subject.traitor
            ? ('🎉', 'A TRAITOR!', 'One less Traitor at the table.', n.gold)
            : ('💔', 'FAITHFUL', 'An innocent soul is gone.', const Color(0xff8fa6c8));
    return TweenAnimationBuilder<double>(
      key: const ValueKey('reveal-role'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: subject.traitor ? Curves.elasticOut : Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.scale(scale: subject.traitor ? 0.5 + 0.5 * t : 1, child: child),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(subject.name, textAlign: TextAlign.center, style: theme.bodyMedium?.copyWith(color: n.mid)),
        const SizedBox(height: 4),
        HuudText(emoji, style: const TextStyle(fontSize: 36)),
        const SizedBox(height: 4),
        Text(title,
            textAlign: TextAlign.center,
            style: theme.displayLarge?.copyWith(fontSize: 28, color: color, letterSpacing: 1.2)),
        const SizedBox(height: 4),
        Text(line, textAlign: TextAlign.center, style: theme.bodyMedium?.copyWith(color: n.mid)),
      ]),
    );
  }
}

enum _Mood { none, joy, grief }

/// A burst of gold, red and green paper from the middle of the table.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, {required this.seed});
  final double t;
  final int seed;

  static const _colors = [Color(0xffffc94a), Color(0xffff6b4a), Color(0xff4ade80), Color(0xfff6eae3), Color(0xffc02b52)];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final centre = Offset(size.width / 2, size.height / 2);
    final fade = (1 - t).clamp(0.0, 1.0);
    for (var i = 0; i < 70; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final speed = 180 + rng.nextDouble() * 260;
      final spin = rng.nextDouble() * 10;
      final p = centre +
          Offset(math.cos(angle) * speed * t, math.sin(angle) * speed * t - 120 * t + 260 * t * t);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(spin * t * 6);
      canvas.drawRect(const Rect.fromLTWH(-4, -2, 8, 4),
          Paint()..color = _colors[i % _colors.length].withValues(alpha: fade));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

/// Slow, falling tears across the table.
class _TearsPainter extends CustomPainter {
  _TearsPainter(this.t, {required this.seed});
  final double t;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    for (var i = 0; i < 34; i++) {
      final x = rng.nextDouble() * size.width;
      final start = -rng.nextDouble() * size.height * 0.4;
      final fall = size.height * (0.5 + rng.nextDouble() * 0.6);
      final y = start + fall * t;
      final alpha = (0.55 * math.sin(math.pi * t)).clamp(0.0, 1.0);
      final paint = Paint()..color = const Color(0xff9ec3ff).withValues(alpha: alpha);
      final drop = Path()
        ..moveTo(x, y - 7)
        ..quadraticBezierTo(x + 4, y, x, y + 4)
        ..quadraticBezierTo(x - 4, y, x, y - 7);
      canvas.drawPath(drop, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TearsPainter old) => old.t != t;
}
