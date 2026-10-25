import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'slay_assets.dart';
import 'slay_models.dart';
import 'slay_theme.dart';
import '../../theme/neon_theme.dart';

class SlayStageController {
  final ready = ValueNotifier<bool>(false);
  final showingOff = ValueNotifier<bool>(false);
  final showcasePhase = ValueNotifier<String>('');
  Future<String> showOff() async =>
      (await request('showcase', {}))['pose'] as String;
  Future<void> stopShowOff() async {
    await request('stopShowcase', {});
  }

  InAppWebViewController? _web;
  int _sequence = 0;
  int _indicatorRevision = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  Completer<void> _ready = Completer<void>();

  /// [timeout] covers the renderer's answer. Putting a look on can mean
  /// downloading its art first, so that waits longer than a camera move.
  Future<Map<String, dynamic>> request(
      String type, Map<String, dynamic> payload,
      {Duration timeout = const Duration(seconds: 25)}) async {
    await _ready.future.timeout(const Duration(seconds: 25));
    final id = 'slay-${++_sequence}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    try {
      // Attach the response handler immediately: JS can reply with an error
      // before evaluateJavascript itself completes.
      final results = await Future.wait<dynamic>([
        _web!.evaluateJavascript(
            source: 'void window.slayReceive(${jsonEncode({
              'v': 1,
              'id': id,
              'type': type,
              'payload': payload
            })});'),
        completer.future.timeout(timeout),
      ], eagerError: true);
      return results[1] as Map<String, dynamic>;
    } finally {
      _pending.remove(id);
    }
  }

  /// The final portrait as JPEG bytes (opaque stage background, ~100 KB).
  Future<Uint8List> snapshot() async => base64Decode(
      (await request('snapshot', {'width': 600, 'height': 900}))['jpegBase64']
          as String);
  void _reset({bool deferIndicators = false}) {
    final revision = ++_indicatorRevision;
    void resetIndicators() {
      if (revision != _indicatorRevision) return;
      ready.value = false;
      showingOff.value = false;
      showcasePhase.value = '';
    }

    // Disposing a stage can leave its parent's listeners mounted while the
    // widget tree is locked. Notify after unmount, unless a new stage reset it.
    if (deferIndicators) {
      scheduleMicrotask(resetIndicators);
    } else {
      resetIndicators();
    }
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('The 3D stage restarted'));
    }
    _pending.clear();
    _ready = Completer<void>();
  }
}

class SlayStage extends StatefulWidget {
  const SlayStage(
      {super.key,
      required this.catalog,
      required this.look,
      required this.controller,
      this.onLoadFailed});
  final Map<String, dynamic> catalog;
  final SlayLook look;
  final SlayStageController controller;
  final void Function(SlayLook previous, String reason)? onLoadFailed;

  /// Widget tests have no WebView; they set this to draw a placeholder instead.
  @visibleForTesting
  static bool debugPlaceholder = false;
  @visibleForTesting
  static Future<void> Function(SlayLook look)? debugApplyLook;

  @override
  State<SlayStage> createState() => _SlayStageState();
}

class _SlayStageState extends State<SlayStage> with WidgetsBindingObserver {
  /// A first visit downloads the character and every garment before the
  /// look shows; on a phone network that can take well over 25 seconds.
  static const _lookTimeout = Duration(minutes: 2);

  /// The cause, short enough for the retry button.
  static String _reason(Object e) {
    final text = e is TimeoutException
        ? 'taking longer than usual'
        : e
            .toString()
            .replaceAll(
                RegExp(r'\b(Bad state|Exception|\w*Error)\b:?\s*',
                    caseSensitive: false),
                '')
            .trim();
    return text.length > 90 ? '${text.substring(0, 90)}…' : text;
  }

  bool _loading = true,
      _booting = false,
      _routeActive = true,
      _appActive = true;
  String? _error;
  bool _applyQueued = false;
  bool _initialised = false;
  int _applyRevision = 0;
  int _pageRevision = 0, _automaticRestarts = 0;
  bool _lowTier = false;
  SlayLook? _lastReadyLook;

  Future<void> _restart({bool automatic = false}) async {
    if (!mounted) return;
    ++_pageRevision;
    ++_applyRevision;
    _booting = false;
    _initialised = false;
    widget.controller._reset();
    if (automatic && _automaticRestarts++ >= 2) {
      setState(() => _error = 'The studio paused. Tap to reconnect.');
      return;
    }
    if (!automatic) _automaticRestarts = 0;
    setState(() => _error = null);
    try {
      await widget.controller._web?.reload();
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = 'Studio connection failed (${_reason(e)}). Tap to retry.');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (SlayStage.debugPlaceholder) {
      if (SlayStage.debugApplyLook != null) {
        _initialised = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _apply());
      }
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    try {
      SlayAssets.instance.configure(widget.catalog);
      await SlayAssets.instance.start();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Could not open the 3D studio (${_reason(e)}). Tap to retry.');
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (active != _routeActive) {
      _routeActive = active;
      if (widget.controller._web != null) {
        unawaited(widget.controller.request('pause', {
          'paused': !_routeActive || !_appActive
        }).catchError((_) => <String, dynamic>{}));
      }
    }
  }

  @override
  void didUpdateWidget(covariant SlayStage old) {
    super.didUpdateWidget(old);
    if (jsonEncode(old.look.toJson()) != jsonEncode(widget.look.toJson())) {
      // Readiness also drives the studio's submit button, outside this
      // subtree. Notify it after the current build has finished.
      if (_applyQueued) return;
      _applyQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyQueued = false;
        if (!mounted) return;
        _automaticRestarts = 0;
        if (_initialised) {
          unawaited(_apply());
        } else if (_error != null) {
          unawaited(_restart());
        }
      });
    }
  }

  Future<void> _apply() async {
    final revision = ++_applyRevision;
    final look = widget.look;
    widget.controller.ready.value = false;
    try {
      if (SlayStage.debugApplyLook != null) {
        await SlayStage.debugApplyLook!(look);
      } else {
        await widget.controller.request('applyLook', {'look': look.toJson()},
            timeout: _lookTimeout);
      }
      if (mounted && revision == _applyRevision) {
        _lastReadyLook = look;
        widget.controller.ready.value = true;
        setState(() => _error = null);
      }
    } catch (e) {
      debugPrint('SlayHuud applyLook failed: $e');
      if (mounted && revision == _applyRevision) {
        if (_lastReadyLook != null &&
            widget.onLoadFailed != null &&
            jsonEncode(_lastReadyLook!.toJson()) != jsonEncode(look.toJson())) {
          widget.onLoadFailed!(_lastReadyLook!, _reason(e));
          return;
        }
        setState(() => _error =
            'The look could not be loaded (${_reason(e)}). Tap to retry.');
      }
    }
  }

  Future<void> _message(Map<String, dynamic> message) async {
    final type = message['type'];
    final payload = Map<String, dynamic>.from(message['payload'] as Map? ?? {});
    final id = message['id'];
    if (id != null) {
      final c = widget.controller._pending[id];
      if (c != null && !c.isCompleted) {
        if (type == 'error') {
          c.completeError(StateError(payload['message']?.toString() ??
              'the studio stopped responding'));
        } else {
          c.complete(payload);
        }
      }
      return;
    }
    if (type == 'showcaseState') {
      widget.controller.showingOff.value = payload['playing'] == true;
      widget.controller.showcasePhase.value =
          payload['phase']?.toString() ?? '';
    } else if (type == 'ready' && !_booting) {
      _initialised = false;
      widget.controller.ready.value = false;
      _booting = true;
      final page = _pageRevision;
      if (!widget.controller._ready.isCompleted) {
        widget.controller._ready.complete();
      }
      try {
        await widget.controller.request('init',
            {'catalog': widget.catalog, 'tier': _lowTier ? 'low' : 'standard'});
        if (!mounted || page != _pageRevision) return;
        _initialised = true;
        await _apply();
        // Queued behind the look: if that was slow, this must not turn a
        // look still loading into "the studio could not load".
        await widget.controller.request('pause', {
          'paused': !_routeActive || !_appActive
        }).catchError((_) => <String, dynamic>{});
      } catch (e) {
        debugPrint('SlayHuud studio initialisation failed: $e');
        if (mounted && page == _pageRevision) {
          setState(() => _error =
              'The studio could not load (${_reason(e)}). Tap to retry.');
        }
      } finally {
        if (page == _pageRevision) _booting = false;
      }
    } else if (type == 'contextLost') {
      _lowTier = true;
      await _restart(automatic: true);
    } else if (type == 'error') {
      if (mounted) {
        setState(() => _error = payload['message'] == null
            ? '3D is unavailable on this device'
            : 'The studio could not load (${_reason(payload['message'] as Object)}). Tap to retry.');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (widget.controller._web == null) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller
          .request('pause', {'paused': !_routeActive})
          .then((_) => _apply())
          .catchError((_) {}));
    } else {
      unawaited(
          widget.controller.request('pause', {'paused': true}).catchError((_) {
        return <String, dynamic>{};
      }));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller._reset(deferIndicators: true);
    widget.controller._web = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (SlayStage.debugPlaceholder) {
      return ColoredBox(
          key: ValueKey(
              'slay-stage-${widget.look.avatarId ?? widget.look.body}'),
          color: context.neon.plate);
    }
    if (_loading) {
      return ColoredBox(
          color: context.neon.plate,
          child: Center(
              child: _error == null
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : TextButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.refresh),
                      label: Text(_error!))));
    }
    // Keep the WebView alive under the retry overlay; removing it also
    // removes the controller that retry needs to reload.
    return Stack(fit: StackFit.expand, children: [
      InAppWebView(
          // The 3D viewport owns drag/pinch. Flutter scroll views and route
          // gestures must not take these touches from OrbitControls.
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer())
          },
          initialUrlRequest: URLRequest(
              url: WebUri(
                  'http://localhost:8187/index.html?renderer=33&catalog=${widget.catalog['version']}')),
          initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              supportZoom: false,
              disableContextMenu: true,
              isInspectable: kDebugMode,
              useShouldOverrideUrlLoading: true),
          onWebViewCreated: (web) {
            widget.controller._web = web;
            web.addJavaScriptHandler(
                handlerName: 'slay',
                callback: (args) {
                  if (args.isNotEmpty && args.first is Map) {
                    unawaited(_message(Map<String, dynamic>.from(args.first)));
                  }
                  return null;
                });
          },
          shouldOverrideUrlLoading: (web, action) async =>
              action.request.url?.host == 'localhost'
                  ? NavigationActionPolicy.ALLOW
                  : NavigationActionPolicy.CANCEL,
          onConsoleMessage: (web, message) =>
              debugPrint('SlayHuud studio console: ${message.message}'),
          onLoadStop: (web, url) async {
            // Startup breaks quietly if the page script throws before it says
            // "ready"; log what the page managed to set up.
            final probe = await web.evaluateJavascript(
                source: 'JSON.stringify({bridge: typeof window.slayReceive,'
                    ' handler: typeof window.flutter_inappwebview})');
            debugPrint('SlayHuud studio loaded $url: $probe');
          },
          onReceivedError: (web, request, error) {
            if (request.isForMainFrame == true && mounted) {
              ++_pageRevision;
              ++_applyRevision;
              _booting = false;
              widget.controller._reset();
              setState(
                  () => _error = 'Studio connection failed. Tap to retry.');
              _initialised = false;
              debugPrint(
                  'SlayHuud page failed ${request.url}: ${error.description}');
            }
          },
          onWebContentProcessDidTerminate: (web) {
            _lowTier = true;
            unawaited(_restart(automatic: true));
          }),
      ValueListenableBuilder<bool>(
          valueListenable: widget.controller.ready,
          builder: (context, ready, _) => ready && _error == null
              ? const SizedBox.shrink()
              : ColoredBox(
                  color: context.neon.plate,
                  child: Center(
                      child: _error != null
                          ? TextButton.icon(
                              onPressed: () => _restart(),
                              icon: const Icon(Icons.refresh),
                              label: Text(_error!))
                          : Column(mainAxisSize: MainAxisSize.min, children: [
                              const CircularProgressIndicator(strokeWidth: 2),
                              const SizedBox(height: 12),
                              Text('Getting your look ready…',
                                  style: TextStyle(color: context.neon.mute)),
                            ])))),
    ]);
  }
}

/// Shared playful control; the long-running bridge request remains cancellable.
class SlayShowOffControl extends StatefulWidget {
  const SlayShowOffControl(
      {super.key,
      required this.controller,
      this.enabled = true,
      this.onFinished,
      this.onError});
  final SlayStageController controller;
  final bool enabled;
  final ValueChanged<String>? onFinished;
  final ValueChanged<Object>? onError;
  @override
  State<SlayShowOffControl> createState() => _SlayShowOffControlState();
}

class _SlayShowOffControlState extends State<SlayShowOffControl> {
  bool _starting = false;
  Future<void> _play() async {
    try {
      if (widget.controller.showingOff.value) {
        await widget.controller.stopShowOff();
      } else {
        if (_starting) return;
        setState(() => _starting = true);
        final pose = await widget.controller.showOff();
        if (mounted) widget.onFinished?.call(pose);
      }
    } catch (error) {
      if (mounted &&
          !error.toString().contains('cancelled') &&
          !error.toString().contains('restarted')) {
        widget.onError?.call(error);
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge(
          [widget.controller.ready, widget.controller.showingOff]),
      builder: (_, __) {
        final playing = widget.controller.showingOff.value;
        return SlayPill(
            label: playing ? 'Stop show off' : 'Show off',
            icon: playing ? Icons.stop_rounded : Icons.directions_walk_rounded,
            selected: playing,
            onPressed: playing ||
                    (widget.enabled &&
                        widget.controller.ready.value &&
                        !_starting)
                ? _play
                : null);
      });
}
