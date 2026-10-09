import 'package:flutter/material.dart';
import '../../theme/neon_theme.dart';

// Keep PlayHuud's chosen palette and fonts, with arcade pills for SlayHuud.
ThemeData slayTheme(BuildContext context) => Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.copyWith(
            displaySmall: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 28, height: 1.12, fontWeight: FontWeight.w800),
            headlineMedium: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontSize: 22, fontWeight: FontWeight.w800),
          ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        backgroundColor: context.neon.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape:
            const StadiumBorder(side: BorderSide(color: kCabinetInk, width: 2)),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: const StadiumBorder(),
        side: BorderSide(color: context.neon.brand, width: 2),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      )),
      chipTheme: Theme.of(context).chipTheme.copyWith(
            shape: const StadiumBorder(),
            side: BorderSide(color: context.neon.line),
            selectedColor: context.neon.gold,
            labelStyle: TextStyle(color: context.neon.ink, fontSize: 12),
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
      segmentedButtonTheme: SegmentedButtonThemeData(
          style: SegmentedButton.styleFrom(
        shape: const StadiumBorder(),
        selectedBackgroundColor: context.neon.brand,
        selectedForegroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      )),
    );

/// A raised arcade pill using a native button for focus, keyboard and semantics.
class SlayButton extends StatelessWidget {
  const SlayButton(
      {super.key,
      required this.onPressed,
      required this.child,
      this.colour,
      this.compact = false})
      : icon = null,
        tonal = false;
  const SlayButton.tonal(
      {super.key,
      required this.onPressed,
      required this.child,
      this.colour,
      this.compact = false})
      : icon = null,
        tonal = true;
  const SlayButton.icon(
      {super.key,
      required this.onPressed,
      required Widget label,
      required this.icon,
      this.colour,
      this.compact = false})
      : child = label,
        tonal = false;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final Color? colour;
  final bool compact, tonal;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    final fill = colour ?? (tonal ? n.panel : n.brand);
    final foreground = colour != null
        ? n.onAccent
        : tonal
            ? n.ink
            : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: foreground,
          disabledForegroundColor: n.mute,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          minimumSize: Size(0, compact ? 40 : 48),
          padding:
              EdgeInsets.symmetric(horizontal: compact ? 12 : 20, vertical: 8),
          shape: const StadiumBorder(),
          textStyle: TextStyle(
              fontSize: compact ? 12 : 14, fontWeight: FontWeight.w800),
        ).copyWith(backgroundBuilder: (context, states, child) {
          final pressed = states.contains(WidgetState.pressed);
          final disabled = states.contains(WidgetState.disabled);
          return AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 90),
            transform: Matrix4.translationValues(0, pressed ? 3 : 0, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: disabled
                      ? [n.plate, n.plate]
                      : [Color.lerp(fill, Colors.white, .10)!, fill]),
              border:
                  Border.all(color: tonal ? n.line : kCabinetInk, width: 1.5),
              boxShadow: disabled
                  ? []
                  : [
                      BoxShadow(
                          color: Color.lerp(fill, kCabinetInk, .65)!,
                          offset: Offset(0, pressed ? 1 : 4),
                          blurRadius: 0)
                    ],
            ),
            child: child,
          );
        }),
        child: icon == null
            ? child
            : Row(mainAxisSize: MainAxisSize.min, children: [
                icon!,
                const SizedBox(width: 7),
                Flexible(child: child)
              ]),
      ),
    );
  }
}

class SlayPill extends StatelessWidget {
  const SlayPill(
      {super.key,
      required this.label,
      required this.onPressed,
      this.icon,
      this.selected = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool selected;
  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        child: SlayButton.tonal(
            onPressed: onPressed,
            compact: true,
            colour: selected ? context.neon.gold : null,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 16),
                const SizedBox(width: 5)
              ],
              Text(label),
            ])),
      );
}

/// Flat browsing controls distinguish wardrobe navigation from raised actions.
class SlayTab extends StatelessWidget {
  const SlayTab(
      {super.key,
      required this.label,
      required this.selected,
      required this.onPressed,
      this.pill = false});
  final String label;
  final bool selected, pill;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Semantics(
      selected: selected,
      child: Container(
        decoration: pill
            ? null
            : BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: selected ? n.gold : Colors.transparent,
                        width: 3))),
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: selected ? n.gold : n.mute,
            backgroundColor: pill
                ? (selected
                    ? n.gold.withValues(alpha: .14)
                    : n.plate.withValues(alpha: .5))
                : Colors.transparent,
            minimumSize: Size(0, pill ? 32 : 40),
            padding:
                EdgeInsets.symmetric(horizontal: pill ? 12 : 14, vertical: 6),
            shape: pill
                ? StadiumBorder(
                    side: BorderSide(
                        color:
                            selected ? n.gold.withValues(alpha: .65) : n.line))
                : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
            textStyle: TextStyle(
                fontSize: pill ? 12 : 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class SlayLabel extends StatelessWidget {
  const SlayLabel(this.text, {super.key, this.colour});
  final String text;
  final Color? colour;
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: .2,
        color: colour ?? context.neon.mute,
      ));
}

class SlayWardrobeTile extends StatelessWidget {
  const SlayWardrobeTile(
      {super.key,
      required this.name,
      required this.selected,
      required this.owned,
      required this.onTap,
      this.thumbnail,
      this.coins = 0});
  final String name;
  final String? thumbnail;
  final bool selected, owned;
  final int coins;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.neon;
    return Tooltip(
        message: name,
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          selected: selected,
          enabled: onTap != null,
          label:
              '$name, ${selected ? 'wearing' : owned ? 'owned' : '$coins coins'}',
          child: TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                foregroundColor: n.ink,
                textStyle: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(letterSpacing: 0),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ).copyWith(
                  backgroundBuilder: (context, states, child) => AnimatedScale(
                        scale: states.contains(WidgetState.pressed) ? .95 : 1,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 140),
                        curve: Curves.easeOutBack,
                        child: child,
                      )),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: selected
                      ? Color.alphaBlend(n.gold.withValues(alpha: .16), n.panel)
                      : n.panel,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: selected ? n.gold : n.line,
                      width: selected ? 2 : 1),
                  boxShadow: [
                    BoxShadow(
                        color: selected
                            ? n.gold.withValues(alpha: .35)
                            : kCabinetInk.withValues(alpha: .4),
                        offset: const Offset(0, 3))
                  ],
                ),
                child: ExcludeSemantics(
                    child: Column(children: [
                  Expanded(
                      child: Stack(children: [
                    Positioned.fill(
                        child: thumbnail != null
                            ? SlayThumbnail(url: thumbnail!)
                            : Icon(Icons.checkroom_rounded,
                                color: n.mute, size: 28)),
                    if (selected || !owned)
                      Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                  color: selected ? n.gold : n.plate,
                                  shape: BoxShape.circle),
                              child: Icon(
                                  selected
                                      ? Icons.check_rounded
                                      : Icons.lock_rounded,
                                  size: 12,
                                  color: selected ? n.onAccent : n.mute))),
                  ])),
                  const SizedBox(height: 3),
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 10,
                          height: 1.1,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  if (selected || !owned)
                    Text(selected ? 'On!' : '● $coins',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: n.gold)),
                ])),
              )),
        ));
  }
}

class SlayPanel extends StatelessWidget {
  const SlayPanel(
      {super.key,
      required this.child,
      this.colour,
      this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final Color? colour;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: context.neon.panel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colour ?? context.neon.line, width: 1.5),
          boxShadow: [
            BoxShadow(
                color: kCabinetInk.withValues(alpha: .35),
                offset: const Offset(0, 4),
                blurRadius: 0)
          ],
        ),
        child: child,
      );
}

class SlayImage extends StatelessWidget {
  const SlayImage(
      {super.key,
      required this.url,
      required this.headers,
      this.fit = BoxFit.cover,
      this.onReport,
      this.onBlock});
  final String url;
  final Map<String, String> headers;
  final BoxFit fit;
  final VoidCallback? onReport, onBlock;
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        Image.network(
          url,
          headers: headers,
          fit: fit,
          loadingBuilder: (c, w, p) => p == null
              ? w
              : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorBuilder: (c, e, s) => Center(
              child: Icon(Icons.image_not_supported_outlined,
                  color: context.neon.mute)),
        ),
        if (onReport != null || onBlock != null)
          Positioned(
              top: 2,
              right: 2,
              child: Material(
                  color: context.neon.panel.withValues(alpha: .92),
                  borderRadius: BorderRadius.circular(20),
                  child: PopupMenuButton<String>(
                      tooltip: 'Look options',
                      icon: const Icon(Icons.more_horiz, size: 20),
                      onSelected: (value) => value == 'report'
                          ? onReport?.call()
                          : onBlock?.call(),
                      itemBuilder: (_) => [
                            if (onReport != null)
                              const PopupMenuItem(
                                  value: 'report', child: Text('Report look')),
                            if (onBlock != null)
                              const PopupMenuItem(
                                  value: 'block', child: Text('Block player')),
                          ]))),
      ]);
}

/// Catalogue artwork may be bundled with the renderer or served by a CDN.
class SlayThumbnail extends StatelessWidget {
  const SlayThumbnail({super.key, required this.url});
  final String url;
  @override
  Widget build(BuildContext context) {
    Widget fallback(BuildContext c, Object e, StackTrace? s) =>
        Icon(Icons.checkroom_rounded, color: c.neon.mute, size: 32);
    return url.startsWith('assets/')
        ? Image.asset('assets/slay_renderer/$url',
            fit: BoxFit.contain, errorBuilder: fallback)
        : Image.network(url, fit: BoxFit.contain, errorBuilder: fallback);
  }
}

Future<bool?> showSlayUnlock(
        BuildContext context, String name, int cost, int? balance) =>
    showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28)),
              title: Text('Unlock $name?'),
              content: Text('$cost coins to add it to your wardrobe forever.'
                  '${balance == null ? '' : '\nYour balance: $balance coins.'}'
                  '${balance != null && balance < cost ? '\nEarn more coins to unlock this item.' : ''}'),
              actions: [
                SlayButton.tonal(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('No')),
                SlayButton(
                    onPressed: balance != null && balance < cost
                        ? null
                        : () => Navigator.pop(c, true),
                    child: Text('Yes · $cost coins'))
              ],
            ));
