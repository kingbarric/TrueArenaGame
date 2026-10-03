import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/features/ludo/ludo_lobby_screen.dart';

void main() {
  testWidgets('two-player start asks for four or eight pieces', (tester) async {
    int? selection;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              selection = await showLudoPieceCountDialog(context);
            },
            child: const Text('Start game'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('Start game'));
    await tester.pumpAndSettle();
    expect(find.text('Two-player Ludo'), findsOneWidget);
    expect(
        tester
            .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
            .selected,
        {8});
    await tester.tap(find.text('4 pieces'));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(selection, 4);
  });
}
