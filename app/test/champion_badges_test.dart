import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:truearena/features/competitive/champion_badges.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/champion_badge.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  final badge = ChampionBadgeData.fromJson(const {
    'championshipId': 'c1',
    'name': 'Big Huud Cup',
    'awardedAt': '2026-10-12T18:00:00Z',
    'gameType': 'chess',
    'size': 64,
  });

  Future<void> pump(WidgetTester tester, List<ChampionBadgeData> badges) => tester.pumpWidget(MaterialApp(
        theme: NeonTheme.light,
        home: Scaffold(body: ChampionBadgesShelf(badges: badges, handle: 'eric', own: false)),
      ));

  test('a badge reads its game and the size of the field', () {
    expect(badge.title, 'Big Huud Cup Champion');
    expect(badge.players, 64);
    expect(ChampionBadge.describe(64, 'chess'), '64-player Chess championship');
    expect(ChampionBadge.describe(32, 'draughts'), '32-player Draughts championship');
  });

  test('the share caption says who won what', () {
    expect(championBadgeShareText(badge, handle: 'eric', own: true),
        "I'm the Big Huud Cup champion on PlayHuud 🏆 — 64-player Chess championship. Come play: https://playhuud.com");
    expect(championBadgeShareText(badge, handle: 'eric', own: false), startsWith('@eric is the Big Huud Cup champion'));
  });

  testWidgets('no badges, no shelf', (tester) async {
    await pump(tester, const []);
    expect(find.text('CHAMPION BADGES'), findsNothing);
  });

  testWidgets('a badge on a profile opens up big with a Share button', (tester) async {
    await pump(tester, [badge]);
    expect(find.text('CHAMPION BADGES'), findsOneWidget);
    expect(find.byType(ChampionBadge), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('champion-badge-c1')));
    await tester.pumpAndSettle();
    expect(find.text('Big Huud Cup Champion'), findsOneWidget);
    expect(find.text('64-player Chess championship'), findsOneWidget);
    expect(find.text('Won 12 Oct 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('champion-badge-share')), findsOneWidget);
  });
}
