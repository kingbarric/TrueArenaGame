import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/table_chat.dart';

void main() {
  testWidgets('new comment marks collapsed chat until it is opened',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    Widget screen(List<TableChatLine> lines) => MaterialApp(
          theme: NeonTheme.dark,
          home: Scaffold(
            body: TableChatPanel(
              lines: lines,
              controller: controller,
              onSend: () {},
              spectatorCount: 1,
              amSpectator: false,
            ),
          ),
        );

    await tester.pumpWidget(screen(const []));
    expect(find.byKey(const ValueKey('unread-comment')), findsNothing);

    await tester.pumpWidget(screen(const [
      TableChatLine(who: 'Viewer', text: 'Good move', isSpectator: true),
    ]));
    expect(find.byKey(const ValueKey('unread-comment')), findsOneWidget);

    await tester.tap(find.text('CHAT · 1'));
    await tester.pump();
    expect(find.byKey(const ValueKey('unread-comment')), findsNothing);
    expect(find.textContaining('Good move', findRichText: true), findsWidgets);
  });
}
