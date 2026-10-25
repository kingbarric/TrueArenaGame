import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:truearena/features/slayhuud/slay_stage.dart';
import 'package:truearena/theme/neon_theme.dart';

class FakeStage extends SlayStageController {
  int starts = 0;
  Completer<String>? finish;
  @override
  Future<String> showOff() {
    starts++;
    showingOff.value = true;
    finish = Completer<String>();
    return finish!.future;
  }

  @override
  Future<void> stopShowOff() async {
    showingOff.value = false;
    finish!.completeError(StateError('Show off cancelled'));
  }
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets(
      'show off waits for completion and can be cancelled without submitting',
      (tester) async {
    final stage = FakeStage(), finished = <String>[], errors = <Object>[];
    await tester.pumpWidget(MaterialApp(
        theme: NeonTheme.dark,
        home: Scaffold(
            body: SlayShowOffControl(
                controller: stage,
                onFinished: finished.add,
                onError: errors.add))));
    await tester.tap(find.text('Show off'));
    await tester.pump();
    expect(stage.starts, 0);
    stage.ready.value = true;
    await tester.pump();
    await tester.tap(find.text('Show off'));
    await tester.pump();
    expect(stage.starts, 1);
    expect(finished, isEmpty);
    await tester.tap(find.text('Stop show off'));
    await tester.pump();
    expect(finished, isEmpty);
    expect(errors, isEmpty);
    expect(find.text('Show off'), findsOneWidget);
    await tester.tap(find.text('Show off'));
    await tester.pump();
    stage.showingOff.value = false;
    stage.finish!.complete('confident');
    await tester.pump();
    expect(finished, ['confident']);
    expect(stage.starts, 2);
    expect(tester.takeException(), isNull);
  });
}
