import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';

/// One `/ws/inbox` connection — a per-user live channel, independent of any
/// game room (see `InboxRegistry`, ta-api). Two things ride it today:
/// `CallScreen` tells the server which LiveKit room it just joined/left
/// (`CALL_JOINED`/`CALL_LEFT`), and `AppState` listens for `GAME_STARTING`
/// notifications pushed to everyone else on that same call when one of them
/// spins up a game. Same envelope shape and connect/listen pattern as
/// `GameSocket`, deliberately — one less thing to learn twice.
class InboxClient {
  InboxClient._(this._channel);

  final WebSocketChannel _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _sub;

  Stream<Map<String, dynamic>> get envelopes => _controller.stream;

  static InboxClient connect(ApiClient api) {
    final wsBase = ApiClient.base.replaceFirst('http', 'ws');
    final uri = Uri.parse('$wsBase/ws/inbox?token=${api.bearer ?? ''}');
    final channel = WebSocketChannel.connect(uri);
    final client = InboxClient._(channel);
    client._sub = channel.stream.listen(
      (raw) {
        try {
          client._controller.add(jsonDecode(raw as String) as Map<String, dynamic>);
        } catch (_) {
          // malformed frame — ignore rather than crash
        }
      },
      onError: (_) => client._controller.close(),
      onDone: () => client._controller.close(),
    );
    return client;
  }

  void send(String type, [Map<String, dynamic>? payload]) {
    _channel.sink.add(jsonEncode({
      'v': 1,
      'type': type,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'payload': payload ?? const {},
    }));
  }

  Future<void> close() async {
    await _sub?.cancel();
    await _controller.close();
    await _channel.sink.close();
  }
}
