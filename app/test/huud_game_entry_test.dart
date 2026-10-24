import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/hangout_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/home/home_screen.dart';
import 'package:truearena/features/huudspace/create_huud_sheet.dart';
import 'package:truearena/features/huudspace/huud_lounge.dart';
import 'package:truearena/features/huudspace/huud_space_screen.dart';
import 'package:truearena/features/huudspace/huud_voice.dart';
import 'package:truearena/theme/neon_theme.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> huud(
        {String? game,
        String status = 'waiting',
        bool live = true,
        String? mode}) =>
    {
      'id': 'h1',
      'name': 'Friday crew',
      'code': 'ABC234',
      'status': 'active',
      'privacy': 'friends',
      'live': live,
      'youAreIn': true,
      'youAreHost': true,
      'youOwn': true,
      'members': [
        {
          'userId': 'me',
          'displayName': 'Riley',
          'username': 'riley',
          'host': true,
          'here': live
        }
      ],
      'memberCount': 1,
      'liveCount': live ? 1 : 0,
      'currentGame': game == null
          ? null
          : {
              'roomId': 'room1',
              'code': 'QQ2345',
              'gameType': game,
              'status': status,
              'players': 1,
              'seats': 4,
              'playerIds': ['me'],
              'youArePlaying': true,
              'mode': mode
            },
    };

Future<void> frames(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> open(
    WidgetTester t, Future<http.Response> Function(http.Request) routes,
    {String game = 'chess', bool catalog = false}) async {
  await t.binding.setSurfaceSize(const Size(390, 1500));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final api = ApiClient(client: MockClient(routes))..bearer = 'game-entry-test';
  final state = AppState(api)
    ..identity = Identity.account
    ..user = const UserView(
        id: 'me', displayName: 'Riley', username: 'riley', isGuest: false);
  await t.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(
          theme: NeonTheme.dark,
          home: catalog
              ? const HomeScreen()
              : Scaffold(
                  body: Builder(
                      builder: (c) => TextButton(
                          onPressed: () => openHuudForGame(c, game),
                          child: const Text('Choose game')))))));
  await frames(t);
  final target = catalog
      ? find.byKey(ValueKey('home-game-$game'))
      : find.text('Choose game');
  await t.ensureVisible(target);
  await t.tap(target);
  await frames(t);
}

void expectGame(WidgetTester t, String game, {String? mode}) {
  expect(find.byType(HuudSpaceScreen), findsOneWidget);
  expect(t.getSemantics(find.byKey(const ValueKey('huud-tab-play'))),
      isSemantics(isSelected: true));
  expect(find.byKey(const ValueKey('huud-people-canvas')), findsNothing);
  final selected = t
      .widget<HuudSpaceScreen>(find.byType(HuudSpaceScreen))
      .initial!
      .currentGame!;
  expect(selected.gameType, game);
  expect(selected.mode, mode);
  expect(find.byKey(const ValueKey('huud-seats')), findsOneWidget);
  expect(t.takeException(), isNull);
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    HuudLounge.debugScenePlaceholder = true;
    HuudVoice.instance.reset();
    HangoutState.instance.clear();
    addTearDown(() => HuudLounge.debugScenePlaceholder = false);
  });

  testWidgets('tapping Chess in Games sets it up and opens the Huud Games tab',
      (t) async {
    var created = false;
    final posts = <Object>[];
    await open(t, (r) async {
      if (r.url.path.endsWith('/h1/game') && r.method == 'POST') {
        posts.add(jsonDecode(r.body));
        created = true;
        return json({});
      }
      if (r.url.path.endsWith('/current') || r.url.path.endsWith('/h1')) {
        return json(huud(game: created ? 'chess' : null));
      }
      return json([]);
    }, catalog: true);
    expect(posts, [
      {'gameType': 'chess'}
    ]);
    expectGame(t, 'chess');
  });

  testWidgets(
      'a new Huud keeps the preselected game and opens Games after creation',
      (t) async {
    final posts = <Object>[];
    await open(t, (r) async {
      if (r.url.path.endsWith('/current')) return json({});
      if (r.url.path == '/api/v1/huud-spaces' && r.method == 'POST') {
        posts.add(jsonDecode(r.body));
        return json(huud(game: 'chess'));
      }
      if (r.url.path.endsWith('/h1')) return json(huud(game: 'chess'));
      return json([]);
    });
    expect(t.getSemantics(find.byKey(const ValueKey('huud-first-game-chess'))),
        isSemantics(isSelected: true));
    await t.ensureVisible(find.byKey(const ValueKey('huud-create')));
    await t.tap(find.byKey(const ValueKey('huud-create')));
    await frames(t);
    expect((posts.single as Map)['gameType'], 'chess');
    expectGame(t, 'chess');
  });

  testWidgets(
      'the existing chosen game and mode are reused without creating another game',
      (t) async {
    var gamePosts = 0;
    await open(t, (r) async {
      if (r.url.path.endsWith('/game') && r.method == 'POST') gamePosts++;
      if (r.url.path.endsWith('/current') || r.url.path.endsWith('/h1')) {
        return json(huud(game: 'whot', mode: 'tell'));
      }
      return json([]);
    }, game: 'whot');
    expectGame(t, 'whot', mode: 'tell');
    expect(gamePosts, 0);
  });

  testWidgets('choosing a game mode opens Games with that exact selection',
      (t) async {
    String? chosenMode;
    final posts = <Object>[];
    await open(t, (r) async {
      if (r.url.path.endsWith('/h1/game') && r.method == 'POST') {
        posts.add(jsonDecode(r.body));
        chosenMode = (jsonDecode(r.body) as Map)['mode'] as String;
        return json({});
      }
      if (r.url.path.endsWith('/current') || r.url.path.endsWith('/h1')) {
        return json(
            huud(game: chosenMode == null ? null : 'whot', mode: chosenMode));
      }
      return json([]);
    }, game: 'whot');
    await t.ensureVisible(find.byKey(const ValueKey('whot-mode-tell')));
    await t.tap(find.byKey(const ValueKey('whot-mode-tell')));
    await frames(t);
    await t.scrollUntilVisible(find.byKey(const ValueKey('whot-rule-holdOn')), 100, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const ValueKey('whot-rule-holdOn')));
    await t.tap(find.byKey(const ValueKey('whot-settings-continue')));
    await frames(t);
    expect(posts, [containsPair('gameConfig', containsPair('holdOn', false))]);
    expectGame(t, 'whot', mode: 'tell');
  });

  testWidgets(
      'going live from Games opens the selected game after confirmation',
      (t) async {
    var live = false, created = false;
    await open(t, (r) async {
      if (r.url.path.endsWith('/h1/live') && r.method == 'POST') live = true;
      if (r.url.path.endsWith('/h1/game') && r.method == 'POST') created = true;
      if (r.url.path.endsWith('/current') ||
          r.url.path.endsWith('/h1') ||
          r.url.path.endsWith('/h1/live')) {
        return json(huud(live: live, game: created ? 'chess' : null));
      }
      return json([]);
    });
    await t.ensureVisible(find.byKey(const ValueKey('golive-confirm')));
    await t.tap(find.byKey(const ValueKey('golive-confirm')));
    await frames(t);
    expectGame(t, 'chess');
  });

  testWidgets(
      'cancelling Go Live stays in Games rather than opening an offline Huud',
      (t) async {
    var posts = 0;
    await open(t, (r) async {
      if (r.method == 'POST') posts++;
      return json(huud(live: false));
    });
    Navigator.of(t.element(find.byKey(const ValueKey('golive-confirm')))).pop();
    await frames(t);
    expect(find.byType(HuudSpaceScreen), findsNothing);
    expect(find.text('Choose game'), findsOneWidget);
    expect(posts, 0);
  });

  testWidgets(
      'failed setup keeps the user at game selection with a retry message',
      (t) async {
    await open(t, (r) async {
      if (r.url.path.endsWith('/h1/game')) {
        return json({'message': 'Unavailable'}, 503);
      }
      if (r.url.path.endsWith('/current')) return json(huud());
      return json([]);
    });
    expect(find.byType(HuudSpaceScreen), findsNothing);
    expect(find.text(userErrorMessage), findsOneWidget);
    expect(find.text('Choose game'), findsOneWidget);
  });

  testWidgets('an active different game is shown in Games without replacing it',
      (t) async {
    var gamePosts = 0;
    await open(t, (r) async {
      if (r.method == 'POST' && r.url.path.endsWith('/game')) gamePosts++;
      if (r.url.path.endsWith('/current') || r.url.path.endsWith('/h1')) {
        return json(huud(game: 'ludo', status: 'playing'));
      }
      return json([]);
    });
    expect(
        t
            .widget<HuudSpaceScreen>(find.byType(HuudSpaceScreen))
            .initial!
            .currentGame!
            .gameType,
        'ludo');
    expect(gamePosts, 0);
    expect(find.byKey(const ValueKey('huud-existing-game-dialog')), findsOneWidget);
    expect(find.textContaining('You already have Ludo open.'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('huud-existing-game-okay')));
    await frames(t);
    expect(find.byKey(const ValueKey('huud-existing-game-dialog')), findsNothing);
    expect(t.getSemantics(find.byKey(const ValueKey('huud-tab-play'))), isSemantics(isSelected: true));
    expect(t.takeException(), isNull);
  });
}
