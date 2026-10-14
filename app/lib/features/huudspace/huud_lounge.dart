import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/app_state.dart';
import '../slayhuud/slay_assets.dart';
import '../slayhuud/slay_models.dart';
import 'huud_space_models.dart';

/// One bounded lounge, with a single shared 3D renderer for the current table.
class HuudLounge extends StatefulWidget {
  const HuudLounge(
      {super.key,
      required this.members,
      required this.onPerson,
      this.me,
      this.speaking = const {}});
  final List<HuudMember> members;
  final String? me;
  final Set<String> speaking;
  final ValueChanged<HuudMember> onPerson;
  @visibleForTesting
  static bool debugScenePlaceholder = false;
  @override
  State<HuudLounge> createState() => _HuudLoungeState();
}

class _HuudLoungeState extends State<HuudLounge> {
  final _scroll = ScrollController();
  int _table = 0;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = [...widget.members]..sort((a, b) {
        final host = (b.host ? 1 : 0) - (a.host ? 1 : 0);
        return host != 0 ? host : (b.here ? 1 : 0) - (a.here ? 1 : 0);
      });
    final tables = (people.length / 8).ceil().clamp(1, 10000),
        table = _table.clamp(0, tables - 1),
        seated = people.skip(table * 8).take(8).toList();
    return Container(
        key: const ValueKey('huud-people-canvas'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: const Color(0xfff5efdf),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xffd9d2bf), width: 1.5)),
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 12, 8),
              child: Row(children: [
                const Icon(Icons.weekend_rounded, color: Color(0xff55785f)),
                const SizedBox(width: 10),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('The lounge',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xff304b39))),
                      Text('Pull up a chair',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xff7b8472))),
                    ])),
                Text('${people.where((p) => p.here).length} here',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: Color(0xff55785f))),
              ])),
          if (tables > 1)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(
                      key: const ValueKey('huud-table-previous'),
                      tooltip: 'Previous table',
                      onPressed: table > 0
                          ? () => setState(() => _table = table - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left)),
                  Text('Table ${table + 1} of $tables',
                      style: const TextStyle(
                          color: Color(0xff55785f),
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                  IconButton(
                      key: const ValueKey('huud-table-next'),
                      tooltip: 'Next table',
                      onPressed: table + 1 < tables
                          ? () => setState(() => _table = table + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right)),
                ])),
          Expanded(
              child: Scrollbar(
                  controller: _scroll,
                  child: ListView(
                      key: const ValueKey('huud-lounge-scroll'),
                      controller: _scroll,
                      padding: EdgeInsets.zero,
                      children: [
                        AspectRatio(
                            aspectRatio: 1.04,
                            child: HuudLounge.debugScenePlaceholder
                                ? const ColoredBox(
                                    color: Color(0xffe8e3d5),
                                    child: Center(
                                        child: Icon(Icons.weekend_rounded,
                                            size: 70,
                                            color: Color(0xff8ca18b))))
                                : _LoungeScene(
                                    members: seated,
                                    me: widget.me,
                                    speaking: widget.speaking,
                                    onPerson: widget.onPerson)),
                        const Padding(
                            padding: EdgeInsets.fromLTRB(16, 13, 16, 8),
                            child: Text('AROUND THE TABLE',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.6,
                                    color: Color(0xff78836e)))),
                        Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                            child: Wrap(spacing: 7, runSpacing: 8, children: [
                              for (final p in seated)
                                Semantics(
                                  button: p.userId != widget.me,
                                  label:
                                      '${p.handle}, ${p.host ? 'Host, ' : ''}${p.here ? 'Here now' : 'Away'}${widget.speaking.contains(p.userId) ? ', Talking now' : ''}',
                                  selected: false,
                                  child: GestureDetector(
                                      key: ValueKey('huud-person-${p.userId}'),
                                      onTap: p.userId == widget.me
                                          ? null
                                          : () => widget.onPerson(p),
                                      child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 11, vertical: 8),
                                          decoration: BoxDecoration(
                                              color: widget.speaking
                                                      .contains(p.userId)
                                                  ? const Color(0xffe1f0dc)
                                                  : const Color(0xfffffaf0),
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                              border: Border.all(
                                                  color: widget.speaking
                                                          .contains(p.userId)
                                                      ? const Color(0xff74a77b)
                                                      : const Color(
                                                          0xffded6c1))),
                                          child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (widget.speaking
                                                    .contains(p.userId))
                                                  Icon(Icons.graphic_eq_rounded,
                                                      key: ValueKey(
                                                          'huud-speaker-${p.userId}'),
                                                      size: 16,
                                                      color: const Color(
                                                          0xff3a8652))
                                                else
                                                  Container(
                                                      width: 6,
                                                      height: 6,
                                                      decoration: BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                          color: p.here
                                                              ? const Color(
                                                                  0xff6c9572)
                                                              : const Color(
                                                                  0xffb1b5a7))),
                                                const SizedBox(width: 6),
                                                Text(
                                                    '${p.host ? '♛ ' : ''}${p.userId == widget.me ? 'You' : p.handle}',
                                                    style: const TextStyle(
                                                        color:
                                                            Color(0xff38513f),
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w800)),
                                              ]))),
                                ),
                            ])),
                      ]))),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: const Color(0xffece7d7),
              child: Text(
                  people.isEmpty
                      ? 'Invite your friends to take a seat.'
                      : 'Drag to look around · pinch to zoom · tap a name',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Color(0xff76806c), fontSize: 11))),
        ]));
  }
}

class _LoungeScene extends StatefulWidget {
  const _LoungeScene(
      {required this.members,
      required this.speaking,
      required this.onPerson,
      this.me});
  final List<HuudMember> members;
  final Set<String> speaking;
  final String? me;
  final ValueChanged<HuudMember> onPerson;
  @override
  State<_LoungeScene> createState() => _LoungeSceneState();
}

class _LoungeSceneState extends State<_LoungeScene>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _catalog;
  InAppWebViewController? _web;
  bool _started = false, _loaded = false, _booting = false;
  int _generation = 0, _restarts = 0;
  String? _error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addObserver(this);
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    try {
      final c = await SlayApi(AppScope.of(context).api).catalog();
      await SlayAssets.instance.start();
      if (mounted) setState(() => _catalog = c);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The lounge could not connect. Tap to retry.');
      }
    }
  }

  List<Map<String, dynamic>> get _people => [
        for (final p in widget.members)
          {
            'id': p.userId,
            'name': p.handle,
            'host': p.host,
            'here': p.here,
            'speaking': widget.speaking.contains(p.userId),
            'me': p.userId == widget.me
          }
      ];
  Future<void> _send(Map<String, dynamic> payload) async {
    await _web?.evaluateJavascript(
        source: 'void window.huudReceive(${jsonEncode(payload)});');
  }

  Future<void> _restart() async {
    if (!mounted) return;
    ++_generation;
    _booting = false;
    setState(() {
      _loaded = false;
      _error = null;
    });
    if (_catalog == null) {
      await _start();
    } else {
      try {
        await _web?.reload();
      } catch (_) {
        if (mounted) setState(() => _error = 'Tap to reconnect to the lounge.');
      }
    }
  }

  Future<void> _message(Map raw) async {
    if (!mounted) return;
    switch (raw['type']) {
      case 'ready':
        if (_booting || _catalog == null) return;
        _booting = true;
        final generation = ++_generation;
        try {
          await _send({
            'type': 'init',
            'catalog': _catalog,
            'people': _people,
            'generation': generation,
            'reducedMotion': MediaQuery.disableAnimationsOf(context)
          });
        } catch (_) {
          if (mounted) {
            setState(() => _error = 'Tap to reconnect to the lounge.');
          }
        }
      case 'loaded':
        if (raw['generation'] != _generation) return;
        setState(() {
          _loaded = true;
          _booting = false;
          _error = null;
        });
        await _send({'type': 'people', 'people': _people});
      case 'person':
        final p =
            widget.members.where((p) => p.userId == raw['id']).firstOrNull;
        if (p != null && p.userId != widget.me) widget.onPerson(p);
      case 'error':
        if (raw['generation'] != null && raw['generation'] != _generation) {
          return;
        }
        setState(() => _error = 'A character could not load. Tap to retry.');
      case 'lost':
        if (_restarts++ < 2) {
          await _restart();
        } else {
          setState(() => _error = 'The lounge paused. Tap to reconnect.');
        }
    }
  }

  @override
  void didUpdateWidget(covariant _LoungeScene old) {
    super.didUpdateWidget(old);
    if (_loaded) unawaited(_send({'type': 'people', 'people': _people}).catchError((_) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_web != null) {
      unawaited(_send(
          {'type': 'pause', 'paused': state != AppLifecycleState.resumed}).catchError((_) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_send({'type': 'dispose'}).catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        if (_catalog != null)
          InAppWebView(
            gestureRecognizers: {
              Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer())
            },
            initialUrlRequest: URLRequest(
                url: WebUri(
                    'http://localhost:8187/huud-lounge.html?scene=1&catalog=${_catalog!['version']}')),
            initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                supportZoom: false,
                disableContextMenu: true,
                isInspectable: kDebugMode),
            onWebViewCreated: (web) {
              _web = web;
              web.addJavaScriptHandler(
                  handlerName: 'huud',
                  callback: (args) {
                    if (args.isNotEmpty && args.first is Map) {
                      unawaited(_message(args.first as Map));
                    }
                    return null;
                  });
            },
            onWebContentProcessDidTerminate: (_) {
              if (_restarts++ < 2) {
                unawaited(_restart());
              } else if (mounted)
                setState(() => _error = 'Tap to reconnect to the lounge.');
            },
            onReceivedError: (_, request, error) {
              if (request.isForMainFrame == true && mounted) {
                setState(() => _error = 'Tap to reconnect to the lounge.');
              }
            },
          ),
        if (!_loaded || _error != null)
          ColoredBox(
              color: const Color(0xffe8e3d5),
              child: Center(
                  child: _error != null
                      ? TextButton.icon(
                          onPressed: () {
                            _restarts = 0;
                            _restart();
                          },
                          icon: const Icon(Icons.refresh),
                          label: Text(_error!))
                      : const Column(mainAxisSize: MainAxisSize.min, children: [
                          CircularProgressIndicator(
                              color: Color(0xff69856a), strokeWidth: 2),
                          SizedBox(height: 12),
                          Text('Setting the table…',
                              style: TextStyle(color: Color(0xff69856a)))
                        ]))),
      ]);
}
