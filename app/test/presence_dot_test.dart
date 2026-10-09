import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/neon.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> show(WidgetTester tester, Presence presence) => tester.pumpWidget(MaterialApp(
      theme: NeonTheme.dark,
      home: Scaffold(body: Center(child: OnlineAvatar('ada', online: false, presence: presence, size: 40)))));

  Color dot(WidgetTester tester, Presence p) =>
      (tester.widget<Container>(find.byKey(ValueKey('presence-${p.name}'))).decoration as BoxDecoration).color!;

  testWidgets('in the game is green, stepped away is amber, gone a while is grey', (tester) async {
    await show(tester, Presence.here);
    expect(dot(tester, Presence.here), const Color(0xff4ade80));
    expect(find.bySemanticsLabel(RegExp('ada, online')), findsOneWidget);

    await show(tester, Presence.away);
    expect(dot(tester, Presence.away), const Color(0xfff5a524));
    expect(find.bySemanticsLabel(RegExp('ada, away')), findsOneWidget);

    await show(tester, Presence.offline);
    expect(dot(tester, Presence.offline), const Color(0xff9ca3af));
    expect(find.bySemanticsLabel(RegExp('ada, offline')), findsOneWidget);
  });

  testWidgets('outside games an offline friend still shows no dot', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: NeonTheme.dark, home: const Scaffold(body: OnlineAvatar('ada', online: false, size: 40))));
    expect(find.byKey(const ValueKey('presence-offline')), findsNothing);
  });
}
