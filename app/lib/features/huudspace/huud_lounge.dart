import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/app_state.dart';
import '../slayhuud/slay_assets.dart';
import '../slayhuud/slay_models.dart';
import 'huud_space_models.dart';
import 'huud_avatar_motion.dart';
import 'huud_avatar_models.dart';
import 'huud_reconnect.dart';

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
  int _table = 0;

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
                  Text('Drag to look around · pinch to zoom · tap a name',
                      style: TextStyle(fontSize: 11, color: Color(0xff70300c))),
                ])),
            Text('${people.length} here',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Color(0xffb34a00))),
          ]),
        ),
        if (tables > 1)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                key: const ValueKey('huud-table-previous'),
                tooltip: 'Previous room',
                onPressed:
                    table > 0 ? () => setState(() => _table = table - 1) : null,
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
          ]),
        Expanded(
          child: Semantics(
            key: const ValueKey('huud-scene-viewport'),
            label: seated.isEmpty
                ? 'Nobody is here right now. Nudge a friend to join you.'
                : 'In The Huud: ${seated.map((p) => '${p.handle}${p.host ? ', Host' : ''}${widget.speaking.contains(p.userId) ? ', Talking now' : ''}').join('; ')}',
            customSemanticsActions: {
              for (final p in seated)
                if (p.userId != widget.me)
                  CustomSemanticsAction(label: 'Open ${p.handle}'): () =>
                      widget.onPerson(p),
            },
            child: HuudLounge.debugScenePlaceholder
                ? const ColoredBox(
                    color: Color(0xfffff0df),
                    child: Center(
                        child: Icon(Icons.weekend_rounded,
                            size: 70, color: Color(0xffff8a1f))))
                : _LoungeScene(
                    members: seated,
                    roomNumber: table,
                    onGame: widget.onGame,
                    me: widget.me,
                    speaking: widget.speaking,
                    motion: widget.motion,
                    onPerson: widget.onPerson),
          ),
        ),
        _AwayMembers(members: away, me: widget.me, onPerson: widget.onPerson),
      ]),
    );
  }
}

/// The roster stays compact until opened, and never grows beyond five rows.
class _AwayMembers extends StatefulWidget {
  const _AwayMembers({
    required this.members,
    required this.me,
    required this.onPerson,
  });
  final List<HuudMember> members;
  final String? me;
  final ValueChanged<HuudMember> onPerson;

  @override
  State<_AwayMembers> createState() => _AwayMembersState();
}

class _AwayMembersState extends State<_AwayMembers> {
  final _scroll = ScrollController();
  final _menu = MenuController();
  bool _expanded = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.members;
    final listHeight = (people.length * 48.0).clamp(0.0, 240.0);
    return LayoutBuilder(
        builder: (context, constraints) => MenuAnchor(
              controller: _menu,
              onOpen: () => setState(() => _expanded = true),
              onClose: () => setState(() => _expanded = false),
              consumeOutsideTap: true,
              style: const MenuStyle(
                padding: WidgetStatePropertyAll(EdgeInsets.zero),
                backgroundColor: WidgetStatePropertyAll(Color(0xffffdfbd)),
                surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    side: BorderSide(color: Color(0xffc08b62)))),
              ),
              menuChildren: [
                SizedBox(
                  width: constraints.maxWidth,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                          people.isEmpty
                              ? 'Everyone is here'
                              : 'Tap a name to nudge them back',
                          style: const TextStyle(
                              color: Color(0xff70300c), fontSize: 12)),
                    ),
                    SizedBox(
                        height: listHeight,
                        child: Scrollbar(
                          controller: _scroll,
                          thumbVisibility: people.length * 48 > listHeight,
                          child: ListView.builder(
                            key: const ValueKey('huud-away-scroll'),
                            controller: _scroll,
                            padding: EdgeInsets.zero,
                            itemExtent: 48,
                            itemCount: people.length,
                            itemBuilder: (_, i) {
                              final p = people[i];
                              return Semantics(
                                label: '${p.handle}, Away from The Huud',
                                button: p.userId != widget.me,
                                child: InkWell(
                                  key: ValueKey('huud-away-${p.userId}'),
                                  onTap: p.userId == widget.me
                                      ? null
                                      : () {
                                          _menu.close();
                                          widget.onPerson(p);
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14),
                                    child: Row(children: [
                                      const Icon(Icons.person_outline_rounded,
                                          color: Color(0xff70300c), size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: Text(p.handle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: Color(0xff49250e),
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 13))),
                                      const Icon(
                                          Icons.notifications_active_outlined,
                                          color: Color(0xff70300c),
                                          size: 18),
                                    ]),
                                  ),
                                ),
                              );
                            },
                          ),
                        )),
                  ]),
                ),
              ],
              builder: (context, controller, child) => Material(
                key: const ValueKey('huud-away-members'),
                color: const Color(0xffffdfbd),
                child: Semantics(
                  button: true,
                  expanded: _expanded,
                  child: InkWell(
                    key: const ValueKey('huud-away-toggle'),
                    onTap: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      child: Row(children: [
                        const Icon(Icons.people_outline_rounded,
                            size: 18, color: Color(0xff70300c)),
                        const SizedBox(width: 7),
                        const Expanded(
                            child: Text('Away from The Huud',
                                style: TextStyle(
                                    color: Color(0xff49250e),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900))),
                        Text('${people.length}',
                            style: const TextStyle(
                                color: Color(0xff49250e),
                                fontSize: 13,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(width: 8),
                        Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                            color: const Color(0xff70300c)),
                      ]),
                    ),
                  ),
                ),
              ),
            ));
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
  int _generation = 0, _viewGeneration = 0;
  late final HuudReconnect _recovery;
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
      _recovery = HuudReconnect(
          reconnect: _restart,
          onWaiting: () {
            if (mounted)
              setState(() {
                _loaded = false;
                _booting = false;
                _error = 'Reconnecting to The Huud…';
              });
          });
      _recovery.waiting();
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    try {
      final c = await SlayApi(AppScope.of(context).api)
          .catalog()
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      _avatarOptions = HuudAvatarOptions.fromJson(jsonDecode(await rootBundle
          .loadString('assets/slay_renderer/huud-avatars.json')));
      await SlayAssets.instance.start().timeout(const Duration(seconds: 10));
      if (mounted) setState(() => _catalog = c);
    } catch (_) {
      if (mounted) _recovery.failed();
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
    final web = _web;
    if (web == null) throw StateError('Huud renderer is not ready');
    await web.evaluateJavascript(
        source: 'void window.huudReceive(${jsonEncode(payload)});');
  }

  Future<void> _restart() async {
    if (!mounted) return;
    ++_generation;
    _booting = false;
    // A new WebView also recovers a dead iOS content process or lost GPU context.
    unawaited(_send({'type': 'dispose'})
        .timeout(const Duration(seconds: 2))
        .catchError((_) {}));
    _web = null;
    setState(() {
      _loaded = false;
      _error = null;
      ++_viewGeneration;
    });
    if (_catalog == null) {
      await _start();
    } else {
      await SlayAssets.instance.start().timeout(const Duration(seconds: 10));
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
          if (mounted) _recovery.failed();
        }
      case 'loaded':
        if (raw['generation'] != _generation) return;
        _recovery.connected();
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
        _recovery.failed();
      case 'lost':
        _recovery.failed();
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
          .catchError((_) {
        if (mounted) _recovery.failed();
      }));
      unawaited(_send({'type': 'selfAction', 'mode': _mode}).catchError((_) {
        if (mounted) _recovery.failed();
      }));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recovery.resume();
    } else {
      _recovery.pause();
    }
    if (_web != null) {
      unawaited(
          _send({'type': 'pause', 'paused': state != AppLifecycleState.resumed})
              .catchError((_) {
        if (mounted) _recovery.failed();
      }));
    }
  }

  @override
  void dispose() {
    _recovery.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_send({'type': 'dispose'}).catchError((_) {}));
    super.dispose();
  }

  void _move(String mode) {
    setState(() => _mode = mode);
    if (widget.me != null) widget.motion?.move(widget.me!, mode);
    unawaited(_send({'type': 'selfAction', 'mode': mode}).catchError((_) {
      if (mounted) _recovery.failed();
    }));
  }

  @override
  Widget build(BuildContext context) {
    final viewGeneration = _viewGeneration;
    return Stack(fit: StackFit.expand, children: [
      if (_catalog != null)
        InAppWebView(
          key: ValueKey('huud-web-$_viewGeneration'),
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer())
          },
          initialUrlRequest: URLRequest(
              url: WebUri(
                  'http://localhost:8187/huud-lounge.html?scene=3&catalog=${_catalog!['version']}')),
          initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              supportZoom: false,
              disableContextMenu: true,
              isInspectable: kDebugMode),
          onWebViewCreated: (web) {
            if (!mounted || viewGeneration != _viewGeneration) return;
            _web = web;
            web.addJavaScriptHandler(
                handlerName: 'huud',
                callback: (args) {
                  if (!mounted || viewGeneration != _viewGeneration)
                    return null;
                  if (args.isNotEmpty && args.first is Map) {
                    unawaited(_message(args.first as Map).catchError((_) {
                      if (mounted) _recovery.failed();
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
            if (mounted && viewGeneration == _viewGeneration)
              _recovery.failed();
          },
          onReceivedError: (_, request, error) {
            if (request.isForMainFrame == true &&
                mounted &&
                viewGeneration == _viewGeneration) _recovery.failed();
          },
          onReceivedHttpError: (_, request, error) {
            if (request.isForMainFrame == true &&
                mounted &&
                viewGeneration == _viewGeneration) _recovery.failed();
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
                child: Semantics(
                    liveRegion: true,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(
                          color: Color(0xffb34a00), strokeWidth: 2),
                      const SizedBox(height: 12),
                      Text(_error ?? 'Opening The Huud…',
                          style: const TextStyle(color: Color(0xff70300c))),
                      if (_error != null)
                        TextButton.icon(
                            onPressed: _recovery.retryNow,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry now')),
                    ])))),
    ]);
  }
}
