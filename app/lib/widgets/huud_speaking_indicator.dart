import 'package:flutter/material.dart';
import '../core/hangout_state.dart';
import '../features/huud/social_huud_controller.dart';

/// Per-player activity comes from the Huud voice connection, independently of the match socket.
class HuudSpeakingIndicator extends StatelessWidget {
  const HuudSpeakingIndicator(
      {super.key, required this.userId, this.size = 14});
  final String userId;
  final double size;
  @override
  Widget build(BuildContext context) {
    final social = SocialHuudScope.maybeOf(context);
    if (social == null) return const SizedBox.shrink();
    final voice = HangoutState.instance;
    return ListenableBuilder(
        listenable: voice,
        builder: (context, _) {
          final speaking = voice.roomName == 'huud-${social.huud.id}' &&
              voice.participants
                  .any((p) => p.identity == userId && p.isSpeaking);
          return speaking
              ? Semantics(
                  label: 'Speaking',
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle),
                      child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(Icons.mic,
                              size: size, color: Colors.white))))
              : const SizedBox.shrink();
        });
  }
}
