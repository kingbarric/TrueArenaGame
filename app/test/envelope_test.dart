import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/core/contract/envelope.dart';

void main() {
  test('golden contract frames round-trip', () {
    final dir = Directory('../shared/contract/testdata');
    expect(dir.existsSync(), isTrue,
        reason: 'run from app/ with the repo checked out');

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(files.length, greaterThanOrEqualTo(2));

    for (final f in files) {
      final original = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final env = Envelope.fromJson(original);
      final reencoded = env.toJson();

      expect(reencoded['v'], original['v'], reason: f.path);
      expect(reencoded['type'], original['type'], reason: f.path);
      expect(reencoded['ts'], original['ts'], reason: f.path);
      expect(reencoded['seq'], original['seq'], reason: f.path);
    }
  });
}
