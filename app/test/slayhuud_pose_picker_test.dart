import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:truearena/features/slayhuud/slay_pose_picker.dart';
import 'package:truearena/features/slayhuud/slay_theme.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('four labelled finishes retain their distinct saved pose IDs',
      (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(MaterialApp(
        theme: NeonTheme.dark,
        home: Scaffold(
            body: SlayPosePicker(
                selected: 'editorial',
                available: slayPoses.keys.toList(),
                onSelected: selected.add))));
    expect(find.textContaining('Every pose starts with a catwalk'),
        findsOneWidget);
    final pills = tester.widgetList<SlayPill>(find.byType(SlayPill)).toList();
    expect(pills.length, 4);
    expect(pills.where((pill) => pill.selected).single.label, 'Cover star');
    for (final pose in slayPoses.entries) {
      await tester.tap(find.text(pose.value.label));
      await tester.pump();
    }
    expect(selected, ['signature', 'confident', 'editorial', 'celebrate']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'does not offer a finishing pose absent from the loaded catalogue',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: NeonTheme.dark,
        home: Scaffold(
            body: SlayPosePicker(
                selected: 'signature',
                available: const ['signature', 'confident'],
                onSelected: (_) {}))));
    expect(find.text('Cover star'), findsNothing);
    expect(find.text('Victory'), findsNothing);
    expect(find.byType(SlayPill), findsNWidgets(2));
  });
}
