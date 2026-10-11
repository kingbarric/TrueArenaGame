import 'package:flutter/material.dart';

import '../../theme/huud_colors.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/game_badge.dart';
import '../../widgets/neon.dart';
import '../huud/huud_models.dart';
import 'huud_space_models.dart';

export '../../theme/huud_colors.dart';

// The Huud pages' building blocks. Made for small hands and new readers:
// every button has a word *and* a picture, every tap target is at least
// 52 tall, and orange is the one colour that means "you can tap this".

/// The Huud's own picture: three friends under one roof.
const huudIcon = 'assets/images/branding/huud_icon.png';

/// Backdrops a host can give their Huud: (wire, label, picture). The first
/// is the default — no picture at all.
const huudBackgrounds = <(String?, String, String?)>[
  // Not picked yet = the disco floor; "Blank" is no picture at all.
  (null, 'Disco', 'assets/images/huud_backgrounds/disco.jpg'),
  ('blank', 'Blank', null),
  ('lounge', 'Lounge', 'assets/images/huud_backgrounds/lounge.jpg'),
  ('poolside', 'Poolside', 'assets/images/huud_backgrounds/poolside.jpg'),
  ('club', 'Club', 'assets/images/huud_backgrounds/club.jpg'),
];

String? huudBackgroundAsset(String? wire) => huudBackgrounds.where((b) => b.$1 == wire).map((b) => b.$3).firstOrNull;

/// The Huud's backdrop behind [child]: the picture, washed over with the
/// page colour so it sets a mood without getting in the way of anything.
/// No picture (the default) is just the page as it always was.
class HuudBackdrop extends StatelessWidget {
  const HuudBackdrop({super.key, required this.background, required this.child});
  final String? background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final asset = huudBackgroundAsset(background);
    if (asset == null) return child;
    final n = context.neon;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(fit: StackFit.expand, children: [
      Image.asset(asset, key: ValueKey('backdrop-${background ?? 'disco'}'), fit: BoxFit.cover),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              n.bg.withValues(alpha: dark ? 0.55 : 0.72),
              n.bg.withValues(alpha: dark ? 0.78 : 0.86),
              n.bg.withValues(alpha: dark ? 0.9 : 0.94),
            ],
          ),
        ),
      ),
      child,
    ]);
  }
}

const huudGameOrder = ['whot', 'draughts', 'chess', 'ludo', 'wordbluff', 'truearena', 'goosi'];

const huudGameEmoji = {
  'truearena': '🕵️',
  'wordbluff': '🤫',
  'draughts': '⚫',
  'chess': '♟️',
  'goosi': '🥜',
  'whot': '🃏',
  'ludo': '🎲',
};

String huudGameName(String? gameType) => huudGameNames[gameType] ?? 'a game';

/// A chunky pill button: icon + word, orange by default.
class HuudButton extends StatelessWidget {
  const HuudButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.kind = HuudButtonKind.orange,
    this.expand = false,
    this.busy = false,
    this.big = false,
    this.image,
  });

  final String label;
  final IconData icon;

  /// A picture in place of [icon] (the Huud icon on "Make my Huud").
  final String? image;
  final VoidCallback? onPressed;
  final HuudButtonKind kind;
  final bool expand;
  final bool busy;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final disabled = onPressed == null || busy;
    final (Color fill, Color fg, Color edge) = switch (kind) {
      HuudButtonKind.orange => (h.orange, h.onOrange, kCabinetInk),
      HuudButtonKind.soft => (h.orangeSoft, h.orangeText, h.orangeText.withValues(alpha: 0.35)),
      HuudButtonKind.plain => (n.panel, n.ink, n.line),
      HuudButtonKind.danger => (n.danger.withValues(alpha: 0.12), n.danger, n.danger.withValues(alpha: 0.5)),
    };
    final height = big ? 60.0 : 52.0;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
        else if (image != null)
          Image.asset(image!, width: big ? 30 : 26, height: big ? 30 : 26)
        else
          Icon(icon, size: big ? 24 : 21, color: fg),
        const SizedBox(width: 10),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: big ? 18 : 16, fontWeight: FontWeight.w900, color: fg, letterSpacing: 0.2)),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: !disabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: disabled && !busy ? 0.5 : 1,
        child: Bouncy(
          onTap: disabled ? null : onPressed,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(color: edge, width: kind == HuudButtonKind.orange ? 2.4 : 1.6),
              boxShadow: kind == HuudButtonKind.orange
                  ? const [BoxShadow(color: Colors.black26, blurRadius: 0, offset: Offset(2, 3))]
                  : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

enum HuudButtonKind { orange, soft, plain, danger }

/// A round icon button with its word underneath — the quick-action row.
class HuudRoundAction extends StatelessWidget {
  const HuudRoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final fg = danger ? n.danger : (active ? h.onOrange : h.orangeText);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Bouncy(
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? h.orange : (danger ? n.danger.withValues(alpha: 0.12) : h.orangeSoft),
                border: Border.all(
                    color: active
                        ? kCabinetInk
                        : (danger ? n.danger.withValues(alpha: 0.5) : h.orangeText.withValues(alpha: 0.3)),
                    width: active ? 2.4 : 1.4),
              ),
              child: Icon(icon, color: fg, size: 26),
            ),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: danger ? n.danger : n.ink)),
          ]),
        ),
      ),
    );
  }
}

/// The big orange "hero" card at the top of a page.
class HuudHeroCard extends StatelessWidget {
  const HuudHeroCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final h = HuudColors.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: h.glow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kCabinetInk, width: 2.5),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 0, offset: Offset(3, 5))],
      ),
      child: DefaultTextStyle.merge(style: const TextStyle(color: kCabinetInk), child: child),
    );
  }
}

/// A plain rounded card that sits on the page.
class HuudCard extends StatelessWidget {
  const HuudCard(
      {super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.highlight = false});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final h = HuudColors.of(context);
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: n.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: highlight ? h.orange : n.line, width: highlight ? 2.4 : 1.4),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Bouncy(feel: BouncyFeel.soft, onTap: onTap, child: card);
  }
}

/// A little rounded label: "🟢 Live", "👫 Friends", "👑 Host".
class HuudChip extends StatelessWidget {
  const HuudChip(this.text, {super.key, this.emoji, this.color, this.onOrange = false});
  final String text;
  final String? emoji;
  final Color? color;

  /// Sitting on the orange hero card: dark ink on a light wash.
  final bool onOrange;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final tint = color ?? n.mid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onOrange ? Colors.white.withValues(alpha: 0.55) : tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: onOrange ? kCabinetInk.withValues(alpha: 0.35) : tint.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (emoji != null) ...[Text(emoji!, style: const TextStyle(fontSize: 13)), const SizedBox(width: 5)],
        Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: onOrange ? kCabinetInk : tint)),
      ]),
    );
  }
}

/// A pulsing green dot + "Live".
class HuudLiveChip extends StatefulWidget {
  const HuudLiveChip({super.key, this.label = 'Live'});
  final String label;

  @override
  State<HuudLiveChip> createState() => _HuudLiveChipState();
}

class _HuudLiveChipState extends State<HuudLiveChip> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100), value: 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect "reduce motion": a steady dot still says Live.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HuudColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: h.live.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: h.live.withValues(alpha: 0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
          child: Container(width: 9, height: 9, decoration: BoxDecoration(color: h.live, shape: BoxShape.circle)),
        ),
        const SizedBox(width: 6),
        Text(widget.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: h.live)),
      ]),
    );
  }
}

/// A soft orange glow that breathes — for "there's something new for you
/// here" (an unread chat message). Steady when the phone asks for less motion.
class HuudGlow extends StatefulWidget {
  const HuudGlow({super.key, required this.child, this.radius = 999});
  final Widget child;
  final double radius;

  @override
  State<HuudGlow> createState() => _HuudGlowState();
}

class _HuudGlowState extends State<HuudGlow> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900), value: 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HuudColors.of(context);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: [
            BoxShadow(
                color: h.orange.withValues(alpha: 0.35 + 0.45 * _pulse.value), blurRadius: 6 + 12 * _pulse.value),
          ],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Overlapping faces, then "+3".
class HuudAvatarStack extends StatelessWidget {
  const HuudAvatarStack({super.key, required this.people, this.total, this.size = 32, this.max = 5});
  final List<HuudMember> people;
  final int? total;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final shown = people.take(max).toList();
    final extra = (total ?? people.length) - shown.length;
    final step = size * 0.68;
    final width = shown.isEmpty ? 0.0 : size + step * (shown.length - 1) + (extra > 0 ? step : 0);
    return SizedBox(
      width: width,
      height: size,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(left: step * i, child: Avatar(shown[i].name, size: size, imageUrl: shown[i].avatarUrl)),
        if (extra > 0)
          Positioned(
            left: step * shown.length,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: n.plate, shape: BoxShape.circle, border: Border.all(color: kCabinetInk, width: 2)),
              child:
                  Text('+$extra', style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w900, color: n.ink)),
            ),
          ),
      ]),
    );
  }
}

/// The game's artwork in a rounded square, with an emoji fallback.
class HuudGameArt extends StatelessWidget {
  const HuudGameArt(this.gameType, {super.key, this.size = 56});
  final String gameType;
  final double size;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final art = GameBadge.artworkFor(huudArtworkId(gameType));
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Container(
        width: size,
        height: size,
        color: n.plate,
        alignment: Alignment.center,
        child: art == null
            ? Text(huudGameEmoji[gameType] ?? '🎮', style: TextStyle(fontSize: size * 0.5))
            : Image.asset(art,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Text(huudGameEmoji[gameType] ?? '🎮', style: TextStyle(fontSize: size * 0.5))),
      ),
    );
  }
}

/// A tappable game tile for the "pick a game" grid.
class HuudGameTile extends StatelessWidget {
  const HuudGameTile({super.key, required this.gameType, required this.onTap, this.busy = false});
  final String gameType;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Semantics(
      button: true,
      label: 'Play ${huudGameName(gameType)}',
      excludeSemantics: true,
      child: HuudCard(
        onTap: busy ? null : onTap,
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          busy
              ? const SizedBox(width: 64, height: 64, child: Center(child: CircularProgressIndicator()))
              : HuudGameArt(gameType, size: 64),
          const SizedBox(height: 10),
          Text(huudGameName(gameType),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: n.ink)),
        ]),
      ),
    );
  }
}

/// A section heading: big word, optional count, optional action on the right.
class HuudSectionTitle extends StatelessWidget {
  const HuudSectionTitle(this.title, {super.key, this.emoji, this.trailing});
  final String title;
  final String? emoji;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        if (emoji != null) ...[Text(emoji!, style: const TextStyle(fontSize: 22)), const SizedBox(width: 8)],
        Expanded(
          child: Text(title, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: n.ink)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// A friendly empty or problem state: big emoji, a sentence, one button.
class HuudFriendlyState extends StatelessWidget {
  const HuudFriendlyState({
    super.key,
    required this.emoji,
    required this.title,
    required this.message,
    this.action,
  });

  final String emoji;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return HuudCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 44)),
        const SizedBox(height: 10),
        Text(title,
            textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: n.ink)),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.35, color: n.mid)),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

/// A bottom sheet on a solid card, rounded on top with a grab handle. (The
/// app theme leaves sheets transparent for its frosted glass; a solid
/// surface reads more clearly for young players.)
Future<T?> showHuudSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  final n = context.neon;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: n.panel,
    barrierColor: kScrim,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      side: BorderSide(color: n.line, width: 1.4),
    ),
    builder: builder,
  );
}

/// Simple yes/no question with a big friendly "yes" and an easy way out.
Future<bool> confirmHuud(
  BuildContext context, {
  required String emoji,
  required String title,
  required String message,
  required String yes,
  bool danger = false,
}) async {
  final answer = await showHuudSheet<bool>(
    context,
    builder: (context) {
      final n = context.neon;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(emoji, textAlign: TextAlign.center, style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: n.ink)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.35, color: n.mid)),
            const SizedBox(height: 20),
            HuudButton(
              label: yes,
              icon: danger ? Icons.logout_rounded : Icons.check_rounded,
              kind: danger ? HuudButtonKind.danger : HuudButtonKind.orange,
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 10),
            HuudButton(
              label: 'No, stay',
              icon: Icons.close_rounded,
              kind: HuudButtonKind.plain,
              expand: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ]),
        ),
      );
    },
  );
  return answer == true;
}

/// A Huud message with the Huud icon in front ("You're invited to a Huud!").
SnackBar huudIconSnack(String message, {SnackBarAction? action}) => SnackBar(
      content: Row(children: [
        Image.asset(huudIcon, width: 26, height: 26),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 15))),
      ]),
      action: action,
    );

void huudSnack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message, style: const TextStyle(fontSize: 15))));
}
