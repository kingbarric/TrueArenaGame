import 'dart:math' as math;
import 'package:flutter/material.dart';

const monopolyCream = Color(0xfffff1d8);
const monopolyInk = Color(0xff29170f);
const monopolyGold = Color(0xffe8bb68);
const monopolyWine = Color(0xff922d40);
const monopolySeatColors = <Color>[
  Color(0xffc33e51),
  Color(0xff327dba),
  Color(0xffd9a329),
  Color(0xff3c9e73),
  Color(0xffed7a32),
  Color(0xffdb709c),
  Color(0xff389b9e),
  Color(0xff76685c),
];
Color monopolyGroupColor(String? group) =>
    const {
      'brown': Color(0xff895137),
      'lightBlue': Color(0xff84c5d9),
      'pink': Color(0xffd74d95),
      'orange': Color(0xffed8d22),
      'red': Color(0xffd43d37),
      'yellow': Color(0xffefd22e),
      'green': Color(0xff248b65),
      'darkBlue': Color(0xff215994),
    }[group] ??
    monopolyGold;

Map<String, dynamic> monopolyMap(dynamic value) =>
    value is Map ? value.cast<String, dynamic>() : {};
List<String> monopolyPlayers(Map<String, dynamic> state) =>
    (state['players'] as List? ?? []).map((e) => e.toString()).toList();

/// Coordinates include all forty spaces, with larger corner tiles. The same
/// geometry drives painting, pointer hit testing and zoomed inspection.
Rect monopolySpaceRect(int id, double size) {
  final inset = size * .018, edge = size - 2 * inset;
  final unit = edge / 14, corner = unit * 2.5;
  final right = size - inset, bottom = size - inset;
  if (id == 0) {
    return Rect.fromLTWH(right - corner, bottom - corner, corner, corner);
  }
  if (id == 10) return Rect.fromLTWH(inset, bottom - corner, corner, corner);
  if (id == 20) return Rect.fromLTWH(inset, inset, corner, corner);
  if (id == 30) return Rect.fromLTWH(right - corner, inset, corner, corner);
  if (id < 10) {
    return Rect.fromLTWH(
        right - corner - id * unit, bottom - corner, unit, corner);
  }
  if (id < 20) {
    return Rect.fromLTWH(
        inset, bottom - corner - (id - 10) * unit, corner, unit);
  }
  if (id < 30) {
    return Rect.fromLTWH(
        inset + corner + (id - 21) * unit, inset, unit, corner);
  }
  return Rect.fromLTWH(
      right - corner, inset + corner + (id - 31) * unit, corner, unit);
}

class MonopolyBoard extends StatefulWidget {
  const MonopolyBoard(
      {super.key, required this.state, required this.onSpace, this.selected});
  final Map<String, dynamic> state;
  final ValueChanged<int> onSpace;
  final int? selected;
  @override
  State<MonopolyBoard> createState() => _MonopolyBoardState();
}

class _MonopolyBoardState extends State<MonopolyBoard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 850))
    ..value = 1;
  Map<String, dynamic> _previous = {};
  @override
  void didUpdateWidget(covariant MonopolyBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state['playerState'].toString() !=
        widget.state['playerState'].toString()) {
      _previous = oldWidget.state;
      if (MediaQuery.disableAnimationsOf(context)) {
        _motion.value = 1;
      } else {
        _motion.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1,
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 3,
          boundaryMargin: const EdgeInsets.all(24),
          child: LayoutBuilder(
              builder: (_, constraints) => GestureDetector(
                    onTapUp: (details) {
                      for (int i = 0; i < 40; i++) {
                        if (monopolySpaceRect(i, constraints.maxWidth)
                            .contains(details.localPosition)) {
                          widget.onSpace(i);
                          return;
                        }
                      }
                    },
                    child: AnimatedBuilder(
                        animation: _motion,
                        builder: (_, __) => Container(
                              decoration: BoxDecoration(
                                image: const DecorationImage(
                                    image: AssetImage(
                                        'assets/images/monopoly/walnut.png'),
                                    fit: BoxFit.cover),
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0xb0000000),
                                      blurRadius: 12,
                                      offset: Offset(0, 9))
                                ],
                              ),
                              child: CustomPaint(
                                  painter: _BoardPainter(
                                      widget.state,
                                      _previous,
                                      _motion.value,
                                      widget.selected),
                                  size: Size.square(constraints.maxWidth)),
                            )),
                  )),
        ),
      );
}

class MonopolyToken extends StatelessWidget {
  const MonopolyToken({super.key, required this.seat, this.size = 32});
  final int seat;
  final double size;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _TokenPainter(seat));
}

class _TokenPainter extends CustomPainter {
  const _TokenPainter(this.seat);
  final int seat;
  @override
  void paint(Canvas canvas, Size size) {
    _metalToken(canvas, size.center(Offset.zero), size.width, seat);
  }

  @override
  bool shouldRepaint(_TokenPainter old) => old.seat != seat;
}

void _metalToken(Canvas canvas, Offset center, double size, int seat) {
  canvas.save();
  canvas.translate(center.dx - size / 2, center.dy - size / 2);
  canvas.scale(size / 100);
  canvas.drawOval(
      const Rect.fromLTWH(6, 70, 90, 22),
      Paint()
        ..color = const Color(0x70000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
  canvas.drawOval(const Rect.fromLTWH(10, 70, 80, 18),
      Paint()..color = monopolySeatColors[seat % 8]);
  canvas.drawOval(
      const Rect.fromLTWH(10, 70, 80, 18),
      Paint()
        ..color = const Color(0xffffdeb0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
  final path = Path();
  switch (seat % 8) {
    case 0: // Motor car: wide body, bonnet, cabin and distinct wheels.
      path.moveTo(10, 54);
      path.lineTo(25, 45);
      path.lineTo(34, 28);
      path.lineTo(62, 28);
      path.lineTo(75, 45);
      path.lineTo(88, 50);
      path.lineTo(90, 68);
      path.lineTo(10, 68);
      path.close();
      path.addOval(const Rect.fromLTWH(17, 60, 20, 20));
      path.addOval(const Rect.fromLTWH(65, 60, 20, 20));
    case 1: // Top hat.
      path.addOval(const Rect.fromLTWH(9, 59, 82, 23));
      path.addRRect(RRect.fromRectAndRadius(
          const Rect.fromLTWH(27, 18, 46, 53), const Radius.circular(5)));
      path.addOval(const Rect.fromLTWH(27, 13, 46, 15));
    case 2: // Terrier.
      path.moveTo(12, 44);
      path.lineTo(27, 51);
      path.lineTo(57, 48);
      path.lineTo(61, 25);
      path.lineTo(70, 18);
      path.lineTo(78, 28);
      path.lineTo(91, 33);
      path.lineTo(89, 43);
      path.lineTo(77, 46);
      path.lineTo(75, 77);
      path.lineTo(63, 77);
      path.lineTo(60, 60);
      path.lineTo(38, 62);
      path.lineTo(32, 77);
      path.lineTo(20, 77);
      path.lineTo(24, 57);
      path.close();
    case 3: // Ship.
      path.moveTo(8, 57);
      path.lineTo(92, 57);
      path.lineTo(75, 78);
      path.lineTo(26, 78);
      path.close();
      path.addRect(const Rect.fromLTWH(46, 17, 6, 43));
      path.moveTo(56, 18);
      path.lineTo(84, 49);
      path.lineTo(56, 49);
      path.close();
      path.moveTo(42, 26);
      path.lineTo(18, 49);
      path.lineTo(42, 49);
      path.close();
    case 4: // Boot.
      path.moveTo(33, 17);
      path.lineTo(62, 17);
      path.lineTo(62, 56);
      path.lineTo(83, 62);
      path.quadraticBezierTo(99, 78, 76, 80);
      path.lineTo(24, 80);
      path.lineTo(22, 65);
      path.lineTo(33, 52);
      path.close();
    case 5: // Wheelbarrow.
      path.moveTo(15, 31);
      path.lineTo(73, 31);
      path.lineTo(62, 56);
      path.lineTo(30, 56);
      path.close();
      path.addRect(const Rect.fromLTWH(61, 21, 30, 6));
      path.addRect(const Rect.fromLTWH(36, 52, 7, 24));
      path.addOval(const Rect.fromLTWH(10, 60, 27, 27));
    case 6: // Cat.
      path.addOval(const Rect.fromLTWH(33, 41, 36, 41));
      path.moveTo(31, 22);
      path.lineTo(45, 32);
      path.lineTo(57, 32);
      path.lineTo(71, 22);
      path.lineTo(66, 50);
      path.quadraticBezierTo(51, 66, 36, 50);
      path.close();
      path.moveTo(67, 68);
      path.cubicTo(92, 65, 88, 45, 83, 43);
      path.lineTo(79, 44);
      path.cubicTo(90, 64, 77, 71, 67, 71);
      path.close();
    default: // Thimble.
      path.moveTo(26, 75);
      path.lineTo(33, 21);
      path.quadraticBezierTo(50, 8, 68, 21);
      path.lineTo(77, 75);
      path.close();
      path.addOval(const Rect.fromLTWH(23, 67, 57, 16));
  }
  canvas.drawShadow(path, const Color(0xff000000), 4, false);
  const bounds = Rect.fromLTWH(10, 10, 80, 75);
  canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xfffbf8e5),
              Color(0xffafb8b7),
              Color(0xff526165),
              Color(0xffe3e4d8),
              Color(0xff778386)
            ],
            stops: [
              0,
              .28,
              .55,
              .72,
              1
            ]).createShader(bounds));
  canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = const Color(0xff293d3f));
  canvas.restore();
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.state, this.previous, this.motion, this.selected);
  final Map<String, dynamic> state, previous;
  final double motion;
  final int? selected;
  void text(Canvas c, String value, Rect area,
      {double? font,
      Color color = monopolyInk,
      int lines = 3,
      FontWeight weight = FontWeight.w900,
      bool fitWords = false}) {
    var fontSize = font ?? area.width * .17;
    if (fitWords) {
      // Balance long street names and keep short labels such as Chance intact.
      value = value.replaceAllMapped(RegExp(r'\S+'), (match) {
        final word = match.group(0)!;
        if (word.length <= 7) return word;
        final count = (word.length / 6).ceil();
        final length = (word.length / count).ceil();
        return [
          for (int i = 0; i < word.length; i += length)
            word.substring(i, math.min(i + length, word.length))
        ].join('\n');
      });
      final measure = TextPainter(textDirection: TextDirection.ltr);
      var widest = 0.0;
      for (final word in value.split(RegExp(r'\s+'))) {
        measure.text = TextSpan(
            text: word,
            style: TextStyle(
                fontFamily: 'MonopolySans',
                fontSize: fontSize,
                fontWeight: weight));
        measure.layout();
        widest = math.max(widest, measure.width);
      }
      if (widest > area.width) fontSize *= area.width / widest;
      measure.dispose();
    }
    final tp = TextPainter(
        text: TextSpan(
            text: value,
            style: TextStyle(
                color: color,
                fontFamily: 'MonopolySans',
                fontSize: fontSize,
                fontWeight: weight,
                height: 1.05)),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: lines,
        ellipsis: '…')
      ..layout(maxWidth: area.width);
    tp.paint(c,
        Offset(area.center.dx - tp.width / 2, area.center.dy - tp.height / 2));
  }

  @override
  void paint(Canvas c, Size size) {
    final w = size.width;
    final edge = Rect.fromLTWH(w * .006, w * .006, w * .988, w * .988);
    c.drawRRect(
        RRect.fromRectAndRadius(
            edge.translate(0, w * .01), Radius.circular(w * .025)),
        Paint()..color = const Color(0xff39251c));
    c.drawRRect(
        RRect.fromRectAndRadius(edge, Radius.circular(w * .025)),
        Paint()
          ..shader = const LinearGradient(colors: [
            Color(0xffe8cf89),
            Color(0xff9b7132),
            Color(0xfff5dba0)
          ], begin: Alignment.topLeft, end: Alignment.bottomRight)
              .createShader(edge));
    final center = Rect.fromLTRB(
        monopolySpaceRect(20, w).right,
        monopolySpaceRect(20, w).bottom,
        monopolySpaceRect(0, w).left,
        monopolySpaceRect(0, w).top);
    c.drawRect(
        center,
        Paint()
          ..shader = const RadialGradient(
                  colors: [Color(0xff3b785d), Color(0xff174b39)], radius: .9)
              .createShader(center));
    // Fine felt flecks have a fixed seed: visual texture never changes a roll.
    final rng = math.Random(7);
    for (int i = 0; i < 850; i++) {
      c.drawCircle(
          Offset(center.left + rng.nextDouble() * center.width,
              center.top + rng.nextDouble() * center.height),
          w * .0006,
          Paint()..color = const Color(0x18ffffff));
    }
    c.drawRect(
        center.deflate(w * .011),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .003
          ..color = const Color(0xffbfa374));
    final board = state['board'] as List? ?? [];
    final deeds = monopolyMap(state['deeds']);
    final players = monopolyPlayers(state);
    for (int id = 0; id < 40; id++) {
      final rect = monopolySpaceRect(id, w).deflate(w * .0015);
      c.drawRect(rect.translate(w * .0018, w * .004),
          Paint()..color = const Color(0xff866e50));
      c.drawRect(
          rect,
          Paint()
            ..shader = const LinearGradient(
                    colors: [Color(0xfffff5df), Color(0xffe7d5b5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight)
                .createShader(rect));
      c.drawRect(
          rect,
          Paint()
            ..color = const Color(0xff705b40)
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * .0018);
      c.drawLine(
          rect.topLeft + const Offset(1, 1),
          rect.topRight + const Offset(-1, 1),
          Paint()
            ..color = const Color(0xbaffffff)
            ..strokeWidth = w * .003);
      c.drawLine(
          rect.topLeft + const Offset(1, 1),
          rect.bottomLeft + const Offset(1, -1),
          Paint()
            ..color = const Color(0x80ffffff)
            ..strokeWidth = w * .002);
      c.drawLine(
          rect.bottomLeft + const Offset(1, -1),
          rect.bottomRight + const Offset(-1, -1),
          Paint()
            ..color = const Color(0x90776142)
            ..strokeWidth = w * .003);
      if (selected == id) {
        c.drawRect(
            rect.deflate(w * .002),
            Paint()
              ..color = monopolyGold
              ..style = PaintingStyle.stroke
              ..strokeWidth = w * .006);
      }
      final s =
          id < board.length ? monopolyMap(board[id]) : <String, dynamic>{};
      final deed = monopolyMap(deeds['$id']);
      final seat = players.indexOf(deed['owner']?.toString() ?? '');
      if (seat >= 0) {
        c.drawCircle(rect.bottomRight - Offset(w * .008, w * .008), w * .006,
            Paint()..color = monopolySeatColors[seat % 8]);
      }
      c.save();
      c.translate(rect.center.dx, rect.center.dy);
      double angle = id > 10 && id < 20
          ? math.pi / 2
          : id > 20 && id < 30
              ? math.pi
              : id > 30
                  ? -math.pi / 2
                  : 0;
      c.rotate(angle);
      final rotated = angle.abs() == math.pi / 2;
      final rw = rotated ? rect.height : rect.width,
          rh = rotated ? rect.width : rect.height;
      final local = Rect.fromCenter(center: Offset.zero, width: rw, height: rh);
      if (id % 10 == 0) {
        final label = switch (id) {
          0 => 'GO',
          10 => 'JAIL\nVISITING',
          20 => 'FREE\nPARKING',
          _ => 'GO TO\nJAIL'
        };
        text(c, label, local.deflate(w * .005),
            font: rw * .19,
            color: id == 0 ? const Color(0xffb33437) : monopolyInk);
        if (id == 0) {
          final y = local.bottom - rh * .20;
          final arrow = Path()
            ..moveTo(-rw * .30, y)
            ..lineTo(rw * .28, y)
            ..moveTo(-rw * .30, y)
            ..lineTo(-rw * .14, y - rh * .09)
            ..moveTo(-rw * .30, y)
            ..lineTo(-rw * .14, y + rh * .09);
          c.drawPath(
              arrow,
              Paint()
                ..color = const Color(0xffb33437)
                ..style = PaintingStyle.stroke
                ..strokeWidth = rw * .055);
        }
      } else {
        final group = s['group']?.toString();
        final kind = s['kind']?.toString();
        if (kind == 'street') {
          final band = Rect.fromLTWH(local.left, local.top, rw, rh * .23);
          c.drawRect(band.translate(0, w * .002),
              Paint()..color = const Color(0xff654e34));
          c.drawRect(band, Paint()..color = monopolyGroupColor(group));
          c.drawLine(
              band.topLeft + Offset(0, w * .002),
              band.topRight + Offset(0, w * .002),
              Paint()
                ..color = const Color(0x99ffffff)
                ..strokeWidth = w * .002);
          final buildings = (deed['buildings'] as num?)?.toInt() ?? 0;
          if (buildings > 0) {
            final count = buildings == 5 ? 1 : buildings;
            for (int n = 0; n < count; n++) {
              final x = band.left + rw * (n + 1) / (count + 1);
              _house(c, Offset(x, band.center.dy),
                  rw * (buildings == 5 ? 0.36 : 0.19), buildings == 5);
            }
          }
        }
        final name = (s['name'] ?? '')
            .toString()
            .replaceAll(' Avenue', '')
            .replaceAll(' Railroad', '\nRail')
            .replaceAll('Community Chest', 'Community\nChest')
            .replaceAll('Electric Company', 'Electric')
            .replaceAll('Water Works', 'Water\nWorks')
            .replaceAll('Luxury Tax', 'Luxury\nTax')
            .replaceAll('Income Tax', 'Income\nTax');
        final nameArea = Rect.fromLTWH(
            local.left + rw * .035,
            local.top + rh * (kind == 'street' ? .24 : .06),
            rw * .93,
            rh * (kind == 'street' ? .53 : .68));
        text(c, name, nameArea,
            font: rw * (kind == 'chest' ? .265 : .29),
            lines: 5,
            fitWords: true);
        final price = (s['price'] as num?)?.toInt() ?? 0;
        if (price > 0) {
          text(c, deed['mortgaged'] == true ? 'MORTGAGED' : '\$$price',
              Rect.fromLTWH(local.left, local.bottom - rh * .21, rw, rh * .19),
              font: rw * (deed['mortgaged'] == true ? 0.15 : 0.28));
        }
        if (kind == 'chance') {
          text(c, '?',
              Rect.fromLTWH(local.left, local.bottom - rh * .29, rw, rh * .26),
              font: rw * .4, color: const Color(0xffb94e20));
        }
      }
      c.restore();
    }
    // Embossed centre title and physical card decks.
    final titleArea = Rect.fromLTWH(w * .21, w * .41, w * .58, w * .13);
    text(c, 'MONOPOLY', titleArea.translate(0, w * .004),
        font: w * .066, color: const Color(0xff0e342a));
    text(c, 'MONOPOLY', titleArea,
        font: w * .066, color: const Color(0xffefe1b4));
    text(c, 'PLAYHUUD • CLASSIC',
        Rect.fromLTWH(w * .25, w * .52, w * .5, w * .035),
        font: w * .018, color: const Color(0xffd0c3a0));
    _deck(c, Rect.fromLTWH(w * .24, w * .23, w * .2, w * .115), 'CHANCE',
        const Color(0xffc88747), -.13);
    _deck(c, Rect.fromLTWH(w * .57, w * .63, w * .2, w * .115),
        'COMMUNITY\nCHEST', const Color(0xffa8c9c0), -.13);
    final dice = (state['dice'] as List? ?? [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toList();
    if (dice.length == 2) {
      _die(c, Offset(w * .43, w * .66), w * .075, dice[0], -.13);
      _die(c, Offset(w * .52, w * .68), w * .075, dice[1], .12);
    }
    text(
        c,
        '${state['bankHouses'] ?? 32} HOUSES  ·  ${state['bankHotels'] ?? 12} HOTELS',
        Rect.fromLTWH(w * .27, w * .765, w * .46, w * .025),
        font: w * .015,
        color: const Color(0xffd7cbaf));
    final people = monopolyMap(state['playerState']),
        old = monopolyMap(previous['playerState']);
    final groups = <int, List<String>>{};
    for (final id in players) {
      final p = monopolyMap(people[id]);
      if (p['bankrupt'] == true) continue;
      final pos = (p['position'] as num?)?.toInt() ?? 0;
      (groups[pos] ??= []).add(id);
    }
    for (int seat = 0; seat < players.length; seat++) {
      final id = players[seat], p = monopolyMap(people[id]);
      if (p['bankrupt'] == true) continue;
      final pos = (p['position'] as num?)?.toInt() ?? 0;
      final before = (monopolyMap(old[id])['position'] as num?)?.toInt() ?? pos;
      Offset location = monopolySpaceRect(pos, w).center;
      if (motion < 1 && before != pos) {
        if (p['jailed'] == true) {
          location = Offset.lerp(monopolySpaceRect(before, w).center, location,
              Curves.easeInOut.transform(motion))!;
        } else {
          final steps = (pos - before) % 40;
          final progress = Curves.easeInOut.transform(motion) * steps;
          final a = (before + progress.floor()) % 40, b = (a + 1) % 40;
          location = Offset.lerp(monopolySpaceRect(a, w).center,
              monopolySpaceRect(b, w).center, progress - progress.floor())!;
        }
      }
      final shared = groups[pos]!;
      final index = shared.indexOf(id);
      final offset = shared.length > 1
          ? Offset(((index % 3) - 1) * w * .022, ((index ~/ 3) - .5) * w * .026)
          : Offset.zero;
      _metalToken(c, location + Offset(0, w * .016) + offset, w * .07, seat);
    }
  }

  void _deck(Canvas c, Rect rect, String label, Color color, double angle) {
    c.save();
    c.translate(rect.center.dx, rect.center.dy);
    c.rotate(angle);
    final r = Rect.fromCenter(
        center: Offset.zero, width: rect.width, height: rect.height);
    for (int i = 4; i >= 0; i--) {
      final rr = RRect.fromRectAndRadius(
          r.translate(i * .6, i * 1.1), const Radius.circular(3));
      c.drawRRect(
          rr, Paint()..color = i == 0 ? color : const Color(0xffd6c8a7));
      c.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8
            ..color = const Color(0xff493c28));
    }
    text(c, label, r.deflate(4), font: rect.width * .145);
    c.restore();
  }

  void _house(Canvas c, Offset p, double size, bool hotel) {
    final body = Rect.fromCenter(
        center: p + Offset(0, size * .16), width: size, height: size * .62);
    c.drawRect(body.translate(1, 1), Paint()..color = const Color(0xff193b25));
    c.drawRect(
        body,
        Paint()
          ..color = hotel ? const Color(0xffd74b36) : const Color(0xff41a46b));
    final roof = Path()
      ..moveTo(p.dx - size * .6, p.dy)
      ..lineTo(p.dx, p.dy - size * .45)
      ..lineTo(p.dx + size * .6, p.dy)
      ..close();
    c.drawPath(
        roof,
        Paint()
          ..color = hotel ? const Color(0xff7f201b) : const Color(0xff155839));
    c.drawLine(
        body.topLeft,
        body.bottomLeft,
        Paint()
          ..color = const Color(0xffabe0b0)
          ..strokeWidth = 1);
  }

  void _die(Canvas c, Offset p, double size, int value, double angle) {
    c.save();
    c.translate(p.dx, p.dy);
    c.rotate(angle);
    final r = Rect.fromCenter(center: Offset.zero, width: size, height: size);
    c.drawRRect(
        RRect.fromRectAndRadius(r.translate(2, 3), Radius.circular(size * .17)),
        Paint()..color = const Color(0x80000000));
    c.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(size * .17)),
        Paint()
          ..shader = const LinearGradient(
              colors: [Color(0xfffffae7), Color(0xffd5be94)]).createShader(r));
    final points = <Offset>[];
    if (value.isOdd) points.add(Offset.zero);
    if (value >= 2) {
      points.addAll(
          [Offset(-size * .25, -size * .25), Offset(size * .25, size * .25)]);
    }
    if (value >= 4) {
      points.addAll(
          [Offset(size * .25, -size * .25), Offset(-size * .25, size * .25)]);
    }
    if (value == 6) {
      points.addAll([Offset(-size * .25, 0), Offset(size * .25, 0)]);
    }
    for (final p in points) {
      c.drawCircle(p, size * .075, Paint()..color = monopolyInk);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.state != state || old.motion != motion || old.selected != selected;
}
