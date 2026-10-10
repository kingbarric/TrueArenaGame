import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/app.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/lobby/joined_room_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<AppState> reopen({required int daysAgo}) async {
    SharedPreferences.setMockInitialValues({
      'ta_access': 'saved-access',
      'ta_refresh': 'saved-refresh',
      'ta_cached_user': jsonEncode({
        'id': 'player-1',
        'displayName': 'Player',
        'isGuest': false,
      }),
      'ta_active_room': 'room-1',
      'ta_active_room_user': 'player-1',
      'ta_active_room_saved_at': DateTime.now()
          .subtract(Duration(days: daysAgo))
          .millisecondsSinceEpoch,
    });
    final state = AppState(ApiClient(client: MockClient((_) async {
      throw const SocketException('offline');
    })));
    await state.bootstrap();
    return state;
  }

  test('recent game survives cold start and temporary network outage', () async {
    final state = await reopen(daysAgo: 6);
    expect(state.identity, Identity.account);
    expect(state.activeRoomId, 'room-1');
    state.dispose();
  });

  test('a game saved over a week ago is not reopened', () async {
    final state = await reopen(daysAgo: 8);
    expect(state.activeRoomId, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ta_active_room'), isNull);
    state.dispose();
  });

  testWidgets('reopens the saved live room screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(ApiClient(client: MockClient((request) async {
      if (request.url.path.endsWith('/rooms/room-1')) {
        return http.Response(jsonEncode({
          'id': 'room-1',
          'code': 'ABCDEF',
          'hostId': 'player-1',
          'status': 'lobby',
          'gameType': 'whot',
          'members': [
            {'userId': 'player-1', 'nickname': 'Player', 'ready': false}
          ],
        }), 200);
      }
      return http.Response('[]', 200);
    })));
    state.user = const UserView(id: 'player-1', displayName: 'Player');
    state.identity = Identity.account;
    state.activeRoomId = 'room-1';
    // The app was closed while this room's screen was open.
    state.resumeRoomId = 'room-1';

    await tester.pumpWidget(TrueArenaApp(state: state));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(JoinedRoomScreen), findsOneWidget);
    expect(state.activeRoomId, 'room-1');
  });

  testWidgets('a lobby you backed out of does not open by itself next time', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final asked = <String>[];
    final state = AppState(ApiClient(client: MockClient((request) async {
      asked.add(request.url.path);
      return http.Response('[]', 200);
    })));
    state.user = const UserView(id: 'player-1', displayName: 'Player');
    state.identity = Identity.account;
    state.activeRoomId = 'room-1';

    await tester.pumpWidget(TrueArenaApp(state: state));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(JoinedRoomScreen), findsNothing);
    expect(asked.where((p) => p.endsWith('/rooms/room-1') || p.endsWith('/rooms/active')), isEmpty);
  });
}
