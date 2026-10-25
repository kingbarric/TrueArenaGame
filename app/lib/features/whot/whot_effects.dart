import 'dart:math' as math;
import 'package:flutter/material.dart';

const whotFinishers = <String, String>{
  'classic': 'Final Slam',
  'thunder': 'Thunder Slam',
  'fire': 'Fire Burst',
  'neon': 'Neon Shockwave',
  'royal': 'Royal Spotlight',
  'confetti': 'Confetti Storm',
};
const whotReactions = ['👏', '🔥', '😂', '😮', '💔', '🎉'];

String whotMomentTitle(Map<String, dynamic> moment) {
  final debt = (moment['debt'] as num?)?.toInt() ?? 0;
  return switch (moment['kind']) {
    'pickTwo' => (moment['pendingBefore'] as num? ?? 0) > 0
        ? (moment['returned'] == true ? 'RETURNED! +$debt' : 'STACKED! +$debt')
        : 'PICK TWO! +$debt',
    'market' => 'TO MARKET! +${moment['count']}',
    'generalMarket' => 'EVERYBODY TO MARKET!',
    'holdOn' => 'STILL MY TURN',
    'skip' => 'TURN SKIPPED',
    'wild' => '${moment['shape'] ?? 'NEW SHAPE'}'.toUpperCase(),
    'finish' => 'FINAL CARD!',
    'qualified' => 'TEAM QUALIFIED',
    'stolen' => 'STOLEN!',
    'buzz' => 'CORRECT BUZZ!',
    'eliminated' => 'TEAM ELIMINATED',
    _ => '${moment['card'] ?? 'Market · ${moment['count'] ?? 1}'}'
        .replaceAll('-', ' '),
  };
}

/// Cosmetic only: never consumes input or changes a game clock.
class WhotEffectStage extends StatefulWidget {
  const WhotEffectStage(
      {super.key,
      required this.child,
      required this.moment,
      required this.seats,
      required this.reduced});
  final Widget child;
  final Map<String, dynamic>? moment;
  final Map<String, Offset> seats;
  final bool reduced;
  @override
  State<WhotEffectStage> createState() => _WhotEffectStageState();
}

class _WhotEffectStageState extends State<WhotEffectStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    if (widget.moment == null) return;
    _animation.duration = Duration(
        milliseconds: widget.reduced
            ? 650
            : widget.moment!['kind'] == 'finish'
                ? 1200
                : 900);
    _animation.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant WhotEffectStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moment?['id'] != widget.moment?['id']) _start();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          final p = _animation.value;
          final moment = widget.moment;
          final active = moment != null && p < 1;
          final shake = active &&
                  !widget.reduced &&
                  moment['effect'] == 'thunder' &&
                  moment['kind'] == 'finish'
              ? math.sin(p * 65) * 3 * (1 - p)
              : 0.0;
          return ClipRect(
              child: Stack(fit: StackFit.expand, children: [
            Transform.translate(offset: Offset(shake, 0), child: widget.child),
            if (active)
              Positioned.fill(
                  child: IgnorePointer(
                      child: CustomPaint(
                key: ValueKey('whot-effect-${moment['kind']}'),
                painter:
                    _WhotEffectPainter(moment, widget.seats, p, widget.reduced),
              ))),
          ]));
        },
      );
}

class _WhotEffectPainter extends CustomPainter {
  _WhotEffectPainter(this.moment, this.seats, this.progress, this.reduced);
  final Map<String, dynamic> moment;
  final Map<String, Offset> seats;
  final double progress;
  final bool reduced;
  static const gold = Color(0xffffd270);

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress;
    final fade = (1 - math.pow(p, 3)).toDouble().clamp(0.0, 1.0);
    final kind = moment['kind'];
    final preset = moment['effect'];
    final finish = kind == 'finish' || kind == 'qualified';
    final color = kind == 'wild'
        ? switch (moment['shape']) {
            'circle' => const Color(0xffff7087),
            'triangle' => const Color(0xff6ef5a2),
            'cross' => const Color(0xff65c8ff),
            'square' => const Color(0xffd19aff),
            _ => gold
          }
        : kind == 'pickTwo' || preset == 'fire'
            ? const Color(0xffff6547)
            : preset == 'neon' || kind == 'wild'
                ? const Color(0xff64e9ff)
                : gold;
    Offset seat(Object? id) {
      final point = seats[id] ?? const Offset(.5, .45);
      return Offset(point.dx * size.width, point.dy * size.height);
    }

    final center = Offset(size.width * .5, size.height * .43);
    if (!reduced) {
      final stroke = Paint()
        ..color = color.withValues(alpha: .8 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      if (kind == 'pickTwo' || kind == 'skip') {
        final from = seat(moment['by']), to = seat(moment['target']);
        final control = Offset(size.width * .5, size.height * .2);
        final path = Path()
          ..moveTo(from.dx, from.dy)
          ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);
        canvas.drawPath(
            path,
            stroke
              ..strokeWidth =
                  2 + math.min(6.0, (moment['debt'] as num? ?? 0) / 2));
        final t = Curves.easeInOut.transform(p.clamp(0, 1));
        final point = from * ((1 - t) * (1 - t)) +
            control * (2 * (1 - t) * t) +
            to * (t * t);
        canvas.drawCircle(point, 9 + 6 * math.sin(p * math.pi),
            Paint()..color = color.withValues(alpha: fade));
        if (kind == 'skip') {
          _text(canvas, '⊘', seat(moment['skipped']), 28,
              gold.withValues(alpha: fade));
        }
        if (kind == 'pickTwo') {
          _text(canvas, '+${moment['debt']}', to.translate(0, -22), 23,
              color.withValues(alpha: fade));
        }
      }
      if (kind == 'generalMarket' ||
          kind == 'wild' ||
          finish ||
          kind == 'stolen') {
        for (var ring = 0; ring < 3; ring++) {
          final radius = (p + ring * .16) * size.shortestSide * .8;
          canvas.drawCircle(
              center,
              radius,
              stroke
                ..strokeWidth = 2
                ..color = color.withValues(alpha: fade * .45));
        }
      }
      if (kind == 'holdOn') {
        canvas.drawArc(Rect.fromCircle(center: seat(moment['by']), radius: 29),
            -math.pi / 2, math.pi * 2 * p, false, stroke);
      }
      if (kind == 'market') {
        for (var i = 0;
            i < math.min(6, (moment['count'] as num? ?? 1).toInt());
            i++) {
          final t = ((p - i * .06) / .65).clamp(0.0, 1.0);
          final point = Offset.lerp(center, seat(moment['by']), t)!;
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: point, width: 16, height: 23),
                  const Radius.circular(3)),
              Paint()..color = gold.withValues(alpha: fade));
        }
      }
      if (moment['teamMembers'] is List &&
          (finish || kind == 'buzz' || kind == 'stolen')) {
        for (final player in moment['teamMembers']) {
          canvas.drawCircle(seat(player), 32 + 6 * p,
              stroke..color = gold.withValues(alpha: fade));
        }
      }
      if (kind == 'market' && moment['stacker'] != null) {
        canvas.drawCircle(seat(moment['stacker']), 34, stroke);
      }
      if (kind == 'wild') {
        canvas.drawRect(Offset.zero & size,
            Paint()..color = color.withValues(alpha: .15 * fade));
      }
      if (finish) {
        final random = math.Random('${moment['id']}'.hashCode);
        for (var i = 0; i < 30; i++) {
          final angle = random.nextDouble() * math.pi * 2;
          final radius = (30 + random.nextDouble() * size.shortestSide * .6) *
              Curves.easeOut.transform(p);
          final point =
              center + Offset(math.cos(angle), math.sin(angle)) * radius;
          final particle = preset == 'confetti'
              ? Colors.primaries[i % Colors.primaries.length]
              : color;
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(
                      center: point,
                      width: 4 + i % 4,
                      height: preset == 'fire' ? 13 : 5),
                  const Radius.circular(2)),
              Paint()..color = particle.withValues(alpha: fade));
        }
        if (preset == 'thunder') {
          for (var i = 0; i < 3; i++) {
            final x = size.width * (.2 + i * .3);
            canvas.drawPath(
                Path()
                  ..moveTo(x, size.height * .12)
                  ..lineTo(x - 15, size.height * .3)
                  ..lineTo(x + 8, size.height * .28)
                  ..lineTo(x - 7, size.height * .49),
                Paint()
                  ..color = gold.withValues(alpha: fade)
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 4);
          }
        }
        if (preset == 'royal') {
          canvas.drawPath(
              Path()
                ..moveTo(size.width * .5, 0)
                ..lineTo(size.width * .16, size.height * .65)
                ..lineTo(size.width * .84, size.height * .65)
                ..close(),
              Paint()..color = gold.withValues(alpha: fade * .13));
        }
        if (preset == 'royal') {
          _text(canvas, '♛', center.translate(0, -65), 58,
              gold.withValues(alpha: fade));
        }
      }
    }
    if (moment['showLabel'] == false) return;
    final labelAt = Offset(size.width * .5, size.height * (finish ? .25 : .16));
    final title = whotMomentTitle(moment);
    final painter = TextPainter(
        text: TextSpan(
            text: title,
            style: TextStyle(
                fontFamily: 'Archivo',
                color: color.withValues(alpha: fade),
                fontSize: finish ? 24 : 17,
                fontWeight: FontWeight.w900,
                letterSpacing: .8)),
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: math.max(1, size.width - 22));
    final rect = Rect.fromCenter(
        center: labelAt,
        width: painter.width + 20,
        height: painter.height + 16);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        Paint()..color = const Color(0xff21112a).withValues(alpha: fade * .94));
    painter.paint(
        canvas, labelAt - Offset(painter.width / 2, painter.height / 2));
    if ((moment['debt'] as num? ?? 0) >= 6) {
      _text(canvas, "WHO'S TAKING IT?", labelAt.translate(0, 33), 11,
          gold.withValues(alpha: fade));
    }
  }

  void _text(Canvas canvas, String text, Offset at, double size, Color color) {
    final p = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                fontFamily: 'Archivo',
                color: color,
                fontSize: size,
                fontWeight: FontWeight.w900)),
        textDirection: TextDirection.ltr)
      ..layout();
    p.paint(canvas, at - Offset(p.width / 2, p.height / 2));
  }

  @override
  bool shouldRepaint(covariant _WhotEffectPainter oldDelegate) => true;
}

/// A dedicated lane OUTSIDE the board. Clips prevent emoji drifting onto cards.
class WhotReactionLane extends StatelessWidget {
  const WhotReactionLane(
      {super.key,
      required this.reactions,
      required this.side,
      required this.reduced});
  final List<Map<String, dynamic>> reactions;
  final int side;
  final bool reduced;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 24,
      child: ClipRect(
          child: IgnorePointer(
        child: LayoutBuilder(
            builder: (context, box) => Stack(children: [
                  for (final reaction
                      in reactions.where((r) => r['lane'] == side))
                    TweenAnimationBuilder<double>(
                      key: ValueKey('reaction-${reaction['id']}'),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 2200),
                      builder: (context, p, child) => Positioned(
                          left: 1,
                          top: reduced
                              ? box.maxHeight * .5
                              : box.maxHeight * (.85 - .65 * p),
                          child: Opacity(
                              opacity: (1 - p).clamp(0.0, 1.0), child: child)),
                      child: SizedBox(
                          width: 22,
                          height: 26,
                          child: FittedBox(
                              child: Text('${reaction['emoji']}',
                                  style: const TextStyle(fontSize: 20)))),
                    ),
                ])),
      )));
}
