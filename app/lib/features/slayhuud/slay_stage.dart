import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'slay_models.dart';
import '../../theme/neon_theme.dart';

class SlayStageController {
  InAppWebViewController? _web;
  int _sequence = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  Completer<void> _ready = Completer<void>();
  Future<Map<String, dynamic>> request(
      String type, Map<String, dynamic> payload) async {
    await _ready.future.timeout(const Duration(seconds: 25));
    final id = 'slay-${++_sequence}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    try {
      await _web!.evaluateJavascript(
          source: 'window.slayReceive(${jsonEncode({
            'v': 1,
            'id': id,
            'type': type,
            'payload': payload
          })});');
      return await completer.future.timeout(const Duration(seconds: 25));
    } finally {
      _pending.remove(id);
    }
  }

  Future<String> snapshot() async =>
      (await request('snapshot', {'width': 600, 'height': 900}))['pngBase64']
          as String;
  void _reset() {
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
      required this.controller});
  final Map<String, dynamic> catalog;
  final SlayLook look;
  final SlayStageController controller;
  @override
  State<SlayStage> createState() => _SlayStageState();
}

class _SlayStageState extends State<SlayStage> with WidgetsBindingObserver {
  static final InAppLocalhostServer _server =
      InAppLocalhostServer(documentRoot: 'assets/slay_renderer', port: 8187);
  static Future<void>? _serverStart;
  bool _loading = true,
      _booting = false,
      _routeActive = true,
      _appActive = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    try {
      await (_serverStart ??= _server.start());
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      _serverStart = null;
      if (mounted) {
        setState(() => _error = 'Could not open the 3D studio. Tap to retry.');
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
      unawaited(_apply());
    }
  }

  Future<void> _apply() async {
    try {
      await widget.controller
          .request('applyLook', {'look': widget.look.toJson()});
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'The look could not be loaded. Tap to retry.');
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
          c.completeError(
              StateError(payload['message']?.toString() ?? 'Renderer error'));
        } else {
          c.complete(payload);
        }
      }
      return;
    }
    if (type == 'ready' && !_booting) {
      _booting = true;
      if (!widget.controller._ready.isCompleted) {
        widget.controller._ready.complete();
      }
      try {
        await widget.controller
            .request('init', {'catalog': widget.catalog, 'tier': 'high'});
        await widget.controller
            .request('applyLook', {'look': widget.look.toJson()});
        await widget.controller
            .request('pause', {'paused': !_routeActive || !_appActive});
        if (mounted) setState(() => _error = null);
      } catch (e) {
        if (mounted) {
          setState(() => _error = 'The studio could not load. Tap to retry.');
        }
      } finally {
        _booting = false;
      }
    } else if (type == 'contextLost') {
      widget.controller._reset();
      await widget.controller._web?.reload();
    } else if (type == 'error') {
      if (mounted) {
        setState(() => _error = payload['message']?.toString() ??
            '3D is unavailable on this device');
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
    widget.controller._reset();
    widget.controller._web = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ColoredBox(
          color: context.neon.plate,
          child: Center(
              child: TextButton.icon(
                  onPressed: () {
                    setState(() => _error = null);
                    widget.controller._web?.reload();
                    if (_loading) _start();
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(_error!))));
    }
    if (_loading) {
      return ColoredBox(
          color: context.neon.plate,
          child:
              const Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return InAppWebView(
        initialUrlRequest:
            URLRequest(url: WebUri('http://localhost:8187/index.html')),
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
        onReceivedError: (web, request, error) {
          if (request.isForMainFrame == true && mounted) {
            setState(() => _error = 'Studio connection failed. Tap to retry.');
          }
        });
  }
}
