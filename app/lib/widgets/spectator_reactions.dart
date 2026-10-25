import 'dart:async';
import 'package:flutter/material.dart';

const spectatorReactions = ['👏', '🔥', '😂', '😮', '💔', '🎉'];

class SpectatorReactionLane extends StatelessWidget {
  const SpectatorReactionLane(
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

/// Ephemeral audience feedback, bounded and cleaned up by one timer.
class SpectatorReactions extends ChangeNotifier {
  final visible = <Map<String, dynamic>>[];
  final _seen = <String>{};
  Timer? _sweep;
  int _serial = 0;
  void receive(Map<String, dynamic> data) {
    final id = data['id'] as String?;
    final sent = (data['sentAtMs'] as num?)?.toInt();
    if (id == null ||
        sent == null ||
        !spectatorReactions.contains(data['emoji']) ||
        DateTime.now().millisecondsSinceEpoch - sent > 3000 ||
        !_seen.add(id)) {
      return;
    }
    if (_seen.length > 128) _seen.remove(_seen.first);
    visible.add(
        {...data, 'lane': _serial++ % 2, 'expires': (_sweep?.tick ?? 0) + 23});
    if (visible.length > 8) visible.removeAt(0);
    _sweep ??= Timer.periodic(const Duration(milliseconds: 100), (timer) {
      visible.removeWhere((r) => (r['expires'] as int) <= timer.tick);
      if (visible.isEmpty) {
        timer.cancel();
        _sweep = null;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void clear() {
    _sweep?.cancel();
    _sweep = null;
    visible.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _sweep?.cancel();
    super.dispose();
  }
}
