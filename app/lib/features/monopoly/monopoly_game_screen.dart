import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_state.dart';
import '../../core/api_client.dart';
import '../../core/game_socket.dart';
import '../../core/game_music.dart';
import '../../core/game_sfx.dart';
import '../../core/hangout_state.dart';
import '../../widgets/game_voice_control.dart';
import '../huudspace/leave_game.dart';
import 'monopoly_board.dart';
import 'monopoly_table.dart';

class MonopolyGameScreen extends StatefulWidget {
  const MonopolyGameScreen(
      {super.key,
      required this.socket,
      required this.selfId,
      required this.nicknames,
      required this.roomCode,
      this.spectating = false});
  final GameSocket socket;
  final String selfId, roomCode;
  final Map<String, String> nicknames;
  final bool spectating;
  @override
  State<MonopolyGameScreen> createState() => _MonopolyGameScreenState();
}

class _MonopolyGameScreenState extends State<MonopolyGameScreen> {
  StreamSubscription? _socketSub, _huudSub;
  Timer? _poll, _ticker, _pendingTimer;
  Map<String, dynamic> _state = {};
  final _input = TextEditingController();
  final _messages = <({String who, String text})>[];
  String? _huudId, _error, _voiceRoom;
  String _huudName = 'Your Huud';
  bool _connected = false,
      _liveSnapshot = false,
      _pending = false,
      _canChat = false,
      _loadingChat = false,
      _sendingChat = false,
      _started = false;
  int _seconds = 180, _watching = 0, _rollSequence = 0, _lastRollSeq = 0;
  bool _pendingRoll = false;
  List<int> _rolledDice = const [];
  String get _cacheKey =>
      'monopoly_snapshot_${widget.selfId}_${widget.socket.roomId}';
  @override
  void initState() {
    super.initState();
    HangoutState.instance.addListener(_voiceChanged);
    _connected = widget.socket.isConnected;
    _socketSub = widget.socket.envelopes.listen(_onEnvelope);
    unawaited(_restore());
    unawaited(GameMusic.start(GameMusic.moodFor('monopoly')));
    unawaited(GameSfx.warmUp());
    widget.socket.send('HELLO', {'lastSeq': 0});
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _connected && _seconds > 0 && _state['paused'] != true) {
        setState(() => _seconds--);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final app = AppScope.of(context);
    _huudSub = app.huudSpaceEvents.listen((event) {
      final data = monopolyMap(event['data']);
      if (data['huudSpaceId'] == _huudId) unawaited(_loadChat());
    });
    unawaited(_loadHuud());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_connected) {
        unawaited(_loadChat());
        if (_huudId == null) unawaited(_loadHuud());
      }
    });
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_cacheKey);
    if (!mounted || _liveSnapshot || value == null) return;
    try {
      final saved = monopolyMap(jsonDecode(value));
      setState(() {
        _state = monopolyMap(saved['state'])
          ..remove('tradeOffers')
          ..remove('legalActions');
        _huudName = saved['huudName']?.toString() ?? _huudName;
        _messages.clear();
        for (final raw in saved['messages'] as List? ?? []) {
          final m = monopolyMap(raw);
          _messages.add((
            who: m['who']?.toString() ?? '',
            text: m['text']?.toString() ?? ''
          ));
        }
      });
    } catch (_) {/* An old cache never blocks the live screen. */}
  }

  Future<void> _save() async {
    if (_state['board'] is! List) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final publicState = Map<String, dynamic>.of(_state)
        ..remove('tradeOffers')
        ..remove('legalActions');
      await prefs.setString(
          _cacheKey,
          jsonEncode({
            'state': publicState,
            'huudName': _huudName,
            'messages': _messages.reversed
                .take(80)
                .toList()
                .reversed
                .map((m) => {'who': m.who, 'text': m.text})
                .toList(),
          }));
    } catch (_) {/* A cache write failure must not interrupt a live match. */}
  }

  void _onEnvelope(Map<String, dynamic> env) {
    if (!mounted) return;
    final p = monopolyMap(env['payload']);
    switch (env['type']) {
      case 'CONNECTION':
        setState(() {
          _connected = p['connected'] == true;
          if (!_connected) {
            _liveSnapshot = false;
            _pending = false;
            _pendingRoll = false;
          }
        });
      case 'SNAPSHOT':
        if (p['board'] is List) {
          setState(() {
            _state = p;
            _connected = widget.socket.isConnected;
            _liveSnapshot = _connected;
            _pending = false;
            _pendingRoll = false;
            _error = null;
            _seconds = (p['secondsLeft'] as num?)?.toInt() ?? _seconds;
            _watching = (p['spectatorCount'] as num?)?.toInt() ?? _watching;
          });
          _pendingTimer?.cancel();
          unawaited(_save());
        } else if (p['lobby'] == true) {
          setState(() {
            _liveSnapshot = false;
            _error =
                'This match has ended. Return to your Huud to choose the next game.';
          });
        }
      case 'PHASE':
        setState(
            () => _seconds = (p['secondsLeft'] as num?)?.toInt() ?? _seconds);
      case 'ERROR':
        setState(() {
          _pending = false;
          _pendingRoll = false;
          _error = p['message']?.toString() ?? 'That action is not available';
        });
        _pendingTimer?.cancel();
      case 'EVENT':
        final data = monopolyMap(p['data']);
        final seq = (p['seq'] as num?)?.toInt() ?? 0;
        if (p['type'] == 'DICE_ROLLED' &&
            _connected &&
            _liveSnapshot &&
            (seq == 0 || seq > _lastRollSeq)) {
          final dice = (data['dice'] as List? ?? [])
              .whereType<num>()
              .map((v) => v.toInt())
              .toList();
          if (dice.length == 2) {
            setState(() {
              _lastRollSeq = seq;
              _rolledDice = dice;
              _rollSequence++;
            });
          }
        }
        if (p['type'] == 'GAME_PAUSED' || p['type'] == 'GAME_RESUMED') {
          setState(() {
            _state = Map.of(_state)..['paused'] = p['type'] == 'GAME_PAUSED';
            _seconds = (data['secondsLeft'] as num?)?.toInt() ?? _seconds;
          });
        }
        if (p['type'] == 'SPECTATOR_COUNT') {
          setState(
              () => _watching = (data['count'] as num?)?.toInt() ?? _watching);
        }
        if (p['type'] == 'CHAT_MESSAGE' && _huudId == null) {
          setState(() => _messages.add((
                who: widget.nicknames[data['from']] ?? 'Player',
                text: data['text']?.toString() ?? ''
              )));
        }
    }
  }

  Future<void> _loadHuud() async {
    try {
      final raw = monopolyMap(await AppScope.of(context)
          .api
          .get('/huud-spaces/by-room/${widget.socket.roomId}'));
      if (!mounted) return;
      setState(() {
        _huudId = raw['id']?.toString();
        _voiceRoom = raw['voiceRoom']?.toString();
        _huudName = raw['name']?.toString() ?? 'Your Huud';
        _canChat = raw['youAreIn'] == true;
        _watching = (raw['watching'] as num?)?.toInt() ?? _watching;
      });
      await _loadChat();
    } on ApiException catch (error) {
      // Only a confirmed standalone room uses room chat. A transient API
      // failure must never send a Huud conversation into an ephemeral channel.
      if (mounted && _huudId == null && error.status == 404) {
        setState(() => _canChat = !widget.spectating);
      }
    } catch (_) {
      /* The saved board remains visible while metadata reconnects. */
    }
  }

  Future<void> _loadChat() async {
    if (_huudId == null || _loadingChat) return;
    _loadingChat = true;
    try {
      final raw =
          await AppScope.of(context).api.get('/huud-spaces/$_huudId/messages');
      if (!mounted) return;
      final messages = <({String who, String text})>[];
      for (final v in raw as List) {
        final m = monopolyMap(v), from = monopolyMap(m['from']);
        messages.add((
          who: from['username']?.toString() ??
              from['displayName']?.toString() ??
              'Member',
          text: m['body']?.toString() ?? ''
        ));
      }
      setState(() => _messages
        ..clear()
        ..addAll(messages));
      unawaited(_save());
    } catch (_) {
      /* Keep recent chat visible during temporary network loss. */
    } finally {
      _loadingChat = false;
    }
  }

  Future<void> _sendChat() async {
    final text = _input.text.trim();
    if (text.isEmpty || !_canChat || !_connected || _sendingChat) return;
    _sendingChat = true;
    try {
      if (_huudId != null) {
        await AppScope.of(context)
            .api
            .post('/huud-spaces/$_huudId/messages', {'body': text});
        if (mounted) {
          if (_input.text.trim() == text) _input.clear();
          await _loadChat();
        }
      } else {
        widget.socket.send('CHAT_SEND', {'channel': 'public', 'text': text});
        _input.clear();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Error has occurred, try again later.');
      }
    } finally {
      _sendingChat = false;
    }
  }

  void _action(String action, Map<String, dynamic> data) {
    if (!_connected ||
        !_liveSnapshot ||
        _state['paused'] == true ||
        _pending ||
        widget.spectating ||
        !monopolyPlayers(_state).contains(widget.selfId)) {
      return;
    }
    setState(() {
      _pending = true;
      _pendingRoll = action == 'ROLL';
      _error = null;
    });
    if (action == 'ROLL') GameSfx.diceRoll();
    widget.socket.send('PLAYER_ACTION', {
      'action': action,
      'data': data,
      'actionId': '${widget.selfId}-${DateTime.now().microsecondsSinceEpoch}'
    });
    _pendingTimer?.cancel();
    _pendingTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _pending) {
        setState(() {
          _pending = false;
          _pendingRoll = false;
          _liveSnapshot = false;
          _error = 'Checking the latest board…';
        });
        widget.socket.send('HELLO', {'lastSeq': 0});
      }
    });
  }

  Future<void> _properties() async {
    final board = _state['board'] as List? ?? [];
    final deeds = monopolyMap(_state['deeds']);
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: monopolyCream,
        builder: (sheetContext) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .75,
                child: Column(children: [
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('PROPERTIES & BUILDINGS',
                          style: TextStyle(
                              color: monopolyInk,
                              fontSize: 20,
                              fontWeight: FontWeight.w900))),
                  Expanded(
                      child: ListView(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          children: [
                        for (final raw in board)
                          if ((monopolyMap(raw)['price'] as num? ?? 0) > 0)
                            Builder(builder: (_) {
                              final tile = monopolyMap(raw),
                                  id = (tile['id'] as num).toInt(),
                                  deed = monopolyMap(deeds['$id']);
                              final mine = deed['owner'] == widget.selfId;
                              final canManage = mine &&
                                  _connected &&
                                  _liveSnapshot &&
                                  !widget.spectating &&
                                  const {'Roll', 'Manage', 'Debt'}
                                      .contains(_state['phase']);
                              final levels = tile['rents'] as List? ?? [],
                                  buildings =
                                      (deed['buildings'] as num?)?.toInt() ?? 0;
                              return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border(
                                          top: BorderSide(
                                              color: monopolyGroupColor(
                                                  tile['group']?.toString()),
                                              width: 9))),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            tile['name']
                                                .toString()
                                                .toUpperCase(),
                                            style: const TextStyle(
                                                color: monopolyInk,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 16)),
                                        Text(
                                            '${mine ? 'YOUR DEED' : deed['owner'] == null ? 'BANK' : widget.nicknames[deed['owner']] ?? 'Player'} • Price \$${tile['price']} • ${deed['mortgaged'] == true ? 'Mortgaged' : buildings == 5 ? 'Hotel' : '$buildings houses'}',
                                            style: const TextStyle(
                                                color: monopolyInk,
                                                fontWeight: FontWeight.w700)),
                                        if (levels.isNotEmpty)
                                          Text(
                                              'Rent: \$${levels[0]} · 1 house \$${levels[1]} · 2 \$${levels[2]}\n3 houses \$${levels[3]} · 4 \$${levels[4]} · hotel \$${levels[5]}\nBuilding cost \$${tile['buildingCost']} each',
                                              style: const TextStyle(
                                                  color: monopolyInk,
                                                  fontSize: 13)),
                                        if (tile['kind'] == 'railroad')
                                          const Text(
                                              'Rent: 1 railroad \$25 · 2 \$50 · 3 \$100 · 4 \$200',
                                              style: TextStyle(
                                                  color: monopolyInk)),
                                        if (tile['kind'] == 'utility')
                                          const Text(
                                              'Rent: one utility 4× dice · both utilities 10× dice',
                                              style: TextStyle(
                                                  color: monopolyInk)),
                                        if (mine)
                                          Wrap(
                                              spacing: 7,
                                              runSpacing: 4,
                                              children: [
                                                if (tile['kind'] == 'street' &&
                                                    deed['mortgaged'] !=
                                                        true) ...[
                                                  _propertyButton(
                                                      sheetContext,
                                                      'Build',
                                                      'BUILD',
                                                      id,
                                                      canManage &&
                                                          _state['phase'] !=
                                                              'Debt' &&
                                                          buildings < 5),
                                                  if (buildings > 0) ...[
                                                    _propertyButton(
                                                        sheetContext,
                                                        'Sell one',
                                                        'SELL_BUILDING',
                                                        id,
                                                        canManage),
                                                    _propertyButton(
                                                        sheetContext,
                                                        'Sell group',
                                                        'SELL_GROUP',
                                                        id,
                                                        canManage)
                                                  ]
                                                ],
                                                _propertyButton(
                                                    sheetContext,
                                                    deed['mortgaged'] == true
                                                        ? 'Redeem \$${((tile['price'] as num).toInt() ~/ 2) + (((tile['price'] as num).toInt() ~/ 2 + 9) ~/ 10)}'
                                                        : 'Mortgage \$${(tile['price'] as num).toInt() ~/ 2}',
                                                    deed['mortgaged'] == true
                                                        ? 'UNMORTGAGE'
                                                        : 'MORTGAGE',
                                                    id,
                                                    canManage),
                                              ]),
                                      ]));
                            })
                      ])),
                  if (_state['phase'] == 'Debt' &&
                      _state['decisionPlayer'] == widget.selfId)
                    TextButton(
                        onPressed: () => _confirmBankruptcy(sheetContext),
                        child: const Text('Declare bankruptcy',
                            style: TextStyle(
                                color: monopolyWine,
                                fontWeight: FontWeight.w800))),
                ]))));
  }

  Widget _propertyButton(BuildContext sheet, String label, String action,
          int id, bool enabled) =>
      FilledButton(
          onPressed: enabled
              ? () {
                  Navigator.pop(sheet);
                  _action(action, {'property': id});
                }
              : null,
          style: FilledButton.styleFrom(
              backgroundColor: monopolyWine,
              foregroundColor: monopolyCream,
              textStyle: const TextStyle(fontWeight: FontWeight.w800)),
          child: Text(label));
  Future<void> _confirmBankruptcy(BuildContext sheet) async {
    final yes = await showDialog<bool>(
        context: sheet,
        builder: (dialog) => AlertDialog(
                title: const Text('Declare bankruptcy?'),
                content: const Text(
                    'This ends your place in this match. You remain in the Huud. The bank will first check that your assets cannot cover the debt.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Keep playing')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Declare'))
                ]));
    if (yes == true && sheet.mounted) {
      Navigator.pop(sheet);
      _action('BANKRUPT', {});
    }
  }

  Future<void> _trade() async {
    final people = monopolyMap(_state['playerState']);
    final others = monopolyPlayers(_state)
        .where((id) =>
            id != widget.selfId && monopolyMap(people[id])['bankrupt'] != true)
        .toList();
    if (others.isEmpty) return;
    String to = others.first;
    final giveCash = TextEditingController(text: '0'),
        takeCash = TextEditingController(text: '0');
    final give = <int>{}, take = <int>{};
    final board = _state['board'] as List? ?? [],
        deeds = monopolyMap(_state['deeds']);
    final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: monopolyCream,
        builder: (sheet) => StatefulBuilder(
            builder: (context, setSheet) => SafeArea(
                child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16,
                        MediaQuery.viewInsetsOf(context).bottom + 16),
                    child: SizedBox(
                        height: MediaQuery.sizeOf(context).height * .62,
                        child: ListView(children: [
                          const Text('MAKE A TRADE',
                              style: TextStyle(
                                  color: monopolyInk,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900)),
                          DropdownButton<String>(
                              value: to,
                              isExpanded: true,
                              items: others
                                  .map((id) => DropdownMenuItem(
                                      value: id,
                                      child: Text(
                                          widget.nicknames[id] ?? 'Player',
                                          style: const TextStyle(
                                              color: monopolyInk,
                                              fontWeight: FontWeight.w800))))
                                  .toList(),
                              onChanged: (id) {
                                if (id != null) {
                                  setSheet(() {
                                    to = id;
                                    take.clear();
                                  });
                                }
                              }),
                          Row(children: [
                            Expanded(
                                child: TextField(
                                    controller: giveCash,
                                    style: const TextStyle(color: monopolyInk),
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                        labelText: 'You give cash',
                                        labelStyle: TextStyle(
                                            color: monopolyInk,
                                            fontWeight: FontWeight.w700),
                                        prefixText: '\$'))),
                            const SizedBox(width: 14),
                            Expanded(
                                child: TextField(
                                    controller: takeCash,
                                    style: const TextStyle(color: monopolyInk),
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                        labelText: 'You receive cash',
                                        labelStyle: TextStyle(
                                            color: monopolyInk,
                                            fontWeight: FontWeight.w700),
                                        prefixText: '\$')))
                          ]),
                          for (final owner in [widget.selfId, to]) ...[
                            Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Text(
                                    owner == widget.selfId
                                        ? 'YOUR DEEDS'
                                        : 'THEIR DEEDS',
                                    style: const TextStyle(
                                        color: monopolyInk,
                                        fontWeight: FontWeight.w900))),
                            for (final raw in board)
                              if (deeds['${monopolyMap(raw)['id']}'] is Map &&
                                  monopolyMap(deeds[
                                              '${monopolyMap(raw)['id']}'])[
                                          'owner'] ==
                                      owner)
                                Builder(builder: (_) {
                                  final tile = monopolyMap(raw),
                                      id = (tile['id'] as num).toInt(),
                                      selection =
                                          owner == widget.selfId ? give : take;
                                  return CheckboxListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      value: selection.contains(id),
                                      activeColor: monopolyWine,
                                      title: Text(tile['name'].toString(),
                                          style: const TextStyle(
                                              color: monopolyInk,
                                              fontWeight: FontWeight.w700)),
                                      onChanged: (yes) => setSheet(() {
                                            if (yes == true) {
                                              selection.add(id);
                                            } else {
                                              selection.remove(id);
                                            }
                                          }));
                                }),
                          ],
                          const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                  'Sell a colour group’s buildings before trading its deeds. A recipient pays 10% interest on each mortgaged deed.',
                                  style: TextStyle(
                                      color: monopolyInk, fontSize: 12))),
                          FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: monopolyWine,
                                  foregroundColor: monopolyCream,
                                  minimumSize: const Size(0, 48)),
                              onPressed: () {
                                final g = int.tryParse(giveCash.text),
                                    t = int.tryParse(takeCash.text);
                                if (g != null &&
                                    t != null &&
                                    g >= 0 &&
                                    t >= 0) {
                                  Navigator.pop(sheet, {
                                    'to': to,
                                    'giveCash': g,
                                    'takeCash': t,
                                    'giveDeeds': give.toList(),
                                    'takeDeeds': take.toList()
                                  });
                                }
                              },
                              child: const Text('Send private offer',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w900))),
                        ]))))));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    giveCash.dispose();
    takeCash.dispose();
    if (result != null && mounted) _action('OFFER_TRADE', result);
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    HangoutState.instance.removeListener(_voiceChanged);
    _socketSub?.cancel();
    _huudSub?.cancel();
    _poll?.cancel();
    _ticker?.cancel();
    _pendingTimer?.cancel();
    _input.dispose();
    widget.socket.close();
    unawaited(GameMusic.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xff221815),
      body: SafeArea(
          child: MonopolyTable(
        speaking:
            _voiceRoom != null && HangoutState.instance.roomName == _voiceRoom
                ? HangoutState.instance.participants
                    .where((p) => p.isSpeaking)
                    .map((p) => p.identity)
                    .toSet()
                : const {},
        state: _state,
        rollPending: _pendingRoll,
        rollSequence: _rollSequence,
        rolledDice: _rolledDice,
        selfId: widget.selfId,
        names: widget.nicknames,
        huudName: _huudName,
        watching: _watching,
        seconds: _seconds,
        error: _error == null ? null : userErrorMessage,
        connected: _connected && _liveSnapshot,
        pending: _pending,
        spectating: widget.spectating,
        canChat: _canChat,
        chatController: _input,
        messages: _messages,
        onAction: _action,
        onProperties: _properties,
        musicEnabled: GameMusic.enabled,
        soundsEnabled: GameSfx.enabled,
        onToggleMusic: () async {
          await GameMusic.setEnabled(!GameMusic.enabled);
          if (mounted) setState(() {});
        },
        onToggleSounds: () async {
          await GameSfx.setEnabled(!GameSfx.enabled);
          if (mounted) setState(() {});
        },
        onPause: () => widget.socket.send('PAUSE_TOGGLE', {}),
        onTrade: _trade,
        onSendChat: _sendChat,
        onBack: () => leaveGame(context, widget.socket.roomId),
        voice: GameVoiceControl(
            socket: widget.socket,
            roomId: widget.socket.roomId,
            selfId: widget.selfId,
            nicknames: widget.nicknames,
            spectating: widget.spectating),
      )));
}
