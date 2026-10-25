import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Ephemeral avatar posture, scoped to the existing Huud voice connection.
/// The authenticated LiveKit sender determines whose avatar may change.
class HuudAvatarMotion extends ChangeNotifier {
  static const topic = 'huud-avatar-v1';
  final Map<String, String> _modes = {};
  bool _disposed = false;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;
  String mode(String id) => _modes[id] ?? 'sit';
  Map<String, String> get modes => Map.unmodifiable(_modes);

  void attach(lk.Room? room) {
    if (_disposed || identical(_room, room)) return;
    unawaited(_events?.dispose());
    _room = room;
    _modes.clear();
    _events = room?.createListener()
      ?..on<lk.DataReceivedEvent>((event) {
        if (_disposed ||
            !identical(_room, room) ||
            event.topic != topic ||
            event.participant == null ||
            event.data.length > 128) {
          return;
        }
        try {
          final data = jsonDecode(utf8.decode(event.data));
          if (data is! Map) return;
          if (data['request'] == true) {
            unawaited(_publish(destination: event.participant!.identity));
          } else {
            receive(event.participant!.identity, data);
          }
        } catch (_) {/* Ignore malformed or unrelated room data. */}
      })
      ..on<lk.ParticipantConnectedEvent>((event) =>
          unawaited(_publish(destination: event.participant.identity)))
      ..on<lk.ParticipantDisconnectedEvent>((event) {
        if (!_disposed &&
            identical(_room, room) &&
            _modes.remove(event.participant.identity) != null) {
          notifyListeners();
        }
      });
    if (room != null) {
      unawaited(_send({'request': true}));
      unawaited(_publish());
    }
  }

  @visibleForTesting
  void receive(String authenticatedSender, Map data) {
    if (_disposed) return;
    final next = data['mode'];
    if (authenticatedSender.isEmpty ||
        !const ['sit', 'stand', 'walk'].contains(next)) {
      return;
    }
    if (_modes[authenticatedSender] == next) return;
    _modes[authenticatedSender] = next as String;
    notifyListeners();
  }

  void move(String id, String mode) {
    receive(id, {'mode': mode});
    if (_room?.localParticipant?.identity == id) unawaited(_publish());
  }

  Future<void> _publish({String? destination}) async {
    final id = _room?.localParticipant?.identity;
    if (id != null) await _send({'mode': mode(id)}, destination: destination);
  }

  Future<void> _send(Map<String, dynamic> data, {String? destination}) async {
    try {
      await _room?.localParticipant?.publishData(utf8.encode(jsonEncode(data)),
          reliable: true,
          topic: topic,
          destinationIdentities: destination == null ? null : [destination]);
    } catch (_) {/* Voice reconnection must not break local avatar controls. */}
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events?.dispose());
    _room = null;
    super.dispose();
  }
}
