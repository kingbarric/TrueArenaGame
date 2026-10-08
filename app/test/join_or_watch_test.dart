import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/lobby/join_room_screen.dart';
import 'package:truearena/features/spectate/spectate_screen.dart';
import 'package:truearena/features/spectate/watch_live.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/neon.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

const _alreadyPlaying = {'message': 'this huud is already playing — watch live instead'};

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  test('only the live-game refusal counts as "already playing"', () {
    expect(isAlreadyPlaying(ApiException(409, 'this huud is already playing — watch live instead')), isTrue);
    expect(isAlreadyPlaying(ApiException(409, 'huud is full')), isFalse);
    expect(isAlreadyPlaying(ApiException(409, 'this huud has already ended')), isFalse);
    expect(isAlreadyPlaying(ApiException(404, 'no huud with that code')), isFalse);
    expect(isAlreadyPlaying(StateError('x')), isFalse);
  });

  Future<List<String>> open(WidgetTester tester, Future<http.Response> Function(http.Request) handler) async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path.replaceFirst('/api/v1', '')}');
      if (req.url.path.endsWith('/huuds/sessions/code')) {
        return _json(404, {'message': 'no active Huud with that code'});
      }
      return handler(req);
    });
    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient(client: client)),
      child: MaterialApp(theme: NeonTheme.dark, home: const JoinRoomScreen()),
    ));
    await tester.enterText(find.byType(TextField).first, 'ABC123');
    return calls;
  }

  testWidgets('joining a game that has started takes you to watch it live', (tester) async {
    final calls = await open(tester, (req) async {
      if (req.url.path.endsWith('/rooms/join')) return _json(409, _alreadyPlaying);
      if (req.url.path.endsWith('/rooms/watch')) {
        return _json(200, {
          'id': '00000000-0000-0000-0000-000000000009', 'code': 'ABC123', 'hostId': 'h', 'status': 'in_game',
          'gameType': 'truearena', 'members': [],
        });
      }
      return _json(200, []);
    });

    await tester.tap(find.widgetWithText(NeonButton, 'Join a huud'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(calls, containsAllInOrder(['POST /rooms/join', 'POST /rooms/watch']));
    expect(find.byType(SpectateScreen), findsOneWidget, reason: 'no dead end — they land on the live view');
    expect(find.text('Watching Traitors'), findsOneWidget);
  });

  testWidgets('a finished game shows the reason and does not try to watch', (tester) async {
    final calls = await open(tester, (req) async {
      if (req.url.path.endsWith('/rooms/join')) return _json(409, {'message': 'this huud has already ended'});
      return _json(200, []);
    });

    await tester.tap(find.widgetWithText(NeonButton, 'Join a huud'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(calls, ['POST /huuds/sessions/code', 'POST /rooms/join']);
    expect(find.text('this huud has already ended'), findsOneWidget);
    expect(find.byType(SpectateScreen), findsNothing);
  });

  testWidgets('if watching is refused too, the person is told why instead of nothing happening', (tester) async {
    await open(tester, (req) async {
      if (req.url.path.endsWith('/rooms/join')) return _json(409, _alreadyPlaying);
      if (req.url.path.endsWith('/rooms/watch')) return _json(403, {'message': 'private championship match'});
      return _json(200, []);
    });

    await tester.tap(find.widgetWithText(NeonButton, 'Join a huud'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('private championship match'), findsOneWidget);
    expect(find.byType(SpectateScreen), findsNothing);
  });
}
