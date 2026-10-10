import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/features/slayhuud/slay_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cache;
  setUp(
      () async => cache = await Directory.systemTemp.createTemp('slay-assets'));
  tearDown(() => cache.delete(recursive: true));

  final dress = List<int>.generate(64, (i) => i);
  Map<String, dynamic> catalog() => {
        'assets': {
          'base': 'https://cdn.test/slay/',
          'files': {
            'assets/female.glb': {
              'name': 'female.aaaa.glb',
              'sha256': 'unused',
              'bytes': 1,
              'bundled': true
            },
            'assets/dress.glb': {
              'name': 'dress.bbbb.glb',
              'sha256': sha256.convert(dress).toString(),
              'bytes': dress.length,
              'bundled': false
            },
          }
        }
      };

  test('bundled starter art is served from the app, not the network', () async {
    final assets = SlayAssets.test(
        MockClient((_) async => fail('starter art must not download')), cache)
      ..configure(catalog());
    final bytes = await assets.bytesFor('assets/female.glb');
    final starter = File('assets/slay_renderer/starter/female.glb');
    expect(bytes, await starter.readAsBytes());
  });

  test('other art downloads once by hashed name and is then read from disk',
      () async {
    final requested = <Uri>[];
    final assets = SlayAssets.test(MockClient((request) async {
      requested.add(request.url);
      return http.Response.bytes(dress, 200);
    }), cache)
      ..configure(catalog());
    expect(await assets.bytesFor('assets/dress.glb'), dress);
    expect(await assets.bytesFor('assets/dress.glb'), dress);
    expect(requested, [Uri.parse('https://cdn.test/slay/dress.bbbb.glb')]);
  });

  test('a download that fails its integrity check is never cached or served',
      () async {
    final assets = SlayAssets.test(
        MockClient((_) async =>
            http.Response.bytes(List<int>.filled(dress.length, 7), 200)),
        cache)
      ..configure(catalog());
    await expectLater(
        assets.bytesFor('assets/dress.glb'), throwsA(isA<HttpException>()));
    expect(cache.listSync(), isEmpty);
  });

  test('art outside the manifest is not served', () async {
    final assets =
        SlayAssets.test(MockClient((_) async => fail('no fetch')), cache)
          ..configure(catalog());
    expect(await assets.bytesFor('assets/unknown.glb'), isNull);
  });
}
