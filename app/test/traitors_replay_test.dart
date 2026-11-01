import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/game_socket.dart';
import 'package:truearena/features/game/game_screen.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/neon.dart' show Presence;

/// Whole Traitors games, as a player's socket received them from a real
/// server (one solo player hosting Cyber Agents, in every mode, with the
/// connection dropping and coming back), played through the game screen
/// frame by frame. A screen that throws on any of them would show players
/// the app's error box in the middle of a game.
///
/// Recorded with tools/traitors_play.mjs against a local backend: one JSON
/// frame per line, led by a META line naming the player, gzipped. The
/// host-ended-* games were recorded with END_AT, the host ending the game.
class _Socket implements GameSocket {
  @override
  final awaySince = <String, DateTime>{};
  @override
  Presence presenceOf(String userId) => Presence.here;
  @override
  final memberAvatars = <String, String?>{};
  final frames = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <({String type, Map<String, dynamic>? payload})>[];
  @override
  final ValueNotifier<Set<String>> onlinePlayers = ValueNotifier(<String>{});
  @override
  Stream<Map<String, dynamic>> get envelopes => frames.stream;
  @override
  bool get isConnected => true;
  @override
  int get lastSeq => 0;
  @override
  String get roomId => '00000000-0000-0000-0000-000000000001';
  @override
  void send(String type, [Map<String, dynamic>? payload]) => sent.add((type: type, payload: payload));
  @override
  Future<void> close() => frames.close();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  final games = Directory('test/fixtures/traitors_replays')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.jsonl') || f.path.endsWith('.jsonl.gz'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('there are recorded games to replay', () => expect(games, isNotEmpty));

  for (final file in games) {
    final name = file.uri.pathSegments.last;
    testWidgets('replays $name without the screen failing', (tester) async {
      final bytes = file.readAsBytesSync();
      final text = utf8.decode(file.path.endsWith('.gz') ? gzip.decode(bytes) : bytes);
      final lines = const LineSplitter()
          .convert(text)
          .where((l) => l.trim().isNotEmpty)
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .toList();
      final meta = (lines.first['payload'] as Map).cast<String, dynamic>();
      final self = meta['selfId'] as String;
      // The game screen opens on the first frame of the game itself; what
      // came before it belongs to the lobby.
      final start = lines.indexWhere((f) =>
          f['type'] == 'PHASE' || (f['type'] == 'SNAPSHOT' && (f['payload'] as Map)['lobby'] == false));
      expect(start, greaterThan(0), reason: 'the game never started in $name');

      // Keep each failure's full report (which widget, how big) for the message.
      final reports = <FlutterErrorDetails>[];
      final report = FlutterError.onError;
      FlutterError.onError = (details) {
        reports.add(details);
        report?.call(details);
      };
      addTearDown(() => FlutterError.onError = report);

      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final socket = _Socket();
      await tester.pumpWidget(AppScope(
        state: AppState(ApiClient(client: MockClient((_) async => http.Response('[]', 200)))),
        child: MaterialApp(
          theme: NeonTheme.dark,
          home: GameScreen(socket: socket, selfId: self, isHost: true, nicknames: const {}),
        ),
      ));

      var phases = 0;
      for (final frame in lines.skip(start)) {
        final type = frame['type'];
        if (type == 'SNAPSHOT' && (frame['payload'] as Map)['lobby'] == true) continue;
        if (type == 'PONG' || type == 'META') continue;
        if (type == 'ERROR') {
          // What GameSocket hands the screen: the player-facing wording.
          final payload = (frame['payload'] as Map).cast<String, dynamic>();
          frame['payload'] = {...payload, 'message': gameActionMessage(payload['code'])};
        }
        if (type == 'PHASE') phases++;
        socket.frames.add(frame);
        await tester.pump(const Duration(milliseconds: 60));
        final error = tester.takeException();
        if (error != null) {
          final text = jsonEncode(frame);
          final detail = reports.isEmpty ? '$error' : reports.last.toString().split('\n').take(40).join('\n');
          fail('$name: the screen failed on ${text.length > 200 ? '${text.substring(0, 200)}…' : text}\n$detail');
        }
      }
      // host-ended-*: the host ended the game for everyone partway through.
      final endedByHost = name.startsWith('host-ended');
      expect(phases, greaterThan(endedByHost ? 1 : 3), reason: '$name should play through several phases');
      // Let any opening animation and the result screen settle, then leave.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull);
      if (endedByHost) {
        expect(find.text('The host ended the game'), findsOneWidget,
            reason: '$name: everyone should land on the ended game\'s results');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
