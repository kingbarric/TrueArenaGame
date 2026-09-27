import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/compact_list_row.dart';

void main() {
  testWidgets('compact rows fit long names and actions on a narrow phone',
      (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: NeonTheme.dark,
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (var i = 0; i < 8; i++)
              CompactListRow(
                leading: const CircleAvatar(radius: 16),
                title: Text('Player $i with a very long display name',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('Item $i', maxLines: 1),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      onPressed: () {}, icon: const Icon(Icons.chat_bubble)),
                  IconButton(onPressed: () {}, icon: const Icon(Icons.call)),
                  IconButton(
                      onPressed: () {}, icon: const Icon(Icons.more_horiz)),
                ]),
              ),
          ],
        ),
      ),
    ));

    expect(
        tester.getSize(find.byType(CompactListRow).first).height, lessThan(60));
    expect(tester.getTopLeft(find.text('Item 7')).dy, lessThan(568));
    expect(tester.takeException(), isNull);
  });
}
