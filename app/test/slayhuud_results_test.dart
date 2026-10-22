import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:truearena/features/slayhuud/slay_results.dart';
import 'package:truearena/theme/neon_theme.dart';

Widget _results(Map<String, dynamic> score, {bool career = false}) =>
    MaterialApp(
        theme: NeonTheme.dark,
        home: SlayResultsScreen(
            score: score,
            title: 'First Date',
            career: career,
            location: 'lagos'));

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'a missed must-wear is explained, and a free-style score says it is a preview',
      (tester) async {
    await tester.pumpWidget(_results({
      'overall': 75.0,
      'stars': 2,
      'themeFit': 100.0,
      'requirements': 50.0,
      'colour': 100.0,
      'completeness': 50.0,
      'missing': ['shoes'],
      'feedback': ['Missing required items: shoes. Score limited to 75.'],
      'preview': true,
    }));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Cute! Almost there'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(2));
    expect(
        find.textContaining('Missing required items: shoes'), findsOneWidget);
    expect(
        find.text('Preview score — no coins or XP awarded.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a five-star career result celebrates rewards, unlocks, rank-up and standings',
      (tester) async {
    await tester.pumpWidget(_results({
      'overall': 92.5,
      'stars': 5,
      'starCount': 5,
      'personalBest': 92.5,
      'newBest': true,
      'coinsEarned': 175,
      'xpEarned': 140,
      'milestonePassed': true,
      'themeFit': 100.0,
      'requirements': 100.0,
      'colour': 100.0,
      'completeness': 100.0,
      'missing': [],
      'feedback': ['Your outfit, required items and palette match this brief.'],
      'unlocked': [
        {
          'id': 'female-skirts-collection-6',
          'name': 'Purple Skirt',
          'category': 'skirts'
        }
      ],
      'rankUp': {
        'rank': 'Rising Star',
        'chapter': 'City Style',
        'location': 'lagos',
        'room': 'Boutique fitting room',
        'venue': 'City street',
        'poses': ['editorial'],
        'items': [
          {'id': 'female-executive', 'name': 'Executive'}
        ]
      },
      'ranking': {
        'friendsRank': 2,
        'global': {'topPercent': 18}
      },
    }, career: true));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('SLAY! Total icon'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));
    expect(find.text('🏆 NEW PERSONAL BEST'), findsOneWidget);
    expect(find.text('You’re a Rising Star!'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('+175 coins'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('#2 with friends'), findsOneWidget);
    expect(find.text('Top 18% worldwide'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Purple Skirt'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.scrollUntilVisible(find.text('Continue'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Try again').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('results stay reachable on a small phone with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 550);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: _results({
          'overall': 28.3,
          'stars': 0,
          'themeFit': 0.0,
          'requirements': 33.3,
          'colour': 100.0,
          'completeness': 50.0,
          'missing': ['headwear', 'jewellery'],
          'feedback': List.filled(
              4, 'Your main garment does not match the wedding theme tags.'),
        })));
    await tester.pump(const Duration(seconds: 2));
    await tester.scrollUntilVisible(find.text('Done'), 200,
        scrollable: find.byType(Scrollable).first);
    // ensureVisible can change the offset after the last drag; lay out that frame.
    await tester.pump();
    expect(find.text('Done').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
