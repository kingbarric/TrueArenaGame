import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/hangout_state.dart';
import 'package:truearena/features/huudspace/huud_preview_voice.dart';
import 'package:truearena/features/huudspace/huud_lounge.dart';
import 'package:truearena/features/huudspace/huud_space_models.dart';
import 'package:truearena/features/huudspace/huud_swipe_screen.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'huud_preview_voice_test.dart' show FakePreviewAudio;

Future<void> frames(WidgetTester tester) async {
  // The Live badge intentionally keeps pulsing; wait for async work, not idle animation.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    HangoutState.instance.clear();
    HuudLounge.debugScenePlaceholder = true;
  });
  tearDown(() {
    HangoutState.instance.clear();
    HuudLounge.debugScenePlaceholder = false;
  });
  final rooms = [
    for (final id in ['a', 'b'])
      LiveHuud(
        id: id,
        name: 'Huud $id',
        privacy: HuudPrivacy.public,
        memberCount: 2,
        members: const [],
        youAreIn: false,
      )
  ];

  Future<List<String>> pump(
      WidgetTester tester, List<FakePreviewAudio> audio, {bool denied = false}) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final calls = <String>[];
    final api = ApiClient(client: MockClient((r) async {
      calls.add('${r.method} ${r.url.path}');
      if (r.method == 'DELETE') return http.Response('', 200);
      if (r.url.path.endsWith('/join')) expect(audio.every((a) => a.closed), isTrue);
      if (denied) return http.Response('{"message":"not available"}', 403);
      if (r.url.path.endsWith('/listen'))
        return http.Response(
            jsonEncode({
              'token': 'signed',
              'livekitUrl': 'wss://test',
              'previewId': 'visit-${calls.length}',
            }),
            200);
      final id = r.url.pathSegments[3];
      return http.Response(
          jsonEncode({
            'id': id,
            'name': 'Huud $id',
            'privacy': 'public',
            'status': 'active',
            'live': true,
            'youAreIn': false,
            'members': [],
            'requests': [],
          }),
          200);
    }));
    await tester.pumpWidget(AppScope(
        state: AppState(api),
        child: MaterialApp(
          theme: NeonTheme.light,
          home: HuudSwipeScreen(
              huuds: rooms,
              previewVoiceFactory: (api) =>
                  HuudPreviewVoice(api, createAudio: (gone) {
                    final session = FakePreviewAudio(gone);
                    audio.add(session);
                    return session;
                  })),
        )));
    await frames(tester);
    return calls;
  }

  testWidgets(
      'swiping switches receive-only audio; mute and background stop it',
      (tester) async {
    final audio = <FakePreviewAudio>[];
    final calls = await pump(tester, audio);
    expect(find.text('Listening live · your mic is off'), findsOneWidget);
    expect(audio.single.playing, isTrue);
    expect(calls.any((c) => c.endsWith('/join')), isFalse);
    expect(calls.any((c) => c.startsWith('GET /api/v1/huud-spaces/')), isFalse);
    await tester.fling(
        find.byKey(const ValueKey('huud-swipe')), const Offset(0, -600), 2000);
    await frames(tester);
    expect(audio[0].closed, isTrue);
    expect(audio.last.playing, isTrue);
    await tester.tap(find.byKey(const ValueKey('swipe-sound-b')));
    await frames(tester);
    expect(audio.last.closed, isTrue);
    expect(find.text('Sound off · your mic stays off'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('swipe-sound-b')));
    await frames(tester);
    expect(audio.last.playing, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await frames(tester);
    expect(audio.every((a) => a.closed), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await frames(tester);
    expect(audio.last.playing, isTrue);
    final nav = Navigator.of(tester.element(find.byType(HuudSwipeScreen)));
    nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Other screen'))));
    await frames(tester);
    expect(audio.every((a) => a.closed), isTrue);
    nav.pop();
    await frames(tester);
    expect(audio.last.playing, isTrue);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    expect(audio.every((a) => a.closed), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an existing call is preserved and preview sound waits',
      (tester) async {
    HangoutState.instance.open(const SizedBox(), 'dm-call', 'Friend');
    final audio = <FakePreviewAudio>[];
    await pump(tester, audio);
    expect(audio, isEmpty);
    expect(HangoutState.instance.roomName, 'dm-call');
    expect(find.text('Preview audio paused during your call'), findsOneWidget);
    HangoutState.instance.clear();
    await frames(tester);
    expect(audio.single.playing, isTrue);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });
  testWidgets('entering stops preview sound before sending the join request', (tester) async {
    final audio = <FakePreviewAudio>[];
    final calls = await pump(tester, audio);
    await tester.tap(find.byKey(const ValueKey('swipe-enter-a')));
    await frames(tester);
    expect(audio.every((a) => a.closed), isTrue);
    expect(calls.where((c) => c == 'POST /api/v1/huud-spaces/a/join'), hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable Huuds stop audio and do not keep saying connecting', (tester) async {
    final audio = <FakePreviewAudio>[];
    await pump(tester, audio, denied: true);
    expect(audio, isEmpty);
    expect(find.text('This Huud is no longer available'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

}
