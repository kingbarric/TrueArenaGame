import 'package:flutter/material.dart';
import '../core/hangout_state.dart';
import '../theme/neon_theme.dart';
import 'talking_row.dart';

class PersistentHangout extends StatelessWidget {
  const PersistentHangout({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final call = HangoutState.instance;
    return ListenableBuilder(
        listenable: call,
        builder: (context, _) {
          final n = context.neon;
          return Overlay.wrap(
              child: Stack(children: [
            Padding(
              padding:
                  EdgeInsets.only(top: call.active && !call.expanded ? 58 : 0),
              child: child,
            ),
            if (call.screen != null)
              Positioned.fill(
                  child: Offstage(
                offstage: !call.expanded,
                child: HeroControllerScope.none(
                    child: Navigator(
                  key: ValueKey(call.screen),
                  onGenerateRoute: (_) =>
                      MaterialPageRoute(builder: (_) => call.screen!),
                )),
              )),
            if (call.active && !call.expanded)
              Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Material(
                        color: n.panel,
                        child: SizedBox(
                          height: 56,
                          child: Row(children: [
                            const SizedBox(width: 10),
                            // Faces with a glow on whoever's talking — visible over every game.
                            Expanded(
                                child: InkWell(
                                    key: const ValueKey('call-bar'),
                                    onTap: call.show,
                                    child: TalkingRow(call: call))),
                            IconButton(
                                tooltip: call.muted ? 'Unmute' : 'Mute',
                                icon: Icon(
                                    call.muted ? Icons.mic_off : Icons.mic),
                                onPressed: call.toggleMute),
                            IconButton(
                                tooltip: 'Play together',
                                icon: const Icon(Icons.sports_esports_outlined),
                                onPressed: call.play),
                            IconButton(
                                tooltip: 'Leave call',
                                icon: Icon(Icons.call_end, color: n.danger),
                                onPressed: call.leave),
                          ]),
                        )),
                  )),
          ]));
        });
  }
}
