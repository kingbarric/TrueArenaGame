import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:truearena/core/hangout_state.dart';
import 'package:truearena/features/calls/call_screen.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/persistent_hangout.dart';

class _VoiceFixture extends StatefulWidget {
  const _VoiceFixture(this.onDispose);
  final VoidCallback onDispose;
  @override
  State<_VoiceFixture> createState() => _VoiceFixtureState();
}

class _VoiceFixtureState extends State<_VoiceFixture> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: TextButton(
        onPressed: HangoutState.instance.minimize,
        child: const Text('Minimize voice'),
      ));
}

void main() {
  final voice = HangoutState.instance;
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    voice.clear();
  });
  tearDown(voice.clear);
  testWidgets(
      'call survives navigation, game results and another game until explicitly left',
      (tester) async {
    var disconnected = 0;
    await tester.pumpWidget(MaterialApp(
      theme: NeonTheme.dark,
      navigatorKey: voice.navigationKey,
      builder: (ctx, child) => PersistentHangout(child: child!),
      home: const Scaffold(body: Text('Huud')),
    ));
    voice.open(_VoiceFixture(() => disconnected++), 'group-one', 'Friends');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minimize voice'));
    await tester.pumpAndSettle();
    expect(find.text('Huud'), findsOneWidget);
    expect(find.byTooltip('Leave call'), findsOneWidget);
    for (final screen in [
      'Game A',
      'Result',
      'Profile',
      'Tournament',
      'Game B'
    ]) {
      voice.navigationKey.currentState!.push(
          MaterialPageRoute(builder: (_) => Scaffold(body: Text(screen))));
      await tester.pumpAndSettle();
      expect(find.text(screen), findsOneWidget);
      expect(disconnected, 0);
      expect(voice.roomName, 'group-one');
    }
    voice.show();
    await tester.pumpAndSettle();
    expect(find.text('Minimize voice'), findsOneWidget);
    expect(disconnected, 0);
    voice.clear();
    await tester.pumpAndSettle();
    expect(disconnected, 1);
  });
  testWidgets(
      'switching calls requires explicit Leave & Join and Cancel keeps current call',
      (tester) async {
    var left = 0;
    voice.open(const SizedBox(), 'first', 'Friends');
    voice.leave = () async {
      left++;
      voice.clear();
    };
    await tester.pumpWidget(MaterialApp(
        theme: NeonTheme.dark,
        home: Builder(
            builder: (ctx) => TextButton(
                  onPressed: () => CallScreen.open(
                      ctx,
                      const CallScreen(
                          roomName: 'second',
                          token: 'token',
                          livekitUrl: 'ws://localhost',
                          title: 'Second')),
                  child: const Text('Join second'),
                ))));
    await tester.tap(find.text('Join second'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(left, 0);
    expect(voice.roomName, 'first');
    await tester.tap(find.text('Join second'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave & Join'));
    await tester.pumpAndSettle();
    expect(left, 1);
    expect(voice.roomName, 'second');
  });
  testWidgets(
      'cancelled host transfer or failed leave cannot open a second call',
      (tester) async {
    voice.open(const SizedBox(), 'first', 'Friends');
    voice.leave = () async {};
    await tester.pumpWidget(MaterialApp(
        theme: NeonTheme.dark,
        home: Builder(
            builder: (ctx) => TextButton(
                  onPressed: () => CallScreen.open(
                      ctx,
                      const CallScreen(
                          roomName: 'second',
                          token: 'token',
                          livekitUrl: 'ws://localhost',
                          title: 'Second')),
                  child: const Text('Join second'),
                ))));
    await tester.tap(find.text('Join second'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave & Join'));
    await tester.pumpAndSettle();
    expect(voice.roomName, 'first');
  });
}
