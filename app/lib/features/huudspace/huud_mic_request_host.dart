import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/hangout_state.dart';
import 'huud_space_models.dart';
import 'huud_voice.dart';

/// Huud mic requests belong to the admin, even while a game route is on top.
class HuudMicRequestHost extends StatefulWidget {
  const HuudMicRequestHost({
    super.key,
    required this.state,
    required this.navigatorKey,
    required this.child,
  });
  final AppState state;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<HuudMicRequestHost> createState() => _HuudMicRequestHostState();
}

class _HuudMicRequestHostState extends State<HuudMicRequestHost>
    with WidgetsBindingObserver {
  StreamSubscription? _events;
  Timer? _poll;
  final _pending = <String, _MicRequest>{};
  final _checking = <String>{};
  final _versions = <String, int>{};
  DialogRoute<HuudSpace>? _dialog;
  _MicRequest? _showing;
  String? _userId;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach();
  }

  void _attach() {
    _userId = widget.state.user?.id;
    widget.state.addListener(_accountChanged);
    _events = widget.state.huudSpaceEvents.listen(_onEvent);
    // Also recover requests missed while the inbox disconnected or the app slept.
    _poll = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _recover(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _recover());
  }

  @override
  void didUpdateWidget(covariant HuudMicRequestHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state == widget.state) return;
    oldWidget.state.removeListener(_accountChanged);
    _events?.cancel();
    _poll?.cancel();
    _clear();
    _attach();
  }

  void _accountChanged() {
    if (_userId == widget.state.user?.id) return;
    _clear();
    _userId = widget.state.user?.id;
    _refresh('current');
  }

  void _clear() {
    _generation++;
    _pending.clear();
    _checking.clear();
    _versions.clear();
    _closeDialog();
  }

  void _onEvent(Map<String, dynamic> event) {
    final data = (event['data'] as Map?)?.cast<String, dynamic>();
    final id = data?['huudSpaceId']?.toString();
    if (id == null) return;
    if (data?['event'] == 'declined-mic' && HuudVoice.instance.huudId == id) {
      HuudVoice.instance.asked = false;
      HangoutState.instance.changed();
    }
    if (const {
      'request',
      'host',
      'live-ended',
      'deleted',
      'removed',
      'left',
      'accepted-mic',
      'declined-mic',
    }.contains(data?['event'])) {
      _refresh(id);
    }
  }

  void _recover() {
    _refresh('current');
    final huudId = HuudVoice.instance.huudId;
    final ids = {
      if (huudId != null) huudId,
      for (final request in _pending.values) request.huud.id
    };
    for (final id in ids) {
      _refresh(id);
    }
  }

  Future<void> _refresh(String id) async {
    if (!mounted ||
        _userId == null ||
        widget.state.api.bearer == null ||
        !_checking.add(id)) {
      return;
    }
    final generation = _generation;
    final version = _versions[id] ?? 0;
    try {
      final raw = await widget.state.api
          .get('/huud-spaces/$id')
          .timeout(const Duration(seconds: 8));
      if (!mounted ||
          generation != _generation ||
          version != (_versions[id] ?? 0)) {
        return;
      }
      if (raw is Map) {
        _merge(HuudSpace.fromJson(raw.cast<String, dynamic>()));
      }
    } on ApiException catch (error) {
      if (mounted &&
          generation == _generation &&
          [401, 403, 404].contains(error.status)) {
        _pending.removeWhere((_, request) => request.huud.id == id);
        if (_showing?.huud.id == id) _closeDialog();
      }
    } catch (_) {
      /* A connection failure must not accept or decline anything. */
    } finally {
      if (generation == _generation) _checking.remove(id);
    }
  }

  void _merge(HuudSpace huud) {
    final waiting = <String, _MicRequest>{};
    if (huud.active && huud.live && huud.youCanManageMic) {
      for (final request in huud.requests.where(
        (request) => request.kind == 'mic',
      )) {
        final entry = _MicRequest(huud, request);
        waiting[entry.key] = entry;
      }
    }
    _pending.removeWhere(
      (key, entry) => entry.huud.id == huud.id && !waiting.containsKey(key),
    );
    _pending.addAll(waiting);
    if (_showing?.huud.id == huud.id && !waiting.containsKey(_showing?.key)) {
      _closeDialog();
    }
    _showNext();
  }

  void _closeDialog() {
    final route = _dialog;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _showNext() {
    if (_dialog != null || _pending.isEmpty || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final navigator = widget.navigatorKey.currentState;
      if (!mounted ||
          _dialog != null ||
          _pending.isEmpty ||
          navigator == null) {
        return;
      }
      final request = _pending.values.first;
      final generation = _generation;
      _showing = request;
      final route = DialogRoute<HuudSpace>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (_) =>
            _MicRequestDialog(api: widget.state.api, request: request),
      );
      _dialog = route;
      final updated = await navigator.push(route);
      _dialog = null;
      _showing = null;
      if (!mounted) return;
      if (generation != _generation) {
        _showNext();
        return;
      }
      _pending.remove(request.key);
      if (updated != null) {
        // Ignore older reads that started before the admin answered.
        _versions[request.huud.id] = (_versions[request.huud.id] ?? 0) + 1;
        _versions['current'] = (_versions['current'] ?? 0) + 1;
        _merge(updated);
      }
      _showNext();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recover();
  }

  @override
  void dispose() {
    _generation++;
    _events?.cancel();
    _poll?.cancel();
    widget.state.removeListener(_accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    _closeDialog();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _MicRequest {
  const _MicRequest(this.huud, this.request);
  final HuudSpace huud;
  final HuudRequest request;
  String get key => '${huud.id}/${request.from.userId}';
}

class _MicRequestDialog extends StatefulWidget {
  const _MicRequestDialog({required this.api, required this.request});
  final ApiClient api;
  final _MicRequest request;
  @override
  State<_MicRequestDialog> createState() => _MicRequestDialogState();
}

class _MicRequestDialogState extends State<_MicRequestDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _answer(bool accept) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = widget.request;
      final raw = await widget.api.post(
        '/huud-spaces/${request.huud.id}/requests/${request.request.from.userId}/mic',
        {'accept': accept},
      ).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      Navigator.of(context)
          .pop(HuudSpace.fromJson((raw as Map).cast<String, dynamic>()));
    } on ApiException catch (error) {
      if (!mounted) return;
      if ([401, 403, 404, 409].contains(error.status)) {
        Navigator.of(context).pop();
      } else {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              userErrorMessage,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          key: const ValueKey('huud-mic-request-dialog'),
          icon: const Icon(Icons.record_voice_over_rounded, size: 36),
          title: const Text(
            'Mic request',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.request.request.from.handle} wants to speak',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text('Allow their microphone in ${widget.request.huud.name}?'),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: _busy ? null : () => _answer(false),
              child: const Text('Decline'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _answer(true),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Accept'),
            ),
          ],
        ),
      );
}
