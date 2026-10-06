import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/widgets/idle_wiggle.dart';

void main() {
  Finder rotation() => find.descendant(
      of: find.byType(IdleWiggle), matching: find.byType(Transform));

  testWidgets('sits still, then gives a little shake at a random moment',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: IdleWiggle(
        minGap: Duration(seconds: 1),
        maxGap: Duration(seconds: 2),
        child: SizedBox(width: 40, height: 40),
      ),
    ));
    expect(rotation(), findsNothing);

    // Somewhere in the next two seconds it starts; mid-shake it's tilted.
    var shook = false;
    for (var i = 0; i < 30 && !shook; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      shook = rotation().evaluate().isNotEmpty;
    }
    expect(shook, isTrue);

    await tester.pump(const Duration(seconds: 1));
    expect(rotation(), findsNothing, reason: 'settles back when done');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stays still when the device asks for reduced motion',
      (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        home: IdleWiggle(
          minGap: Duration(milliseconds: 100),
          maxGap: Duration(milliseconds: 200),
          child: SizedBox(width: 40, height: 40),
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(rotation(), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
