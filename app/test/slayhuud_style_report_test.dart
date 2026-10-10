import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:truearena/features/slayhuud/slay_style_report.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets('report explains missing requirements and preview rewards',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: NeonTheme.dark,
        home: const Scaffold(
            body: SlayStyleReport(themeTitle: 'First Date', score: {
          'overall': 75.0,
          'stars': 2,
          'themeFit': 100.0,
          'requirements': 50.0,
          'colour': 100.0,
          'completeness': 50.0,
          'missing': ['shoes'],
          'feedback': ['Missing required items: shoes. Score limited to 75.'],
          'preview': true,
        }))));
    expect(find.text('75.0'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(2));
    expect(
        find.textContaining('Missing required items: shoes'), findsOneWidget);
    expect(
        find.text('Preview score — no coins or XP awarded.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('long feedback scrolls on a small screen with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 550);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: NeonTheme.dark,
        home: Scaffold(
            body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
                child: SlayStyleReport(themeTitle: 'Traditional Bride', score: {
                  'overall': 28.3,
                  'stars': 0,
                  'themeFit': 0.0,
                  'requirements': 33.3,
                  'colour': 100.0,
                  'completeness': 50.0,
                  'missing': ['headwear', 'jewellery'],
                  'feedback': List.filled(4,
                      'Your main garment does not match the wedding, traditional and bridal theme tags.'),
                  'preview': true,
                })))));
    await tester.scrollUntilVisible(find.text('Back to the studio'), 200,
        scrollable: find.byType(Scrollable));
    expect(find.text('Back to the studio').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
