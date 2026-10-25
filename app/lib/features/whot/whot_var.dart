import 'dart:async';
import 'package:flutter/material.dart';
import 'whot_card.dart';
import 'whot_effects.dart';

/// The server supplies only public plays and counts. No hands enter this replay.
class WhotVarSheet extends StatefulWidget {
  const WhotVarSheet({super.key, required this.plays, required this.names});
  final List<Map<String, dynamic>> plays;
  final Map<String, String> names;
  @override
  State<WhotVarSheet> createState() => _WhotVarSheetState();
}

class _WhotVarSheetState extends State<WhotVarSheet> {
  late int _index = widget.plays.length - 1;
  Timer? _timer;
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _play() {
    _timer?.cancel();
    setState(() => _index = 0);
    _timer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (!mounted || _index >= widget.plays.length - 1) {
        timer.cancel();
        return;
      }
      setState(() => _index++);
    });
  }

  void _seek(int index) {
    _timer?.cancel();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final play = widget.plays[_index];
    final sizes = play['handSizes'] as Map? ?? const {};
    return SafeArea(
        child: SizedBox(
            height:
                (MediaQuery.sizeOf(context).height * .82).clamp(350.0, 600.0),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                const Text('VAR REPLAY',
                    key: ValueKey('whot-var-title'),
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const Text('Public plays only · the live game clock continues',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                Text(
                    '${widget.names[play['by']] ?? 'Player'} · ${whotMomentTitle(play)}',
                    textAlign: TextAlign.center),
                if (play['undone'] == true)
                  const Text('UNDONE — this turn was taken back',
                      style: TextStyle(color: Colors.orange)),
                Expanded(
                    child: Center(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if ((play['topBefore'] as String? ?? '').isNotEmpty) ...[
                    WhotCardView(code: play['topBefore'], scale: .85),
                    const Icon(Icons.arrow_forward_rounded),
                  ],
                  WhotCardView(code: play['card'], scale: .85),
                ]))),
                if ((play['debt'] as num? ?? 0) > 0)
                  Text('Outstanding Pick Two debt: +${play['debt']}'),
                Text(
                    sizes.entries
                        .map((entry) =>
                            '${widget.names[entry.key] ?? 'Player'}: ${entry.value}')
                        .join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11)),
                Slider(
                    key: const ValueKey('whot-var-slider'),
                    value: _index.toDouble(),
                    min: 0,
                    max: (widget.plays.length - 1).clamp(1, 24).toDouble(),
                    divisions: widget.plays.length > 1
                        ? widget.plays.length - 1
                        : null,
                    onChanged: widget.plays.length > 1
                        ? (value) => _seek(value.round())
                        : null),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(
                      tooltip: 'Previous play',
                      onPressed: _index > 0 ? () => _seek(_index - 1) : null,
                      icon: const Icon(Icons.skip_previous_rounded)),
                  IconButton(
                      tooltip: 'Replay from start',
                      onPressed: _play,
                      icon: const Icon(Icons.replay_rounded)),
                  Text('${_index + 1} / ${widget.plays.length}'),
                  IconButton(
                      tooltip: 'Next play',
                      onPressed: _index < widget.plays.length - 1
                          ? () => _seek(_index + 1)
                          : null,
                      icon: const Icon(Icons.skip_next_rounded)),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close')),
                ]),
              ]),
            )));
  }
}
