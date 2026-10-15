import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/app_state.dart';
import '../slayhuud/slay_assets.dart';
import '../slayhuud/slay_models.dart';
import 'huud_space_models.dart';
import 'huud_avatar_motion.dart';
import 'huud_avatar_models.dart';

/// One bounded lounge, with a single shared 3D renderer for the current table.
class HuudLounge extends StatefulWidget {
  const HuudLounge(
      {super.key,
      required this.members,
      required this.onPerson,
      this.me,
      this.onGame,
      this.motion,
      this.speaking = const {}});
  final VoidCallback? onGame;
  final List<HuudMember> members;
  final String? me;
  final HuudAvatarMotion? motion;
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
    final away = widget.members.where((p) => !p.here).toList();
    final people = widget.members.where((p) => p.here).toList()
      ..sort((a, b) {
        final host = (b.host ? 1 : 0) - (a.host ? 1 : 0);
        return host != 0 ? host : (b.here ? 1 : 0) - (a.here ? 1 : 0);
      });
    final tables = (people.length / 12).ceil().clamp(1, 10000),
        table = _table.clamp(0, tables - 1),
        seated = people.skip(table * 12).take(12).toList();
    return Container(
        key: const ValueKey('huud-people-canvas'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: const Color(0xfffff0df),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xfff5c395), width: 1.5)),
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 12, 8),
              child: Row(children: [
                const Icon(Icons.weekend_rounded, color: Color(0xffb34a00)),
                const SizedBox(width: 10),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('The Huud',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xff70300c))),
                      Text('Make yourself at home',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xff9a613c))),
                    ])),
                Text('${people.where((p) => p.here).length} here',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: Color(0xffb34a00))),
              ])),
          if (tables > 1)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(
                      key: const ValueKey('huud-table-previous'),
                      tooltip: 'Previous room',
                      onPressed: table > 0
                          ? () => setState(() => _table = table - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left)),
                  Text('Room ${table + 1} of $tables',
                      style: const TextStyle(
                          color: Color(0xffb34a00),
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                  IconButton(
                      key: const ValueKey('huud-table-next'),
                      tooltip: 'Next room',
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
                                    color: Color(0xfffff0df),
                                    child: Center(
                                        child: Icon(Icons.weekend_rounded,
                                            size: 70,
                                            color: Color(0xffff8a1f))))
                                : _LoungeScene(
                                    members: seated,
                                    roomNumber: table,
                                    onGame: widget.onGame,
                                    me: widget.me,
                                    speaking: widget.speaking,
                                    motion: widget.motion,
                                    onPerson: widget.onPerson)),
                        if (people.isEmpty)
                          const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                  'Nobody is here right now. Nudge a friend to join you.')),
                        const Padding(
                            padding: EdgeInsets.fromLTRB(16, 13, 16, 8),
                            child: Text('IN THE HUUD',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.6,
                                    color: Color(0xffb34a00)))),
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
                                                            Color(0xff70300c),
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w800)),
                                              ]))),
                                ),
                            ])),
                        if (away.isNotEmpty)
                          Material(
                              color: Colors.transparent,
                              child: ExpansionTile(
                                key: const ValueKey('huud-away-members'),
                                title: Text(
                                    'Away from The Huud · ${away.length}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800)),
                                subtitle: const Text(
                                    'Tap a name to nudge them back',
                                    style: TextStyle(fontSize: 11)),
                                children: [
                                  for (final p in away)
                                    ListTile(
                                      key: ValueKey('huud-away-${p.userId}'),
                                      dense: true,
                                      leading: const Icon(
                                          Icons.person_outline_rounded),
                                      title: Text(p.handle),
                                      subtitle: const Text('Offline'),
                                      trailing: p.userId == widget.me
                                          ? null
                                          : const Icon(Icons
                                              .notifications_active_outlined),
                                      onTap: p.userId == widget.me
                                          ? null
                                          : () => widget.onPerson(p),
                                    )
                                ],
                              )),
                      ]))),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: const Color(0xffffe8d2),
              child: Text(
                  people.isEmpty
                      ? 'Invite your friends into the Huud.'
                      : 'Drag to look around · pinch to zoom · tap a name',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Color(0xff9a613c), fontSize: 11))),
        ]));
  }
}

class _LoungeScene extends StatefulWidget {
  const _LoungeScene(
      {required this.members,
      required this.speaking,
      required this.onPerson,
      required this.roomNumber,
      this.onGame,
      this.motion,
      this.me});
  final List<HuudMember> members;
  final Set<String> speaking;
  final int roomNumber;
  final VoidCallback? onGame;
  final String? me;
  final HuudAvatarMotion? motion;
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
  String _mode = 'sit';
  bool _canSit = true;
  String? _error;
  HuudAvatarOptions? _avatarOptions;
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
      _avatarOptions = HuudAvatarOptions.fromJson(jsonDecode(await rootBundle
          .loadString('assets/slay_renderer/huud-avatars.json')));
      await SlayAssets.instance.start();
      if (mounted) setState(() => _catalog = c);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The Huud could not connect. Tap to retry.');
      }
    }
  }

  List<Map<String, dynamic>> get _people => [
        for (final p in widget.members)
          {
            'id': p.userId,
            'look':
                _avatarOptions?.look(p.huudAvatarId, p.huudOutfitId)?.toJson(),
            'name': p.handle,
            'host': p.host,
            'here': p.here,
            'speaking': widget.speaking.contains(p.userId),
            'mode': widget.motion?.mode(p.userId) ??
                (p.userId == widget.me ? _mode : 'sit'),
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
        if (mounted) setState(() => _error = 'Tap to reconnect to the Huud.');
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
            'roomKey': widget.roomNumber,
            'canPlay': widget.onGame != null,
            'catalog': _catalog,
            'people': _people,
            'generation': generation,
            'reducedMotion': MediaQuery.disableAnimationsOf(context)
          });
        } catch (_) {
          if (mounted) {
            setState(() => _error = 'Tap to reconnect to the Huud.');
          }
        }
      case 'loaded':
        if (raw['generation'] != _generation) return;
        setState(() {
          _loaded = true;
          _canSit = raw['canSit'] == true;
          _booting = false;
          _error = null;
        });
        await _send({'type': 'people', 'people': _people});
        _mode = widget.me == null
            ? _mode
            : widget.motion?.mode(widget.me!) ?? _mode;
        await _send({'type': 'selfAction', 'mode': _mode});
      case 'game':
        widget.onGame?.call();
      case 'person':
        final p =
            widget.members.where((p) => p.userId == raw['id']).firstOrNull;
        if (p != null && p.userId != widget.me) widget.onPerson(p);
      case 'error':
        debugPrint('Huud renderer: ${raw['message']}');
        if (raw['generation'] != null && raw['generation'] != _generation) {
          return;
        }
        setState(() => _error = 'A character could not load. Tap to retry.');
      case 'lost':
        if (_restarts++ < 2) {
          await _restart();
        } else {
          setState(() => _error = 'The Huud paused. Tap to reconnect.');
        }
    }
  }

  @override
  void didUpdateWidget(covariant _LoungeScene old) {
    super.didUpdateWidget(old);
    if (widget.me != null) _mode = widget.motion?.mode(widget.me!) ?? _mode;
    if (_loaded) {
      unawaited(_send(old.roomNumber == widget.roomNumber
              ? {'type': 'people', 'people': _people}
              : {
                  'type': 'init',
                  'catalog': _catalog,
                  'people': _people,
                  'generation': _generation,
                  'roomKey': widget.roomNumber,
                  'canPlay': widget.onGame != null,
                  'reducedMotion': MediaQuery.disableAnimationsOf(context)
                })
          .catchError((_) {}));
      unawaited(
          _send({'type': 'selfAction', 'mode': _mode}).catchError((_) {}));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_web != null) {
      unawaited(
          _send({'type': 'pause', 'paused': state != AppLifecycleState.resumed})
              .catchError((_) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_send({'type': 'dispose'}).catchError((_) {}));
    super.dispose();
  }

  void _move(String mode) {
    setState(() => _mode = mode);
    if (widget.me != null) widget.motion?.move(widget.me!, mode);
    unawaited(_send({'type': 'selfAction', 'mode': mode}).catchError((_) {}));
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
                    'http://localhost:8187/huud-lounge.html?scene=2&catalog=${_catalog!['version']}')),
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
                      unawaited(_message(args.first as Map).catchError((_) {
                        if (mounted)
                          setState(
                              () => _error = 'Tap to reconnect to the Huud.');
                      }));
                    }
                    return null;
                  });
            },
            onConsoleMessage: (_, message) {
              if (message.messageLevel == ConsoleMessageLevel.ERROR)
                debugPrint('Huud webview: ${message.message}');
            },
            onWebContentProcessDidTerminate: (_) {
              if (_restarts++ < 2) {
                unawaited(_restart());
              } else if (mounted) {
                setState(() => _error = 'Tap to reconnect to the Huud.');
              }
            },
            onReceivedError: (_, request, error) {
              if (request.isForMainFrame == true && mounted) {
                setState(() => _error = 'Tap to reconnect to the Huud.');
              }
            },
          ),
        if (_loaded &&
            _error == null &&
            widget.members.any((p) => p.userId == widget.me && p.here))
          Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: const Color(0xfffff0df).withValues(alpha: .94),
                      borderRadius: BorderRadius.circular(18)),
                  child: Row(children: [
                    if (_canSit)
                      Expanded(
                          child: TextButton.icon(
                              key: const ValueKey('huud-sit'),
                              onPressed: () => _move('sit'),
                              icon: const Icon(Icons.weekend_rounded, size: 16),
                              label: const Text('Sit',
                                  style: TextStyle(fontSize: 11)))),
                    Expanded(
                        child: TextButton.icon(
                            key: const ValueKey('huud-stand'),
                            onPressed: () => _move('stand'),
                            icon: const Icon(Icons.accessibility_new_rounded,
                                size: 16),
                            label: const Text('Stand',
                                style: TextStyle(fontSize: 11)))),
                    Expanded(
                        child: TextButton.icon(
                            key: const ValueKey('huud-walk'),
                            onPressed: () =>
                                _move(_mode == 'walk' ? 'stand' : 'walk'),
                            icon: Icon(
                                _mode == 'walk'
                                    ? Icons.pause_rounded
                                    : Icons.directions_walk_rounded,
                                size: 16),
                            label: Text(_mode == 'walk' ? 'Stop' : 'Walk',
                                style: const TextStyle(fontSize: 11)))),
                  ]))),
        if (!_loaded || _error != null)
          ColoredBox(
              color: const Color(0xfffff0df),
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
                          Text('Opening The Huud…',
                              style: TextStyle(color: Color(0xff69856a)))
                        ]))),
      ]);
}
