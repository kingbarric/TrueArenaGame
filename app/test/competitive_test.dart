import 'dart:convert';

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
import 'package:truearena/features/competitive/player_profile_screen.dart';
import 'package:truearena/features/draughts/draughts_lobby_screen.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/neon.dart';

/// A /me/competitive payload as the server sends it: rated in Draft, on the
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
      expect(draft.name, 'Draft'); // the app's brand name for draughts
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

  testWidgets('own profile without a state asks to complete it, and still shows Draft before any rated game',
      (tester) async {
    final state = AppState(ApiClient(client: MockClient((_) async => _json([]))));
    final profile = CompetitiveProfile.fromJson(_profileJson(rated: false));

    await tester.pumpWidget(_app(
        state,
        Scaffold(
            body: SingleChildScrollView(
                child: CompetitiveRecordSection(profile: profile, own: true, ratedGames: const ['draughts']))),
      ));

    expect(find.text('Complete your player profile to unlock National & State rankings.'), findsOneWidget);
    expect(find.byKey(const ValueKey('game-record-draughts')), findsOneWidget);
    expect(find.text('Play a ranked match to get rated'), findsOneWidget);
  });

  testWidgets("someone else's profile never shows the complete-profile prompt", (tester) async {
    final state = AppState(ApiClient(client: MockClient((_) async => _json([]))));
    final profile = CompetitiveProfile.fromJson(_profileJson());

    await tester.pumpWidget(_app(
        state, Scaffold(body: SingleChildScrollView(child: CompetitiveRecordSection(profile: profile, own: false)))));

    expect(find.byKey(const ValueKey('complete-player-profile')), findsNothing);
    expect(find.text('Nigeria #127'), findsOneWidget);
    expect(find.text('10 Match Win Streak'), findsOneWidget);
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

    expect(find.text('Draft Rankings'), findsOneWidget);
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

  testWidgets('choosing Ranked locks Draft to official rules', (tester) async {
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
