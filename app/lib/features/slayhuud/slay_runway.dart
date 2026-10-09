import 'dart:async';
import 'package:flutter/material.dart';
import 'slay_models.dart';
import 'slay_stage.dart';
import 'slay_theme.dart';

/// One anonymous, immutable submitted look takes the stage at a time.
class SlayRunway extends StatefulWidget {
  const SlayRunway(
      {super.key,
      required this.catalog,
      required this.entries,
      required this.api,
      required this.onReviewed,
      required this.onReport});
  final Map<String, dynamic> catalog;
  final List<Map<String, dynamic>> entries;
  final SlayApi api;
  final ValueChanged<String> onReviewed, onReport;
  @override
  State<SlayRunway> createState() => _SlayRunwayState();
}

class _SlayRunwayState extends State<SlayRunway> {
  SlayStageController _stage = SlayStageController();
  SlayLook? _look;
  int _index = 0, _revision = 0;
  bool _failed = false, _played = false, _starting = false;
  bool _photo = false;
  Timer? _timeout;
  Map<String, dynamic> get _entry => widget.entries[_index];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final revision = ++_revision;
    _stage.ready.addListener(_ready);
    _timeout = Timer(const Duration(seconds: 30), () {
      if (mounted && revision == _revision && !_played) {
        setState(() => _failed = true);
      }
    });
    try {
      final look = await widget.api.runwayLook(_entry['lookId']);
      if (mounted && revision == _revision) setState(() => _look = look);
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _failed = true);
    }
  }

  void _ready() {
    if (!_stage.ready.value || _starting || _played || _photo) return;
    unawaited(_perform());
  }

  Future<void> _perform() async {
    final revision = _revision;
    _starting = true;
    try {
      await _stage.showOff();
      if (!mounted || revision != _revision || _photo) return;
      _timeout?.cancel();
      setState(() {
        _played = true;
        _failed = false;
      });
      widget.onReviewed(_entry['id']);
    } catch (_) {
      if (mounted && revision == _revision && !_photo) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _starting = false);
    }
  }

  void _next() {
    _timeout?.cancel();
    _stage.ready.removeListener(_ready);
    setState(() {
      _index++;
      _look = null;
      _failed = false;
      _played = false;
      _starting = false;
      _photo = false;
      _stage = SlayStageController();
    });
    _load();
  }

  @override
  void dispose() {
    _revision++;
    _timeout?.cancel();
    _stage.ready.removeListener(_ready);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(children: [
          Expanded(
              child: SlayLabel(
                  '${_entry['label']} · ${_index + 1}/${widget.entries.length}')),
          IconButton(
              tooltip: 'Report look',
              onPressed: () => widget.onReport(_entry['lookId']),
              icon: const Icon(Icons.flag_outlined, size: 18)),
        ]),
        SizedBox(
            height:
                (MediaQuery.sizeOf(context).height * .50).clamp(300.0, 520.0),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: _photo
                    ? SlayImage(
                        url: widget.api.imageUrl(_entry['image']),
                        headers: widget.api.imageHeaders)
                    : _look == null
                        ? Center(
                            child: _failed
                                ? const Text('The runway could not load.')
                                : const CircularProgressIndicator(
                                    strokeWidth: 2))
                        : SlayStage(
                            key: ValueKey('${_entry['id']}:$_revision'),
                            catalog: widget.catalog,
                            look: _look!,
                            controller: _stage))),
        const SizedBox(height: 10),
        ValueListenableBuilder<String>(
            valueListenable: _stage.showcasePhase,
            builder: (_, phase, __) => Text(_played
                ? 'Look complete · judge the style'
                : phase.isEmpty
                    ? 'Getting the runway ready…'
                    : phase)),
        const SizedBox(height: 10),
        if (_failed && !_photo)
          SlayButton.tonal(
              onPressed: () {
                _timeout?.cancel();
                setState(() {
                  _photo = true;
                  _played = true;
                });
                // The saved photo is the fallback for older submissions / unsupported 3D.
                widget.onReviewed(_entry['id']);
              },
              child: const Text('View submitted photo')),
        if (_played)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (!_photo)
              SlayPill(
                  label: 'Replay',
                  icon: Icons.replay_rounded,
                  onPressed: _starting ? null : () => unawaited(_perform())),
            if (_index + 1 < widget.entries.length) ...[
              const SizedBox(width: 8),
              SlayButton(
                  onPressed: _starting ? null : _next,
                  child: const Text('Next look')),
            ],
          ]),
      ]);
}
