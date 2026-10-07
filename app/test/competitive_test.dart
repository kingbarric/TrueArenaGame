import 'dart:convert';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/competitive/competitive_models.dart';
import 'package:truearena/features/competitive/leaderboard_screen.dart';
import 'package:truearena/features/competitive/card_share.dart';
import 'package:truearena/features/competitive/player_card.dart';
import 'package:truearena/features/competitive/player_profile_screen.dart';
import 'package:truearena/features/draughts/draughts_lobby_screen.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/neon.dart';

/// A /me/competitive payload as the server sends it: rated in Draughts, on the
/// global board, but with no state set yet.
Map<String, dynamic> _profileJson({bool complete = false, bool rated = true}) => {
      'userId': 'u1',
      'username': 'eric',
      'displayName': 'Eric',
      'avatarUrl': '🦁',
      'playhuudNumber': 127,
      'playhuudId': '#000127',
      'founding': {'code': 'FOUNDING_1000', 'label': 'Founding 1,000'},
      'location': {
        'countryCode': 'NG',
        'countryName': 'Nigeria',
        'regionCode': complete ? 'NG-RI' : null,
        'regionName': complete ? 'Rivers' : null,
        'city': null,
        'cityPublic': false,
      },
      'profileComplete': complete,
      'locationLockedUntil': null,
      'games': [
        if (rated)
          {
            'gameType': 'draughts',
            'rating': 1842,
            'peakRating': 1917,
            'ratingDeviation': 62,
            'provisional': false,
            'placementGamesPlayed': 10,
            'placementGamesRequired': 10,
            'ranks': {
              'global': {'rank': 12421, 'status': 'ranked'},
              'country': {'rank': 127, 'status': 'ranked'},
              'region': complete
                  ? {'rank': 14, 'status': 'ranked'}
                  : {'rank': null, 'status': 'location_required'},
            },
            'stats': {
              'gamesPlayed': 428,
              'wins': 291,
              'losses': 124,
              'draws': 13,
              'winRate': 0.68,
              'currentWinStreak': 7,
              'bestWinStreak': 19,
              'top100Wins': 4,
              'tournamentWins': 3,
              'casualGames': 12,
            },
            'lastRatedAt': '2026-10-05T10:00:00Z',
          },
      ],
      'achievements': [
        {'type': 'FOUNDING_1000', 'label': 'Founding 1,000', 'icon': '💎', 'rarity': 'epic', 'displayPriority': 900},
        {
          'type': 'STREAK_10',
          'label': '10 Match Win Streak',
          'icon': '🔥',
          'gameType': 'draughts',
          'earnedAt': '2026-09-01T00:00:00Z',
          'rarity': 'rare',
          'displayPriority': 400,
        },
      ],
    };

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

Widget _app(AppState state, Widget home) => AppScope(
      state: state,
      child: MaterialApp(theme: NeonTheme.light, home: home),
    );

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('models', () {
    test('parses a full competitive profile', () {
      final p = CompetitiveProfile.fromJson(_profileJson());
      expect(p.playhuudId, '#000127');
      expect(p.founding?.label, 'Founding 1,000');
      expect(p.profileComplete, isFalse);
      final draft = p.game('draughts')!;
      expect(draft.name, 'Draughts'); // the app's brand name for draughts
      expect(draft.rating, 1842);
      expect(draft.ranks.country.isRanked, isTrue);
      expect(draft.ranks.region.status, RankInfo.locationRequired);
      expect(draft.stats.bestWinStreak, 19);
      expect(p.achievements.first.isFounding, isTrue);
    });

    test('formats PlayHuud numbers and locations for display', () {
      expect(formatPlayhuudNumber(127), '#000127');
      expect(formatPlayhuudNumber(1234567), '#1234567');
      expect(flagEmoji('ng'), '🇳🇬');
      expect(
          locationLine(const CompetitiveLocation(countryCode: 'NG', countryName: 'Nigeria', regionName: 'Rivers')),
          '🇳🇬 Nigeria · Rivers');
      expect(locationLine(null), '');
    });
  });

  /// A phone-sized viewport — the cards are sized off the screen width.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  group('player cards', () {
    test('Overall leads with the best game rating, labelled with that game — never a blended rating', () {
      final cards = buildPlayerCards(CompetitiveProfile.fromJson(_profileJson()));
      // Overall, then the ranked game, then every other game — played or not.
      expect(cards.map((c) => c.title),
          ['OVERALL', 'DRAUGHTS', 'TRAITORS', 'WORD BLUFF', 'CHESS', 'WHOT', 'LUDO', 'MACALA']);
      final overall = cards.first;
      expect(overall.bigValue, '1842');
      expect(overall.bigLabel, 'DRA');
      expect(overall.stats.map((s) => '${s.value} ${s.label}'),
          ['428 GMS', '68% WIN', '3 TTL', '19 BST', '1 BDG', '#127 RNK']);
      final draft = cards[1];
      expect(draft.bigLabel, 'NG #127');
      expect(draft.theme.accent, PlayerCardTheme.forGame('draughts').accent);
      expect(draft.theme.accent, isNot(PlayerCardTheme.overall.accent)); // each game has its own livery
    });

    test('a player with nothing rated still gets every card, blank', () {
      final cards = buildPlayerCards(CompetitiveProfile.fromJson(_profileJson(rated: false)));
      expect(cards, hasLength(8));
      expect(cards.every((c) => c.blank), isTrue);
      expect(cards[1].bigValue, '—');
      expect(cards[1].bigLabel, 'UNRATED');
    });

    test('every card has its own colours', () {
      final cards = buildPlayerCards(CompetitiveProfile.fromJson(_profileJson(rated: false)));
      expect(cards.map((c) => c.theme.accent).toSet(), hasLength(cards.length));
      expect(cards.map((c) => c.theme.top).toSet(), hasLength(cards.length));
    });

    test('only ranked games open a detail page', () {
      final cards = buildPlayerCards(CompetitiveProfile.fromJson(_profileJson()));
      expect(cards.where((c) => c.ranked).map((c) => c.title), ['DRAUGHTS']);
    });

    test('share captions name the game, the rating and how to find the player', () {
      final cards = buildPlayerCards(CompetitiveProfile.fromJson(_profileJson()));
      expect(playerCardShareText(cards[0]), 'My PlayHuud player card #000127. Come play me: https://playhuud.com');
      expect(playerCardShareText(cards[1]),
          'My Draughts card on PlayHuud — rating 1842, NG #127. Find me: #000127 https://playhuud.com');
      expect(playerCardShareText(cards.firstWhere((c) => c.title == 'WHOT')),
          'Come play Whot with me on PlayHuud #000127: https://playhuud.com');
    });

    test('the shared image is story-sized (9:16), for WhatsApp Status and friends', () async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 68, 100), Paint()..color = const Color(0xff12606a));
      final card = await recorder.endRecording().toImage(68, 100);
      final cards = buildPlayerCards(CompetitiveProfile.fromJson(_profileJson()));
      final story = await composePlayerCardStory(card, cards[1]);
      expect(story.width, 1080);
      expect(story.height, 1920);
    });

    test('provisional players show their placement progress instead of a rank', () {
      final json = _profileJson();
      final game = (json['games'] as List).first as Map<String, dynamic>;
      game['provisional'] = true;
      game['placementGamesPlayed'] = 5;
      final cards = buildPlayerCards(CompetitiveProfile.fromJson(json));
      expect(cards[1].bigLabel, 'PROV 5/10');
    });
  });

  testWidgets('own profile without a state asks to complete it, and shows blank Draughts cards before any rated game',
      (tester) async {
    phone(tester);
    final state = AppState(ApiClient(client: MockClient((_) async => _json([]))));
    final profile = CompetitiveProfile.fromJson(_profileJson(rated: false));

    await tester.pumpWidget(_app(
        state,
        Scaffold(
            body: SingleChildScrollView(
                child: CompetitiveRecordSection(profile: profile, own: true, ratedGames: const ['draughts']))),
      ));
    await tester.pumpAndSettle();

    expect(find.text('Complete your player profile to unlock National & State rankings.'), findsOneWidget);
    expect(find.byKey(const ValueKey('player-card-OVERALL')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-card-DRAUGHTS')), findsOneWidget);
    // The visibility switch moved to Settings; the profile page is just cards.
    expect(find.byKey(const ValueKey('profile-public-switch')), findsNothing);
  });

  testWidgets('your page runs: cards, then "complete your profile", then the wallet', (tester) async {
    phone(tester);
    final state = AppState(ApiClient(client: MockClient((_) async => _json([]))));
    final profile = CompetitiveProfile.fromJson(_profileJson(rated: false));

    await tester.pumpWidget(_app(
        state,
        Scaffold(
            body: SingleChildScrollView(
                child: CompetitiveRecordSection(
          profile: profile,
          own: true,
          belowPrompt: const Text('WALLET-ROW'),
        )))));
    await tester.pumpAndSettle();

    final cardsY = tester.getTopLeft(find.byKey(const ValueKey('player-card-carousel'))).dy;
    final promptY = tester.getTopLeft(find.byKey(const ValueKey('complete-player-profile'))).dy;
    final walletY = tester.getTopLeft(find.text('WALLET-ROW')).dy;
    expect(cardsY, lessThan(promptY), reason: 'the player cards are the first thing on the page');
    expect(promptY, lessThan(walletY), reason: 'the wallet sits under the complete-profile prompt');
  });

  testWidgets("someone else's profile shows their cards, but no prompts or settings", (tester) async {
    phone(tester);
    final state = AppState(ApiClient(client: MockClient((_) async => _json([]))));
    final profile = CompetitiveProfile.fromJson(_profileJson());

    await tester.pumpWidget(_app(
        state, Scaffold(body: SingleChildScrollView(child: CompetitiveRecordSection(profile: profile, own: false)))));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('complete-player-profile')), findsNothing);
    expect(find.byKey(const ValueKey('profile-public-switch')), findsNothing);
    expect(find.text('10 Match Win Streak'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('card-big-OVERALL'))).data, '1842');
  });

  testWidgets('swiping brings the next game card to the front; tapping it opens that game', (tester) async {
    phone(tester);
    final state = AppState(ApiClient(client: MockClient((_) async => _json([]))));
    final profile = CompetitiveProfile.fromJson(_profileJson());

    await tester.pumpWidget(_app(
        state, Scaffold(body: SingleChildScrollView(child: CompetitiveRecordSection(profile: profile, own: false)))));
    await tester.pumpAndSettle();

    final carousel = find.byKey(const ValueKey('player-card-carousel'));
    expect(find.text('Share overall card'), findsOneWidget); // Overall starts at the front

    await tester.fling(carousel, const Offset(-200, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Share draughts card'), findsOneWidget, reason: 'one flick moves one card round the ring');

    // The front card is drawn last, so it's the one a tap reaches.
    await tester.tapAt(tester.getCenter(carousel));
    await tester.pumpAndSettle();
    expect(find.byType(GameCompetitiveScreen), findsOneWidget);
  });

  testWidgets('a game without rankings says so instead of opening an empty page', (tester) async {
    phone(tester);
    final state = AppState(ApiClient(client: MockClient((_) async => _json([]))));
    final profile = CompetitiveProfile.fromJson(_profileJson());
    await tester.pumpWidget(_app(
        state, Scaffold(body: SingleChildScrollView(child: CompetitiveRecordSection(profile: profile, own: false)))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('TRAITORS').last); // the pill under the ring (the card has the same title)
    await tester.pumpAndSettle();
    expect(find.text('Share traitors card'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('player-card-carousel'))));
    await tester.pumpAndSettle();
    expect(find.byType(GameCompetitiveScreen), findsNothing);
    expect(find.text('Rankings for Traitors are coming soon.'), findsOneWidget);
  });

  testWidgets('a private profile shows who they are and nothing more', (tester) async {
    phone(tester);
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('/players/eric/competitive')) {
        return _json({
          ..._profileJson(),
          'restricted': true,
          'profilePublic': false,
          'games': [],
          'location': null,
          'achievements': [],
        });
      }
      if (req.url.path.endsWith('/competitive/games')) return _json(['draughts']);
      return _json([]);
    });
    final state = AppState(ApiClient(client: mock));

    await tester.pumpWidget(_app(state, const PlayerProfileScreen(username: 'eric', statusUserId: 'u1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Eric keeps their competitive profile private.'), findsOneWidget);
    expect(find.textContaining('#000127', findRichText: true), findsOneWidget); // identity stays
    expect(find.byKey(const ValueKey('player-card-carousel')), findsNothing);
    expect(find.byTooltip('Status'), findsOneWidget); // opened from friends: status is one tap away
  });

  testWidgets('game detail shows real ranks big, and explains a missing one', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final state = AppState(ApiClient(client: MockClient((_) async => _json([]))));
    final profile = CompetitiveProfile.fromJson(_profileJson());

    await tester.pumpWidget(_app(state, GameCompetitiveScreen(profile: profile, gameType: 'draughts', own: true)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('1842'), findsOneWidget);
    expect(find.text('Peak 1917'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('rank-global')), matching: find.text('#12,421')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('rank-country')), matching: find.text('#127')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('rank-region')), matching: find.text('Complete profile')),
        findsOneWidget);
    expect(find.text('291/124/13'), findsOneWidget);
  });

  testWidgets('leaderboard lists entries, pins your own rank, and gates the state board on location',
      (tester) async {
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('/api/v1/leaderboards/draughts')) {
        final scope = req.url.queryParameters['scope'];
        if (scope == 'region') {
          return _json({
            'gameType': 'draughts',
            'scope': 'region',
            'offset': 0,
            'entries': [],
            'unavailableReason': 'location_required',
          });
        }
        return _json({
          'gameType': 'draughts',
          'scope': scope,
          'scopeKey': scope == 'country' ? 'NG' : null,
          'scopeName': scope == 'country' ? 'Nigeria' : null,
          'offset': 0,
          'entries': [
            {
              'rank': 1,
              'userId': 'top',
              'username': 'champ',
              'displayName': 'Champ',
              'playhuudId': '#000003',
              'founding': {'code': 'FOUNDING_100', 'label': 'Founding 100'},
              'rating': 2147,
              'peakRating': 2200,
              'gamesPlayed': 500,
              'winRate': 0.8,
              'tournamentWins': 2,
              'provisional': false,
            },
          ],
          'me': {
            'rank': 127,
            'userId': 'u1',
            'username': 'eric',
            'displayName': 'Eric',
            'rating': 1842,
            'provisional': false,
          },
        });
      }
      return _json([]);
    });
    final state = AppState(ApiClient(client: mock));

    await tester.pumpWidget(_app(state, const LeaderboardScreen(gameType: 'draughts')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Draughts Rankings'), findsOneWidget);
    expect(find.text('Champ'), findsOneWidget);
    expect(find.text('FOUNDING 100'), findsOneWidget);
    expect(find.text('2147'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('leaderboard-me-rank'))).data, '#127');

    await tester.tap(find.byKey(const ValueKey('scope-country')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Nigeria'), findsOneWidget); // the tab renames itself to the board it shows

    await tester.tap(find.byKey(const ValueKey('scope-region')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Unlock State rankings'), findsOneWidget);
    expect(find.text('Complete profile'), findsOneWidget);
  });

  testWidgets('choosing Ranked locks Draughts to official rules', (tester) async {
    DraughtsMatchSetup? result;
    await tester.pumpWidget(MaterialApp(
      theme: NeonTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showDraughtsRulesSheet(context, canRank: true),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(2)); // ranked, captures
    expect(tester.widget<Switch>(switches.at(1)).value, isFalse); // casual default: optional captures

    await tester.tap(switches.at(0));
    await tester.pumpAndSettle();
    final captures = tester.widget<Switch>(switches.at(1));
    expect(captures.value, isTrue);
    expect(captures.onChanged, isNull); // can't be switched off while ranked

    await tester.ensureVisible(find.text('Start ranked huud')); // the sheet scrolls on short screens
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NeonButton, 'Start ranked huud'));
    await tester.pumpAndSettle();
    expect(result?.ranked, isTrue);
    expect(result?.mandatoryCapture, isTrue);
  });

  testWidgets('guests are not offered a ranked match', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: NeonTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => showDraughtsRulesSheet(context), child: const Text('open')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Ranked'), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
  });
}
