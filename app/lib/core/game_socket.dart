import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/widgets.dart';

import 'api_client.dart';
import 'keep_awake.dart';
import '../widgets/neon.dart' show Presence;

/// A room connection that survives short network outages. A reconnect sends
/// the highest event `seq` this socket has actually seen, so the server can
/// replay just what was missed instead of resending a full snapshot every
/// time — see `GameOrchestrator.handleHello` (`lastSeq > 0` branch) for the
/// server side of this contract. The very first connection (and any
/// reconnect before an EVENT frame has ever arrived) still gets a full
/// snapshot, since there's nothing to replay from yet.
class GameSocket {
  GameSocket._(this._api, this._roomId, this._spectate, this._baseUrl, this._retryBase);

  final ApiClient _api;
  final String _roomId;
  final bool _spectate;
  final String _baseUrl;
  final Duration _retryBase;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final ValueNotifier<Set<String>> onlinePlayers = ValueNotifier(<String>{});
  final _agentIds = <String>{};
  final memberAvatars = <String, String?>{};

  /// When each player stepped away from the game (app in the background or
  /// disconnected). Gone 5 minutes or more reads as offline.
  final awaySince = <String, DateTime>{};
  static const offlineAfter = Duration(minutes: 5);
  Timer? _presenceClock;
  _AwayWatcher? _awayWatcher;

  /// Green in the game, amber stepped away, grey gone a while (or never came).
  Presence presenceOf(String userId) {
    if (_agentIds.contains(userId)) return Presence.here;
    final away = awaySince[userId];
    if (away != null) {
      return DateTime.now().difference(away) >= offlineAfter ? Presence.offline : Presence.away;
    }
    return onlinePlayers.value.contains(userId) ? Presence.here : Presence.offline;
  }

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _retry;
  Timer? _heartbeat;
  DateTime? _lastPong;
  bool _closed = false;
  bool _connected = false;
  int _attempt = 0;
  int _generation = 0;
  int _lastSeq = 0;
  Map<String, dynamic>? _latestGameSnapshot;

  /// New game screens can attach after the lobby has already received the
  /// first authoritative game snapshot. Replay that one frame to late
  /// subscribers so the board never waits blank for a second network round
  /// trip. Lobby snapshots are deliberately not cached: replaying one after a
  /// game starts would make the game screen think the match disappeared.
  Stream<Map<String, dynamic>> get envelopes => Stream.multi((listener) {
        final sub = _controller.stream.listen(
          listener.add,
          onError: listener.addError,
          onDone: listener.close,
        );
        final snapshot = _latestGameSnapshot;
        if (snapshot != null) listener.add(snapshot);
        listener.onCancel = sub.cancel;
      }, isBroadcast: true);
  bool get isConnected => _connected && !_closed;
  int get lastSeq => _lastSeq;
  String get roomId => _roomId;

  /// The room whose lobby or game is on screen right now, as a player —
  /// the screen to come back to if the app is closed here. Lobby and game
  /// screens hold a player socket exactly while they're open; watching
  /// doesn't count.
  static final currentPlayerRoom = ValueNotifier<String?>(null);
  static final List<GameSocket> _playerSockets = [];

  static void _track() => currentPlayerRoom.value = _playerSockets.isEmpty ? null : _playerSockets.last._roomId;

  static GameSocket connect(ApiClient api, String roomId,
      {bool spectate = false, String baseUrl = ApiClient.base, Duration retryBase = const Duration(seconds: 1)}) {
    final socket = GameSocket._(api, roomId, spectate, baseUrl, retryBase);
    if (!spectate) {
      _playerSockets.add(socket);
      _track();
    }
    socket._loadAgentIds();
    socket._open();
    if (!spectate) socket._awayWatcher = _AwayWatcher(socket)..start();
    // Amber turns grey on its own after five minutes — redraw now and then.
    socket._presenceClock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (socket.awaySince.isNotEmpty && !socket._closed) {
        socket.onlinePlayers.value = {...socket.onlinePlayers.value};
      }
    });
    // In a game the screen stays on, so nobody's phone sleeps mid-turn.
    KeepAwake.hold(socket);
    return socket;
  }

  /// Room details identify system agents while a socket reconnects, including
  /// when the app reopens directly into a running game without its lobby.
  Future<void> _loadAgentIds() async {
    try {
      final room = await _api.get('/rooms/$_roomId') as Map;
      if (_closed) return;
      _readAvatars(room['members']);
      _agentIds.addAll((room['members'] as List? ?? const [])
          .whereType<Map>()
          .where((member) => member['isBot'] == true)
          .map((member) => member['userId'].toString()));
      onlinePlayers.value = {...onlinePlayers.value, ..._agentIds};
    } catch (_) {
      // A lobby snapshot may still provide the roster over the socket.
    }
  }

  Uri get _uri {
    final base = _baseUrl.replaceFirst('http', 'ws');
    return Uri.parse('$base/ws/room/$_roomId').replace(queryParameters: {
      'token': _api.bearer ?? '',
      if (_spectate) 'spectate': 'true',
    });
  }

  void _status(bool connected) {
    if (!_closed && !_controller.isClosed) {
      _controller.add({
        'type': 'CONNECTION',
        'payload': {'connected': connected}
      });
    }
  }

  Future<void> _open() async {
    if (_closed) return;
    final generation = ++_generation;
    final channel = WebSocketChannel.connect(_uri);
    _channel = channel;
    _sub = channel.stream.listen((raw) {
      if (_closed || generation != _generation) return;
      try {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        _updatePresence(frame);
        if (frame['type'] == 'PONG') _lastPong = DateTime.now();
        if (frame['type'] == 'EVENT') {
          final seq = (frame['payload'] as Map?)?['seq'] as num?;
          if (seq != null && seq.toInt() > _lastSeq) _lastSeq = seq.toInt();
        }
        if (frame['type'] == 'SNAPSHOT' && (frame['payload'] as Map?)?['lobby'] == false) {
          _latestGameSnapshot = frame;
        }
        _controller.add(frame);
      } catch (_) {
        // A malformed frame must not terminate the room connection.
      }
    }, onError: (_) => _lost(generation), onDone: () => _lost(generation));
    try {
      await channel.ready;
      if (_closed || generation != _generation) return;
      _connected = true;
      _attempt = 0;
      _lastPong = DateTime.now();
      _status(true);
      send('HELLO', {'lastSeq': _lastSeq});
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!_connected) return;
        if (DateTime.now().difference(_lastPong!) > const Duration(seconds: 30)) {
          _lost(generation);
        } else {
          send('PING');
        }
      });
    } catch (_) {
      _lost(generation);
    }
  }

  void _readAvatars(Object? members) {
    for (final member in (members as List? ?? const []).whereType<Map>()) {
      memberAvatars[member['userId'].toString()] = member['avatarUrl'] as String?;
    }
  }

  void _updatePresence(Map<String, dynamic> frame) {
    final payload = (frame['payload'] as Map?)?.cast<String, dynamic>();
    if (frame['type'] == 'SNAPSHOT' && payload != null) {
      if (payload['members'] is List) {
        _readAvatars(payload['members']);
        _agentIds.addAll((payload['members'] as List)
            .whereType<Map>()
            .where((member) => member['isBot'] == true)
            .map((member) => member['userId'].toString()));
      }
      final away = (payload['awaySince'] as Map?)?.cast<String, dynamic>();
      if (away != null) {
        awaySince
          ..clear()
          ..addAll({
            for (final e in away.entries)
              if (e.value is num) e.key: DateTime.fromMillisecondsSinceEpoch((e.value as num).toInt()),
          });
      }
      final ids = payload['connectedPlayers'] as List?;
      if (ids != null) {
        onlinePlayers.value = {...ids.map((id) => id.toString()), ..._agentIds};
      } else if (payload['members'] is List) {
        onlinePlayers.value = (payload['members'] as List)
            .whereType<Map>()
            .where((member) => member['connectionStatus'] == 'connected' || member['isBot'] == true)
            .map((member) => member['userId'].toString())
            .toSet();
      }
    } else if (frame['type'] == 'EVENT' && payload != null) {
      final type = payload['type'];
      const presenceEvents = {'MEMBER_CONNECTED', 'MEMBER_DISCONNECTED', 'MEMBER_AWAY', 'MEMBER_BACK'};
      if (!presenceEvents.contains(type)) return;
      final data = payload['data'] as Map?;
      final id = data?['userId']?.toString();
      if (id == null) return;
      final at =
          data?['at'] is num ? DateTime.fromMillisecondsSinceEpoch((data!['at'] as num).toInt()) : DateTime.now();
      final next = {...onlinePlayers.value};
      switch (type) {
        case 'MEMBER_CONNECTED':
          next.add(id);
          awaySince.remove(id);
        case 'MEMBER_DISCONNECTED':
          if (!_agentIds.contains(id)) next.remove(id);
          awaySince.putIfAbsent(id, () => at);
        case 'MEMBER_AWAY':
          awaySince.putIfAbsent(id, () => at);
        case 'MEMBER_BACK':
          awaySince.remove(id);
      }
      onlinePlayers.value = next;
    }
  }

  void _lost(int generation) {
    if (_closed || generation != _generation) return;
    final unauthorized = _channel?.closeCode == 4401;
    _generation++;
    _connected = false;
    onlinePlayers.value = {..._agentIds};
    _heartbeat?.cancel();
    _status(false);
    _sub?.cancel();
    _channel?.sink.close();
    final factor = math.min(30, 1 << math.min(_attempt++, 5));
    _retry?.cancel();
    _retry = Timer(_retryBase * factor, () async {
      if (unauthorized) {
        try {
          await _api.refreshHandler?.call();
        } catch (_) {
          // The next attempt can still succeed after a later sign-in.
        }
      }
      if (!_closed) _open();
    });
  }

  /// Actions sent while offline are discarded; replaying a move after a
  /// reconnect could apply it to a different turn. The fresh snapshot lets
  /// the player make the decision again against current state.
  void send(String type, [Map<String, dynamic>? payload]) {
    if (_closed || !_connected) return;
    try {
      _channel?.sink.add(jsonEncode({
        'v': 1,
        'type': type,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'payload': payload ?? const {},
      }));
    } catch (_) {
      _lost(_generation);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    KeepAwake.release(this);
    _presenceClock?.cancel();
    _awayWatcher?.stop();
    if (_playerSockets.remove(this)) _track();
    _generation++;
    _retry?.cancel();
    _heartbeat?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    await _controller.close();
    onlinePlayers.dispose();
  }
}

/// Tells the room when this phone leaves the game (app to the background)
/// and when it comes back, so the others see amber rather than green.
class _AwayWatcher with WidgetsBindingObserver {
  _AwayWatcher(this._socket);
  final GameSocket _socket;

  void start() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // No app lifecycle to watch (plain unit tests).
    }
  }

  void stop() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _socket.send('PRESENCE', {'away': true});
    } else if (state == AppLifecycleState.resumed) {
      _socket.send('PRESENCE', {'away': false});
    }
  }
}
