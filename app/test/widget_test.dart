import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/main.dart';

void main() {
  testWidgets('app boots and shows its name', (tester) async {
    await tester.pumpWidget(const TrueArenaApp());
    expect(find.text('TrueArena'), findsOneWidget);
  });
}
