import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/features/huudspace/huud_preview_voice.dart';

class FakePreviewAudio implements PreviewAudio {
  FakePreviewAudio(this.disconnected, {this.connecting});
  final VoidCallback disconnected;
  final Completer<void>? connecting;
  bool closed = false, playing = false;
  @override
  Future<void> connect(String url, String token) async {
    await connecting?.future;
  }

  @override
  Future<void> play() async {
    playing = true;
  }

  @override
  Future<void> close() async {
    closed = true;
    playing = false;
  }
}

http.Response token(int visit) => http.Response(
    jsonEncode({
      'roomName': 'huud-test',
      'livekitUrl': 'wss://voice.test',
      'token': 'signed-$visit',
      'previewId': 'visit-$visit',
    }),
    200);

void main() {
  test('only the visible Huud plays and every stop targets its own visit',
      () async {
    final calls = <String>[];
    final audio = <FakePreviewAudio>[];
    var visit = 0;
    final api = ApiClient(client: MockClient((r) async {
      calls.add('${r.method} ${r.url.path}');
      return r.method == 'DELETE' ? http.Response('', 200) : token(++visit);
    }));
    final voice = HuudPreviewVoice(api, createAudio: (gone) {
      final room = FakePreviewAudio(gone);
      audio.add(room);
      return room;
    });
    await voice.watch('a');
    expect(audio.single.playing, isTrue);
    await voice.watch('b');
    expect(audio[0].closed, isTrue);
    expect(audio[1].playing, isTrue);
    await voice.watch('a');
    expect(audio[1].closed, isTrue);
    expect(audio[2].playing, isTrue);
    expect(calls, contains('DELETE /api/v1/huud-spaces/a/listen/visit-1'));
    expect(
        calls, isNot(contains('DELETE /api/v1/huud-spaces/a/listen/visit-3')));
    await voice.watch(null);
    expect(audio.every((a) => a.closed), isTrue);
    expect(voice.status, PreviewVoiceStatus.off);
    voice.dispose();
  });

  test('a late token from an old swipe never creates or plays an audio room',
      () async {
    final pending = Completer<http.Response>();
    final calls = <String>[];
    final audio = <FakePreviewAudio>[];
    final api = ApiClient(client: MockClient((r) async {
      calls.add('${r.method} ${r.url.path}');
      if (r.method == 'DELETE') return http.Response('', 200);
      return r.url.path.contains('/a/') ? pending.future : token(2);
    }));
    final voice = HuudPreviewVoice(api, createAudio: (gone) {
      final room = FakePreviewAudio(gone);
      audio.add(room);
      return room;
    });
    final first = voice.watch('a');
    await Future<void>.delayed(Duration.zero);
    await voice.watch('b');
    pending.complete(token(1));
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(audio, hasLength(1));
    expect(audio.single.playing, isTrue);
    expect(voice.target, 'b');
    expect(calls, contains('DELETE /api/v1/huud-spaces/a/listen/visit-1'));
    voice.dispose();
  });

  test('a late media connection cannot start playing after swiping away',
      () async {
    final connecting = Completer<void>();
    final audio = <FakePreviewAudio>[];
    var visit = 0;
    final api = ApiClient(
        client: MockClient((r) async =>
            r.method == 'DELETE' ? http.Response('', 200) : token(++visit)));
    final voice = HuudPreviewVoice(api, createAudio: (gone) {
      final room =
          FakePreviewAudio(gone, connecting: audio.isEmpty ? connecting : null);
      audio.add(room);
      return room;
    });
    final first = voice.watch('a');
    await Future<void>.delayed(Duration.zero);
    await voice.watch('b');
    connecting.complete();
    await first;
    expect(audio[0].closed, isTrue);
    expect(audio[0].playing, isFalse);
    expect(audio[1].playing, isTrue);
    voice.dispose();
  });

  test('network errors and dropped rooms retry, and disposal cancels retries',
      () {
    fakeAsync((clock) {
      final audio = <FakePreviewAudio>[];
      var requests = 0;
      final api = ApiClient(client: MockClient((r) async {
        if (r.method == 'DELETE') return http.Response('', 200);
        requests++;
        return requests == 1
            ? http.Response('{"message":"unavailable"}', 503)
            : token(requests);
      }));
      final voice = HuudPreviewVoice(api, createAudio: (gone) {
        final room = FakePreviewAudio(gone);
        audio.add(room);
        return room;
      });
      unawaited(voice.watch('a'));
      clock.flushMicrotasks();
      expect(voice.status, PreviewVoiceStatus.reconnecting);
      clock.elapse(const Duration(seconds: 2));
      clock.flushMicrotasks();
      expect(voice.status, PreviewVoiceStatus.listening);
      audio.single.disconnected();
      clock.flushMicrotasks();
      expect(audio.single.closed, isTrue);
      expect(voice.status, PreviewVoiceStatus.reconnecting);
      voice.dispose();
      clock.elapse(const Duration(minutes: 5));
      clock.flushMicrotasks();
      expect(requests, 2);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('a denied preview never connects media or retries authorization', () {
    fakeAsync((clock) {
      var calls = 0, media = 0;
      final api = ApiClient(client: MockClient((_) async {
        calls++;
        return http.Response('{"message":"not allowed"}', 403);
      }));
      final voice = HuudPreviewVoice(api, createAudio: (gone) {
        media++;
        return FakePreviewAudio(gone);
      });
      unawaited(voice.watch('private'));
      clock.flushMicrotasks();
      clock.elapse(const Duration(minutes: 2));
      expect(voice.status, PreviewVoiceStatus.unavailable);
      expect(calls, 1);
      expect(media, 0);
      voice.dispose();
    });
  });
}
