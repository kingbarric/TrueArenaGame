import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// App-scoped voice ownership. Routes and games never dispose this connection.
class HangoutState extends ChangeNotifier {
  static final instance = HangoutState();
  final navigationKey = GlobalKey<NavigatorState>();
  Widget? screen;
  String? roomName;
  String title = '';
  bool expanded = true;
  bool muted = false;
  lk.Room? room;
  final Map<String, String?> avatars = {};
  String? ownerId;
  Map<String, dynamic>? session;
  Future<void> Function()? toggleMute;
  Future<void> Function()? leave;
  Future<void> Function()? play;
  bool get active => screen != null;
  List<lk.Participant> get participants => [
        if (room?.localParticipant != null) room!.localParticipant!,
        ...?room?.remoteParticipants.values,
      ];
  List<String> get speaking => participants
      .where((p) => p.isSpeaking)
      .map((p) => p.name.isEmpty ? p.identity : p.name)
      .toList();

  void open(Widget next, String name, String label) {
    screen = next;
    roomName = name;
    title = label;
    expanded = true;
    notifyListeners();
  }

  void attach(lk.Room? next) {
    room?.removeListener(changed);
    room = next;
    next?.addListener(changed);
    changed();
  }

  void changed() => notifyListeners();
  void minimize() {
    expanded = false;
    changed();
  }

  void show() {
    expanded = true;
    changed();
  }

  void clear() {
    room?.removeListener(changed);
    room = null;
    screen = null;
    roomName = null;
    muted = false;
    avatars.clear();
    ownerId = null;
    session = null;
    leave = null;
    toggleMute = null;
    play = null;
    changed();
  }
}
