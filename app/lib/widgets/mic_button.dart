import 'package:flutter/material.dart';

/// Where your mic is, the same everywhere — in a Huud and in every game:
enum MicState {
  /// You can listen but not talk yet: grey with a red crossed-out mic and a
  /// little ✋ — tap to ask.
  locked,

  /// You asked; waiting on the host / a player: grey with an hourglass.
  asked,

  /// You may talk, but your mic is off: a red ring and red crossed-out mic.
  muted,

  /// Your mic is on: amber — tap to mute.
  live,
}

extension MicStateWords on MicState {
  String get label => switch (this) {
        MicState.locked => 'Tap to ask',
        MicState.asked => 'Asked…',
        MicState.muted => 'Muted',
        MicState.live => 'Talking',
      };

  String get hint => switch (this) {
        MicState.locked => 'Tap to ask to talk',
        MicState.asked => 'Waiting for your turn to talk',
        MicState.muted => 'Muted — tap to talk',
        MicState.live => 'Your mic is on — tap to mute',
      };
}

class MicStateButton extends StatelessWidget {
  const MicStateButton({
    super.key,
    required this.state,
    required this.onTap,
    this.onLongPress,
    this.size = 40,
    this.showLabel = false,
    this.badge = false,
  });

  final MicState state;
  final VoidCallback? onTap;

  /// E.g. the game's live-talk panel.
  final VoidCallback? onLongPress;
  final double size;

  /// The word under the button (on the Huud screen; not in a game's top bar).
  final bool showLabel;

  /// A red dot: someone's waiting for you to answer (players see requests).
  final bool badge;

  static const amber = Color(0xfff59e0b);
  static const red = Color(0xffe5484d);
  static const grey = Color(0xff6b7280);

  @override
  Widget build(BuildContext context) {
    final (fill, ring, icon, iconColor) = switch (state) {
      MicState.locked => (grey.withValues(alpha: 0.28), grey.withValues(alpha: 0.6), Icons.mic_off_rounded, red),
      MicState.asked => (grey.withValues(alpha: 0.28), grey.withValues(alpha: 0.6), Icons.hourglass_top_rounded, const Color(0xffd1d5db)),
      MicState.muted => (red.withValues(alpha: 0.12), red, Icons.mic_off_rounded, red),
      MicState.live => (amber, const Color(0xffb45309), Icons.mic_rounded, Colors.white),
    };
    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: ring, width: state == MicState.live ? size * 0.045 : size * 0.05),
        boxShadow: state == MicState.live
            ? [BoxShadow(color: amber.withValues(alpha: 0.6), blurRadius: size * 0.35, spreadRadius: 1)]
            : null,
      ),
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        Icon(icon, key: ValueKey('mic-${state.name}'), color: iconColor, size: size * 0.5),
        // "Tap to ask": a little raised hand on the locked mic.
        if (state == MicState.locked)
          Positioned(
            right: -size * 0.08,
            bottom: -size * 0.06,
            child: Text('✋', style: TextStyle(fontSize: size * 0.32)),
          ),
        if (badge)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: size * 0.24,
              height: size * 0.24,
              decoration: BoxDecoration(
                color: red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ]),
    );
    return Semantics(
      button: true,
      label: state.hint,
      excludeSemantics: true,
      child: Tooltip(
        message: state.hint,
        child: GestureDetector(
          key: const ValueKey('mic-button'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLongPress,
          child: showLabel
              ? SizedBox(
                  width: size + 20,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    circle,
                    const SizedBox(height: 6),
                    Text(state.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: switch (state) {
                              MicState.live => amber,
                              MicState.muted => red,
                              _ => grey,
                            })),
                  ]),
                )
              : Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: circle),
        ),
      ),
    );
  }
}
