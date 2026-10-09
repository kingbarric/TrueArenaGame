import 'package:flutter/material.dart';

/// The app's tab pictures (`assets/images/nav/`): huud, live, games, friends,
/// messages, you, foryou. Selected, a tab shows its all-orange picture; not
/// selected, the grey-and-orange one in light mode — and, where grey would
/// vanish into a dark menu, the orange one dimmed.
class NavArt extends StatelessWidget {
  const NavArt(this.name, {super.key, required this.active, this.size = 24});

  final String name;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final picture = Image.asset(
      'assets/images/nav/${name}_${active || dark ? 'active' : 'idle'}.png',
      key: ValueKey('nav-art-$name-${active ? 'on' : 'off'}'),
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
    return !active && dark ? Opacity(opacity: 0.5, child: picture) : picture;
  }
}
