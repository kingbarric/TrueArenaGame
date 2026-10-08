import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/huud/social_huud_controller.dart';
import 'package:truearena/features/huud/social_huud_entry.dart';
import 'package:truearena/features/huud/social_huud_models.dart';
import 'package:truearena/features/huud/social_huud_screen.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/features/whot/whot_game_screen.dart';
import 'whot_game_test.dart' show TestSocket;

Map<String, dynamic> fixture({bool participant = false}) => {
      'id': 'huud-1',
      'code': 'ERIC82',
      'ownerId': 'host',
      'name': "Eric's Huud",
      'description': '',
      'privacy': 'public',
      'status': 'active',
      'activity': 'waiting',
      'gameType': 'draughts',
      'activityVersion': 1,
      'currentRoomId': null,
      'participantCount': participant ? 2 : 1,
      'viewerCount': participant ? 0 : 1,
      'playerCount': 0,
      'participant': participant,
      'joinRequestStatus': participant ? 'accepted' : 'none',
      'gameRequestStatus': 'none',
      'capacity': {'min': 2, 'max': 2, 'allowed': []},
      'participants': [
        {'userId': 'host', 'username': 'Eric', 'status': 'participant'},
        if (participant)
          {'userId': 'viewer', 'username': 'Chidi', 'status': 'participant'}
      ],
      'joinRequests': [],
      'gameRequests': [],
      'selectedPlayers': [],
    };
http.Response json(Object? body) =>
    http.Response(body == null ? '' : jsonEncode(body), 200,
        headers: {'content-type': 'application/json'});

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  for (final participant in [false, true]) {
    testWidgets(
        participant
            ? 'participants request a seat separately from voice'
            : 'viewers make one admission request before requesting seats',
        (tester) async {
      final posts = <String>[], view = fixture(participant: participant);
      final api = ApiClient(client: MockClient((r) async {
        if (r.method == 'POST') {
          posts.add(r.url.path);
          if (r.url.path.endsWith('join-request')) {
            view['joinRequestStatus'] = 'requested';
          }
          if (r.url.path.endsWith('game-request')) {
            view['gameRequestStatus'] = 'requested';
          }
        }
        return json(r.url.path.endsWith('/chat') ? [] : view);
      }));
      final c = SocialHuudController(api, 'viewer', SocialHuud.fromJson(view));
      await tester.pumpWidget(MaterialApp(
          theme: NeonTheme.light,
          home: Scaffold(
              body: ListenableBuilder(
                  listenable: c,
                  builder: (context, child) => HuudContents(controller: c)))));
      final button = participant ? 'Request to Play' : 'Request to Join Huud';
      expect(find.text(button), findsOneWidget);
      expect(find.text('Start Game'), findsNothing);
      expect(find.textContaining('Request Mic'), findsNothing);
      if (!participant) expect(find.text('Request to Play'), findsNothing);
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      expect(
          posts.where(
              (p) => p.endsWith(participant ? 'game-request' : 'join-request')),
          hasLength(1));
      expect(posts.where((p) => p.contains('voice/token')), isEmpty);
      expect(find.text(participant ? 'Requested' : 'Join requested'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
  testWidgets('host is optional and Start requires a valid selected roster',
      (tester) async {
    final view = fixture(participant: true);
    view['gameRequests'] = [
      {'userId': 'viewer', 'username': 'Chidi', 'status': 'requested'}
    ];
    final api = ApiClient(
        client: MockClient(
            (r) async => json(r.url.path.endsWith('/chat') ? [] : view)));
    final c = SocialHuudController(api, 'host', SocialHuud.fromJson(view));
    await tester.pumpWidget(MaterialApp(
        theme: NeonTheme.light,
        home: Scaffold(body: HuudContents(controller: c))));
    expect(
        tester
            .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, 'Include me as a player'))
            .value,
        isFalse);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Start Game'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('creation defaults to public and fits a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppState(ApiClient(client: MockClient((_) async => json(null))))
      ..user =
          const UserView(id: 'host', displayName: 'Eric', username: 'eric');
    Map<String, dynamic>? result;
    await tester.pumpWidget(AppScope(
        state: app,
        child: MaterialApp(
            theme: NeonTheme.light,
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () async {
                          result = await showCreateHuudPrompt(context,
                              gameType: 'whot');
                        },
                        child: const Text('Open')))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SegmentedButton<String>>(
                find.byType(SegmentedButton<String>))
            .selected,
        {'public'});
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Create Huud'));
    await tester.pumpAndSettle();
    expect(result?['privacy'], 'public');
    expect(result?['gameType'], 'whot');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
  test('mode capacities and population counts stay separate', () {
    final raw = fixture(participant: true)..['selectedPlayers'] = ['a', 'b'];
    expect(SocialHuud.fromJson(raw).validRoster, isTrue);
    expect(SocialHuud.fromJson(raw).playerCount, 0);
    raw['capacity'] = {
      'min': 4,
      'max': 8,
      'allowed': [4, 6, 8]
    };
    raw['selectedPlayers'] = ['a', 'b', 'c', 'd', 'e'];
    expect(SocialHuud.fromJson(raw).validRoster, isFalse);
  });
  test('room recovery distinguishes a Huud match from a legacy room', () async {
    final api = ApiClient(
        client: MockClient((r) async =>
            json(r.url.path.endsWith('/social-room') ? fixture() : null)));
    expect((await socialHuudForRoom(api, 'social-room'))?.id, 'huud-1');
    expect(await socialHuudForRoom(api, 'legacy-room'), isNull);
  });
  test('forbidden Huud recovery cannot fall back to legacy player access',
      () async {
    final api = ApiClient(
        client: MockClient((r) async => http.Response(
            '{"message":"private Huud"}', 403,
            headers: {'content-type': 'application/json'})));
    await expectLater(
        socialHuudForRoom(api, 'private-room'), throwsA(isA<ApiException>()));
  });
  testWidgets('Whot retains Huud chat inside a narrow phone game layout',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final raw = fixture(participant: true)
      ..['activity'] = 'playing'
      ..['gameType'] = 'whot'
      ..['selectedPlayers'] = ['viewer', 'host'];
    final api = ApiClient(
        client: MockClient(
            (r) async => json(r.url.path.endsWith('/chat') ? [] : raw)));
    final app = AppState(api);
    final c = SocialHuudController(api, 'viewer', SocialHuud.fromJson(raw));
    c.messages = [
      {
        'id': 'message',
        'userId': 'host',
        'username': 'Eric',
        'text': 'Stay for another game'
      }
    ];
    final socket = TestSocket();
    await tester.pumpWidget(AppScope(
        state: app,
        child: MaterialApp(
            theme: NeonTheme.light,
            home: SocialHuudScope(
                controller: c,
                child: Scaffold(
                    body: Column(children: [
                  const SizedBox(height: 52, child: Text("Eric's Huud")),
                  Expanded(
                      child: WhotGameScreen(
                          socket: socket,
                          selfId: 'viewer',
                          roomId: 'room',
                          roomCode: 'ERIC82',
                          nicknames: const {
                        'viewer': 'Chidi',
                        'host': 'Eric'
                      })),
                ]))))));
    socket.snapshot({
      'players': ['viewer', 'host'],
      'dealer': 'viewer',
      'turnPlayer': 'viewer',
      'handSizes': {'viewer': 3, 'host': 5}
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Huud Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Stay for another game'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Message your Huud'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await socket.close();
    c.dispose();
    app.dispose();
  });
}
