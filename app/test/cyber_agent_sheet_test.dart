import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/cyber_agent_sheet.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('adds a room-scoped agent with chosen name and difficulty',
      (tester) async {
    AgentChoice? selected;
    await tester.pumpWidget(MaterialApp(
      theme: NeonTheme.dark,
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              selected =
                  await showCyberAgentPicker(context, defaultName: 'Cyber 2');
            },
            child: const Text('Open'),
          );
        }),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('ADD A CYBER AGENT'), findsOneWidget);
    expect(find.text('YOUR CYBER AGENTS'), findsNothing);
    expect(find.text('Delete'), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey('cyber-agent-name')), 'Sharp Kofi');
    await tester.tap(find.byKey(const ValueKey('segment-hard')));
    await tester.tap(find.byKey(const ValueKey('confirm-cyber-agent')));
    await tester.pumpAndSettle();

    expect(selected?.name, 'Sharp Kofi');
    expect(selected?.difficulty, 'hard');
  });
}
