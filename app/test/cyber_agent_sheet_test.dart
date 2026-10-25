import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/cyber_agent_sheet.dart';
import 'package:truearena/widgets/cyber_agent_difficulty.dart';

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
    expect(find.text('Rookie'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Legend'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('cyber-agent-name')), 'Sharp Kofi');
    await tester.tap(find.byKey(const ValueKey('segment-hard')));
    await tester.tap(find.byKey(const ValueKey('confirm-cyber-agent')));
    await tester.pumpAndSettle();

    expect(selected?.name, 'Sharp Kofi');
    expect(selected?.difficulty, 'hard');
  });

  testWidgets(
      'three-dot level control supports taps, dragging and accessible labels',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      var value = 'medium';
      await tester.pumpWidget(MaterialApp(
        theme: NeonTheme.dark,
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
          return CyberAgentDifficulty(
              value: value, onChanged: (next) => setState(() => value = next));
        })),
      ));
      expect(find.bySemanticsLabel('Pro, Medium difficulty'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('segment-easy')));
      await tester.pumpAndSettle();
      expect(value, 'easy');
      await tester.drag(
          find.byType(CyberAgentDifficulty), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(value, 'hard');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('level control fits a small screen with large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: NeonTheme.light,
      home: const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
            body: Padding(
          padding: EdgeInsets.all(22),
          child: CyberAgentDifficulty(value: 'medium', onChanged: null),
        )),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Rookie'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Legend'), findsOneWidget);
  });
}
