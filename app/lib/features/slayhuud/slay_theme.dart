import 'package:flutter/material.dart';
import '../../theme/neon_theme.dart';
import '../../widgets/neon.dart';

// SlayHuud follows the player's chosen PlayHuud theme, including its design family.
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
    );

class SlayLabel extends StatelessWidget {
  const SlayLabel(this.text, {super.key, this.colour});
  final String text;
  final Color? colour;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
        color: colour ?? context.neon.mute,
      ));
}

class SlayPanel extends StatelessWidget {
  const SlayPanel(
      {super.key,
      required this.child,
      this.colour,
      this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final Color? colour;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) =>
      NeonCard(padding: padding, accent: colour, glass: false, child: child);
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
