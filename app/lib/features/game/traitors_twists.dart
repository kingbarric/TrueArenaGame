import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/neon_theme.dart';
import '../../widgets/huud_art.dart';
import '../../widgets/neon.dart';

/// Everything the table knows of the dynamics (docs/TRAITORS_DYNAMICS_PLAN.md):
/// what's public — the pie, the clues, the alibis, the Black Spot, the crowd —
/// and what only this player was shown — their offer, their lantern, their
/// jury seat. Refreshed from every snapshot; the server's word is final.
class TraitorsTwists {
  Map<String, dynamic>? pie;
  List<Map<String, dynamic>> clues = const [];
  Map<String, String> alibiBoard = const {};
  Map<String, dynamic>? spot;
  Map<String, dynamic>? standReveal;
  bool lastStandUsed = false;
  Map<String, dynamic>? hunch;

  bool canRecruit = false;
  List<String> recruitTargets = const [];
  String? recruitingTonight;
  bool recruitOffer = false;
  bool canBakePie = false;
  String? pieBakedTonight;
  bool canPlaceSpot = false;
  String? spotPending;
  bool alibiNeeded = false;
  String? yourAlibi;
  Map<String, dynamic>? seer;
  bool ghostJuror = false;
  String? yourJuryVote;
  bool canCrowdVote = false;
  String? yourCrowdVote;
  bool canLastStand = false;

  void apply(Map<String, dynamic> p) {
    Map<String, dynamic>? map(Object? o) => o is Map ? o.cast<String, dynamic>() : null;
    List<String> strings(Object? o) => o is List ? o.map((e) => e.toString()).toList() : const [];
    pie = map(p['pie']);
    clues = p['crimeClues'] is List
        ? [for (final c in p['crimeClues'] as List) (c as Map).cast<String, dynamic>()]
        : const [];
    alibiBoard = p['alibiBoard'] is Map ? (p['alibiBoard'] as Map).cast<String, String>() : const {};
    spot = map(p['blackSpot']);
    standReveal = map(p['standReveal']);
    lastStandUsed = p['lastStandUsed'] == true;
    hunch = map(p['crowdHunch']);
    canRecruit = p['canRecruit'] == true;
    recruitTargets = strings(p['recruitTargets']);
    recruitingTonight = p['recruitingTonight'] as String?;
    recruitOffer = p['recruitOffer'] == true;
    canBakePie = p['canBakePie'] == true;
    pieBakedTonight = p['pieBakedTonight'] as String?;
    canPlaceSpot = p['canPlaceSpot'] == true;
    spotPending = p['spotPending'] as String?;
    alibiNeeded = p['alibiNeeded'] == true;
    yourAlibi = p['yourAlibi'] as String?;
    seer = map(p['seer']);
    ghostJuror = p['ghostJuror'] == true;
    yourJuryVote = p['yourJuryVote'] as String?;
    canCrowdVote = p['canCrowdVote'] == true;
    yourCrowdVote = p['yourCrowdVote'] as String?;
    canLastStand = p['canLastStand'] == true;
  }

  String? get spotHolder => spot?['holder'] as String?;
  String? get spotSilenced => spot?['silenced'] as String?;
  List<String> get spotChain => spot?['chain'] is List ? (spot!['chain'] as List).cast<String>() : const [];
  bool get pieOnTable => pie?['available'] == true;
  String? get pieHolder => pie?['holder'] as String?;
  bool get canLight => seer?['canLight'] == true;
  Map<String, String> get visions =>
      seer?['visions'] is Map ? (seer!['visions'] as Map).cast<String, String>() : const {};

  /// The latest seat clue's glow: everyone within its reach of the victim.
  Set<String> seatGlow(List<String> seating) {
    final seat = clues.lastWhere((c) => c['kind'] == 'seat', orElse: () => const {});
    if (seat.isEmpty) return const {};
    final at = seating.indexOf(seat['victim'] as String? ?? '');
    final within = (seat['within'] as num?)?.toInt() ?? 0;
    if (at < 0) return const {};
    final n = seating.length;
    return {
      for (var i = 0; i < n; i++)
        if (i != at && math.min((i - at).abs(), n - (i - at).abs()) <= within) seating[i]
    };
  }

  /// Alibis as lines: gold where two back each other up, red where a story goes one way.
  List<({String from, String to, bool mutual})> get alibiLinks => [
        for (final e in alibiBoard.entries)
          if (!(alibiBoard[e.value] == e.key && e.key.compareTo(e.value) > 0))
            (from: e.key, to: e.value, mutual: alibiBoard[e.value] == e.key),
      ];
}

/// "A Traitor sat within 2 seats of Ada." — a clue, in words.
String clueText(Map<String, dynamic> clue, String Function(String) name) {
  final victim = name(clue['victim'] as String? ?? '');
  switch (clue['kind']) {
    case 'seat':
      final within = (clue['within'] as num?)?.toInt() ?? 1;
      return 'A Traitor sat within $within seat${within == 1 ? '' : 's'} of $victim.';
    case 'trio':
      final ids = ((clue['ids'] as List?) ?? const []).cast<String>().map(name).toList();
      return ids.length == 3 ? 'At least one of ${ids[0]}, ${ids[1]} and ${ids[2]} is a Traitor.' : 'A clue was left.';
    case 'vote':
      return 'A Traitor voted for ${name(clue['target'] as String? ?? '')} at the last vote.';
    default:
      return 'A clue was left at the scene.';
  }
}

/// A gentle, endless breath — off when the system asks for less motion.
class Breathing extends StatefulWidget {
  const Breathing({super.key, required this.builder, this.period = const Duration(milliseconds: 1800)});
  final Widget Function(BuildContext context, double t) builder;
  final Duration period;

  @override
  State<Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<Breathing> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => widget.builder(context, _c.value),
      );
}

// ---------------------------------------------------------------- the tabletop

/// One object on the table: a card in the tabletop tray with its own colour.
class TableObjectCard extends StatelessWidget {
  const TableObjectCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.body,
    required this.accent,
    this.action,
    this.onAction,
    this.leading,
  });

  final String emoji;
  final String title;
  final String body;
  final Color accent;
  final String? action;
  final VoidCallback? onAction;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Container(
      width: 232,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.24), n.panel.withValues(alpha: 0.96)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.7), width: 1.6),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 14, spreadRadius: -4)],
      ),
      // The tray gives every card the same height; the words take what's left
      // after the title and the button, and trail off rather than overflow.
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          leading ?? HuudText(emoji, artwork: false, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
          ),
        ]),
        const SizedBox(height: 4),
        Expanded(
          child: Text(body,
              maxLines: action == null ? 4 : 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: n.ink, fontSize: 12.5, height: 1.25)),
        ),
        if (action != null) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: kCabinetInk,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
              ),
              child: Text(action!),
            ),
          ),
        ],
      ]),
    );
  }
}

/// The pie itself: a latticed crust, steam curling off it while it's warm,
/// a golden glow once it's shown to be a shield, a sickly green if poison.
class PieArt extends StatelessWidget {
  const PieArt({super.key, this.size = 40, this.filling, this.warm = true});
  final double size;
  final String? filling;
  final bool warm;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: warm && filling == null
            ? Breathing(builder: (context, t) => CustomPaint(painter: _PiePainter(steam: t, filling: filling)))
            : CustomPaint(painter: _PiePainter(steam: 0, filling: filling)),
      );
}

class _PiePainter extends CustomPainter {
  _PiePainter({required this.steam, required this.filling});
  final double steam;
  final String? filling;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dish = Rect.fromCenter(center: Offset(w / 2, h * 0.68), width: w * 0.94, height: h * 0.42);
    if (filling == 'shield') {
      canvas.drawOval(dish.inflate(w * 0.08),
          Paint()..color = const Color(0xffffd36a).withValues(alpha: 0.55)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }
    canvas.drawOval(dish, Paint()..color = const Color(0xffe9dccb));
    final crust = dish.deflate(w * 0.07);
    final poisoned = filling == 'poison';
    canvas.drawOval(crust, Paint()..shader = RadialGradient(colors: poisoned
        ? const [Color(0xffa8c26a), Color(0xff4f6b2a)]
        : const [Color(0xfff2c27a), Color(0xffb36b2b)]).createShader(crust));
    final lattice = Paint()
      ..color = (poisoned ? const Color(0xff2f4214) : const Color(0xff8a4a1c)).withValues(alpha: 0.7)
      ..strokeWidth = math.max(1, w * 0.03);
    canvas.save();
    canvas.clipPath(Path()..addOval(crust));
    for (var i = -2; i <= 2; i++) {
      final dx = crust.center.dx + i * crust.width / 6;
      canvas.drawLine(Offset(dx - crust.height, crust.top), Offset(dx + crust.height, crust.bottom), lattice);
      canvas.drawLine(Offset(dx + crust.height, crust.top), Offset(dx - crust.height, crust.bottom), lattice);
    }
    canvas.restore();
    if (filling == null) {
      // Steam: three wisps curling up and fading as they rise.
      for (var k = 0; k < 3; k++) {
        final phase = (steam + k / 3) % 1.0;
        final x = w * (0.34 + 0.16 * k);
        final y = crust.top - h * 0.45 * phase;
        final path = Path()..moveTo(x, crust.top);
        path.cubicTo(x - w * 0.08, (crust.top + y) / 2, x + w * 0.08, (crust.top + y) / 2 - h * 0.05, x, y);
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1, w * 0.035)
              ..strokeCap = StrokeCap.round
              ..color = Colors.white.withValues(alpha: 0.55 * (1 - phase)));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) => old.steam != steam || old.filling != filling;
}

/// The Black Spot's colour: its rim, and its path round the table.
const kSpotCrimson = Color(0xffd6302a);

/// The Black Spot: a black coin with a crimson rim and a skull, pulsing where it sits.
class SpotToken extends StatelessWidget {
  const SpotToken({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) => Breathing(
        period: const Duration(milliseconds: 1400),
        builder: (context, t) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xff0d0708),
            border: Border.all(color: kSpotCrimson, width: math.max(1.4, size * 0.08)),
            boxShadow: [
              BoxShadow(
                  color: kSpotCrimson.withValues(alpha: 0.4 + 0.35 * math.sin(t * math.pi)),
                  blurRadius: 8 + 6 * math.sin(t * math.pi)),
            ],
          ),
          child: HuudText('☠️', artwork: false, style: TextStyle(fontSize: size * 0.52, height: 1)),
        ),
      );
}

/// The crowd's favourite suspect as a filling bar — or the crowd still deciding.
class CrowdMeter extends StatelessWidget {
  const CrowdMeter({super.key, required this.hunch, required this.name, this.onVote, this.yourVote});

  final Map<String, dynamic> hunch;
  final String Function(String) name;
  final VoidCallback? onVote;
  final String? yourVote;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final voters = (hunch['voters'] as num?)?.toInt() ?? 0;
    final suspect = hunch['suspect'] as String?;
    final percent = ((hunch['percent'] as num?)?.toDouble() ?? 0) / 100;
    final split = hunch['split'] == true;
    return Container(
      key: const ValueKey('traitors-crowd-meter'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: n.panel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: n.jade.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        const HuudText('👀', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(
              suspect == null
                  ? 'The crowd is still making up its mind…'
                  : split
                      ? 'The crowd is split — ${name(suspect)} and others'
                      : 'The crowd suspects ${name(suspect)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: n.ink, fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(children: [
                Container(height: 7, color: n.plate),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: suspect == null ? 0 : percent),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => FractionallySizedBox(
                    widthFactor: v.clamp(0.0, 1.0),
                    child: Container(
                      height: 7,
                      decoration: BoxDecoration(gradient: LinearGradient(colors: [n.jade, n.gold])),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 3),
            Text(
              '${suspect == null ? '' : '${(percent * 100).round()}% · '}$voters ${voters == 1 ? 'voice' : 'voices'}'
              '${yourVote == null ? '' : ' · your hunch: ${name(yourVote!)}'}',
              style: TextStyle(color: n.mute, fontSize: 10.5),
            ),
          ]),
        ),
        if (onVote != null)
          TextButton(
            key: const ValueKey('traitors-crowd-vote'),
            onPressed: onVote,
            child: Text(yourVote == null ? 'Your hunch' : 'Change'),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- moments

/// The sealed letter: "The Traitors want you. Join them — or else."
class RecruitLetter extends StatelessWidget {
  const RecruitLetter({super.key, required this.onAnswer, this.busy = false});
  final void Function(bool accept) onAnswer;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(
        scale: 0.6 + 0.4 * t,
        child: Transform.rotate(angle: (1 - t) * -0.2, child: Opacity(opacity: t.clamp(0.0, 1.0), child: child)),
      ),
      child: Container(
        key: const ValueKey('traitors-recruit-letter'),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xfff6e6c4), Color(0xffe2c995)]),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xff7b5a32), width: 2),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 12))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // The wax seal.
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [Color(0xffd23c3c), Color(0xff7a1414)]),
              boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3))],
            ),
            child: const Text('T',
                style: TextStyle(color: Color(0xfff6d8b0), fontSize: 26, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 14),
          Text('The Traitors want you.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displayLarge?.copyWith(color: const Color(0xff3a2412), fontSize: 24)),
          const SizedBox(height: 4),
          const Text('Join them — or else.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xff7a1414), fontSize: 16, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text('Nobody will know who sent this. Answer before the vote — silence is a no.',
              textAlign: TextAlign.center, style: TextStyle(color: Color(0xff5a3d22), fontSize: 12)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton(
                key: const ValueKey('traitors-recruit-refuse'),
                onPressed: busy ? null : () => onAnswer(false),
                style: FilledButton.styleFrom(backgroundColor: n.gold, foregroundColor: kCabinetInk,
                    minimumSize: const Size(0, 48)),
                child: const FittedBox(child: Text('Refuse 😇')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                key: const ValueKey('traitors-recruit-accept'),
                onPressed: busy ? null : () => onAnswer(true),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xff7a1414), foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48)),
                child: const FittedBox(child: Text('Join them 😈')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// The Ghost Jury at work: the tied pair, the ghosts drifting over them.
class GhostJuryStage extends StatelessWidget {
  const GhostJuryStage({
    super.key,
    required this.tied,
    required this.avatar,
    required this.name,
    required this.juror,
    required this.vote,
    required this.onVote,
    required this.footer,
  });

  final List<String> tied;
  final Widget Function(String id, double size) avatar;
  final String Function(String) name;
  final bool juror;
  final String? vote;
  final void Function(String id)? onVote;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    const mist = Color(0xffbcd7ff);
    return Container(
      key: const ValueKey('traitors-ghost-jury'),
      decoration: const BoxDecoration(
        gradient: RadialGradient(radius: 1.1, colors: [Color(0x553b5c8f), Color(0x00000000)]),
      ),
      child: Stack(children: [
        // Ghosts drifting up behind the verdict.
        Positioned.fill(
          child: IgnorePointer(
            child: Breathing(
              period: const Duration(seconds: 6),
              builder: (context, t) => LayoutBuilder(builder: (context, box) {
                return Stack(children: [
                  for (var k = 0; k < 5; k++)
                    Positioned(
                      left: box.maxWidth * ((k * 0.21 + 0.05) % 1.0),
                      top: box.maxHeight * (1 - ((t + k / 5) % 1.0)),
                      child: Opacity(
                        opacity: 0.18 + 0.2 * math.sin(((t + k / 5) % 1.0) * math.pi),
                        child: const HuudText('👻', style: TextStyle(fontSize: 30)),
                      ),
                    ),
                ]);
              }),
            ),
          ),
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const HuudText('⚖️', artwork: false, style: TextStyle(fontSize: 46)),
              const SizedBox(height: 8),
              Text('The Ghost Jury',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28, color: mist)),
              const SizedBox(height: 6),
              Text(
                juror
                    ? vote == null
                        ? 'You\'re out — but your voice still counts. Which of them goes?'
                        : 'Your verdict is in. The ghosts are still deciding…'
                    : 'The table is tied. The Faithful who are out will decide.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: n.mid),
              ),
              const SizedBox(height: 22),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final (i, id) in tied.indexed) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text('or', style: TextStyle(color: n.mute, fontWeight: FontWeight.w800)),
                    ),
                  Bouncy(
                    key: ValueKey('ghost-vote-$id'),
                    onTap: onVote == null ? null : () => onVote!(id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: n.panel.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: vote == id ? mist : n.line, width: vote == id ? 2.6 : 1.2),
                        boxShadow: vote == id ? [BoxShadow(color: mist.withValues(alpha: 0.5), blurRadius: 18)] : null,
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        avatar(id, 62),
                        const SizedBox(height: 6),
                        Text(name(id), style: TextStyle(color: n.ink, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 22),
              footer,
            ]),
          ),
        ),
      ]),
    );
  }
}

/// The Seer's lantern, glowing while it's still unlit.
class LanternGlow extends StatelessWidget {
  const LanternGlow({super.key, this.size = 44, this.lit = true});
  final double size;
  final bool lit;

  @override
  Widget build(BuildContext context) => Breathing(
        period: const Duration(milliseconds: 2200),
        builder: (context, t) => Container(
          width: size * 1.6,
          height: size * 1.6,
          alignment: Alignment.center,
          decoration: lit
              ? BoxDecoration(shape: BoxShape.circle, boxShadow: [
                  BoxShadow(
                      color: const Color(0xffffc04d).withValues(alpha: 0.35 + 0.25 * math.sin(t * math.pi)),
                      blurRadius: size * (0.5 + 0.3 * math.sin(t * math.pi))),
                ])
              : null,
          child: HuudText('🏮', style: TextStyle(fontSize: size)),
        ),
      );
}

/// A Last Stand, shown to the whole table: who stood, who they unmasked.
class LastStandBanner extends StatelessWidget {
  const LastStandBanner({super.key, required this.reveal, required this.name});
  final Map<String, dynamic> reveal;
  final String Function(String) name;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final traitor = reveal['side'] == 'traitor';
    final color = traitor ? n.brand : n.gold;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.7, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        key: const ValueKey('traitors-last-stand'),
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: n.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 2),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 20)],
        ),
        child: Row(children: [
          HuudText(traitor ? '😈' : '😇', style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${name(reveal['by'] as String)} made a Last Stand: '
              '${name(reveal['target'] as String)} is ${traitor ? 'a TRAITOR' : 'FAITHFUL'}.',
              style: TextStyle(color: n.ink, fontWeight: FontWeight.w800, fontSize: 13.5),
            ),
          ),
        ]),
      ),
    );
  }
}
