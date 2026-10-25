import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/game_socket.dart';
import 'package:truearena/core/table_minimum.dart';

void main() {
  test('game ERROR frames retain codes but strip internal messages', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <WebSocket>[];
    final listener = server.listen((request) async {
      final peer = await WebSocketTransformer.upgrade(request);
      peers.add(peer);
      peer.listen((raw) {
        if ((jsonDecode(raw as String) as Map)['type'] == 'HELLO') {
          peer.add(jsonEncode({'type':'ERROR','payload':{'code':'ACTION','message':'SQL update private_table failed'}}));
        }
      });
    });
    final socket = GameSocket.connect(ApiClient()..bearer='test-token','room',baseUrl:'http://127.0.0.1:${server.port}');
    try {
      final error = await socket.envelopes.firstWhere((f) => f['type']=='ERROR').timeout(const Duration(seconds:5));
      expect(error['payload'],{'code':'ACTION','message':userRetryMessage});
    } finally {
      await socket.close();
      for (final peer in peers) { await peer.close(); }
      await listener.cancel();
      await server.close(force:true);
    }
  });

  test('a Start turned down for too few players says to add one, not to try again', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <WebSocket>[];
    final listener = server.listen((request) async {
      final peer = await WebSocketTransformer.upgrade(request);
      peers.add(peer);
      peer.listen((raw) {
        if ((jsonDecode(raw as String) as Map)['type'] == 'HELLO') {
          peer.add(jsonEncode({'type':'ERROR','payload':{'code':'NEEDS_TWO_PLAYERS','message':'Draughts is 1v1 — needs exactly 2 players'}}));
        }
      });
    });
    final socket = GameSocket.connect(ApiClient()..bearer='test-token','room',baseUrl:'http://127.0.0.1:${server.port}');
    try {
      final error = await socket.envelopes.firstWhere((f) => f['type']=='ERROR').timeout(const Duration(seconds:5));
      expect(error['payload'],{'code':'NEEDS_TWO_PLAYERS','message':tableTooSmallMessage});
    } finally {
      await socket.close();
      for (final peer in peers) { await peer.close(); }
      await listener.cancel();
      await server.close(force:true);
    }
  });

  test('reconnects and requests a fresh snapshot after a dropped socket',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final frames = <Map<String, dynamic>>[];
    var connections = 0;
    final serverSub = server.listen((request) async {
      final peer = await WebSocketTransformer.upgrade(request);
      connections++;
      final number = connections;
      peer.listen((raw) {
        final frame =
            (jsonDecode(raw as String) as Map).cast<String, dynamic>();
        frames.add(frame);
        if (frame['type'] == 'HELLO') {
          peer.add(jsonEncode({
            'type': 'SNAPSHOT',
            'payload': {'connection': number},
          }));
          if (number == 1) peer.close();
        }
      });
    });
    final api = ApiClient()..bearer = 'test-token';
    final socket = GameSocket.connect(api, 'test-room',
        baseUrl: 'http://127.0.0.1:${server.port}',
        retryBase: const Duration(milliseconds: 20));
    final received = <Map<String, dynamic>>[];
    final done = Completer<void>();
    final sub = socket.envelopes.listen((frame) {
      received.add(frame);
      if (frame['type'] == 'SNAPSHOT' &&
          (frame['payload'] as Map)['connection'] == 2 &&
          !done.isCompleted) {
        done.complete();
      }
    });
    try {
      await done.future.timeout(const Duration(seconds: 5));
      expect(connections, 2);
      expect(frames.where((f) => f['type'] == 'HELLO').length, 2);
      expect(
          received
              .where((f) => f['type'] == 'CONNECTION')
              .map((f) => (f['payload'] as Map)['connected']),
          containsAllInOrder([true, false, true]));
      expect(frames.last['payload'], {'lastSeq': 0});
    } finally {
      await socket.close();
      await sub.cancel();
      await serverSub.cancel();
      await server.close(force: true);
    }
  });

  test('reconnect HELLO carries the highest seq actually seen, not 0',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final frames = <Map<String, dynamic>>[];
    var connections = 0;
    final serverSub = server.listen((request) async {
      final peer = await WebSocketTransformer.upgrade(request);
      connections++;
      final number = connections;
      peer.listen((raw) {
        final frame =
            (jsonDecode(raw as String) as Map).cast<String, dynamic>();
        frames.add(frame);
        if (frame['type'] == 'HELLO') {
          if (number == 1) {
            // First connection: an EVENT with seq=7 arrives, then the socket drops.
            peer.add(jsonEncode({
              'type': 'EVENT',
              'payload': {'seq': 7, 'type': 'SOMETHING_HAPPENED', 'data': {}},
            }));
            peer.close();
          } else {
            peer.add(jsonEncode({
              'type': 'PHASE',
              'payload': {'connection': number}
            }));
          }
        }
      });
    });
    final api = ApiClient()..bearer = 'test-token';
    final socket = GameSocket.connect(api, 'test-room',
        baseUrl: 'http://127.0.0.1:${server.port}',
        retryBase: const Duration(milliseconds: 20));
    final done = Completer<void>();
    final sub = socket.envelopes.listen((frame) {
      if (frame['type'] == 'PHASE' && !done.isCompleted) done.complete();
    });
    try {
      await done.future.timeout(const Duration(seconds: 5));
      final hellos = frames.where((f) => f['type'] == 'HELLO').toList();
      expect(hellos.length, 2);
      expect(hellos.first['payload'],
          {'lastSeq': 0}); // fresh connection, nothing seen yet
      expect(hellos.last['payload'],
          {'lastSeq': 7}); // reconnect: replay from the last EVENT seen
      expect(socket.lastSeq, 7);
    } finally {
      await socket.close();
      await sub.cancel();
      await serverSub.cancel();
      await server.close(force: true);
    }
  });

  test('late game-screen subscriber receives the latest game snapshot',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverSub = server.listen((request) async {
      final peer = await WebSocketTransformer.upgrade(request);
      peer.listen((raw) {
        final frame =
            (jsonDecode(raw as String) as Map).cast<String, dynamic>();
        if (frame['type'] == 'HELLO') {
          peer.add(jsonEncode({
            'type': 'SNAPSHOT',
            'payload': {
              'lobby': false,
              'phase': 'playing',
              'turn': 'player-1',
            },
          }));
        }
      });
    });
    final socket = GameSocket.connect(
        ApiClient()..bearer = 'test-token', 'test-room',
        baseUrl: 'http://127.0.0.1:${server.port}');
    final lobbySawSnapshot = Completer<void>();
    final lobbySub = socket.envelopes.listen((frame) {
      if (frame['type'] == 'SNAPSHOT' && !lobbySawSnapshot.isCompleted) {
        lobbySawSnapshot.complete();
      }
    });
    try {
      await lobbySawSnapshot.future.timeout(const Duration(seconds: 5));
      await lobbySub.cancel();

      final replayed = await socket.envelopes
          .firstWhere((frame) => frame['type'] == 'SNAPSHOT')
          .timeout(const Duration(seconds: 1));
      expect((replayed['payload'] as Map)['turn'], 'player-1');
    } finally {
      await socket.close();
      await serverSub.cancel();
      await server.close(force: true);
    }
  });
}
