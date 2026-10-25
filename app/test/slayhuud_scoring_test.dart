import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/dev/slay_preview_scoring.dart';

void main() {
  final catalog = Map<String, dynamic>.from(
      jsonDecode(File('assets/slay_renderer/catalog.json').readAsStringSync()));
  final fixtures =
      jsonDecode(File('../docs/fixtures/slay-scoring.json').readAsStringSync())
          as List;
  for (final fixture in fixtures) {
    test('preview matches backend: ${fixture['name']}', () {
      final theme = (catalog['themes'] as List)
          .firstWhere((t) => t['id'] == fixture['theme']);
      final score = scoreSlayPreview(Map<String, dynamic>.from(fixture['look']),
          Map<String, dynamic>.from(theme), catalog);
      expect(score, fixture['expected']);
    });
  }
  test('preview rejects an undressed look instead of returning a fake score',
      () {
    final look = Map<String, dynamic>.from(fixtures.first['look']);
    look['items'] = {'hair': 'female-hair-0'};
    final theme = Map<String, dynamic>.from((catalog['themes'] as List).first);
    expect(() => scoreSlayPreview(look, theme, catalog), throwsStateError);
  });
}
