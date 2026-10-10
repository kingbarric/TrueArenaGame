import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/features/slayhuud/slay_models.dart';
import 'package:truearena/features/slayhuud/slay_wardrobe.dart';

void main() {
  final catalog = Map<String, dynamic>.from(
      jsonDecode(File('assets/slay_renderer/catalog.json').readAsStringSync()));
  for (final body in ['female', 'male']) {
    test('$body clothing appears exactly once across all visible groups', () {
      final wardrobe = SlayWardrobe(catalog, body), all = <String>[];
      for (final category in wardrobe.categories) {
        final groups = wardrobe.groupsFor(category);
        if (!SlayWardrobe.clothing.contains(category)) continue;
        expect(groups, isNotEmpty);
        expect(groups, isNot(contains('All')));
        for (final group in groups) {
          final items = wardrobe.itemsFor(category, group);
          expect(items, isNotEmpty, reason: 'empty groups must disappear');
          all.addAll(items.map((i) => i['id'] as String));
        }
      }
      final clothing = wardrobe.items
          .where((i) => SlayWardrobe.clothing.contains(wardrobe.category(i)));
      expect(all.length, clothing.length);
      expect(all.toSet().length, all.length);
    });
  }
  test(
      'identical aliases are merged and existing saved selections keep their category',
      () {
    final wardrobe = SlayWardrobe(catalog, 'female');
    expect(wardrobe.items.any((i) => i['id'] == 'female-dress-collection-9'),
        isFalse);
    expect(wardrobe.items.any((i) => i['id'] == 'female-trousers-collection-1'),
        isFalse);
    expect(
        wardrobe.canonicalId('female-dress-collection-9'), 'female-essential');
    expect(wardrobe.categoryForId('female-essential'), 'dress');
    expect(wardrobe.categoryForId('female-dress-collection-9'), 'dress');
    expect(
        wardrobe
            .itemsFor('outfit')
            .every((i) => !i['name'].toString().contains('Dress')),
        isTrue);
    expect(wardrobe.groupsFor('tops'), isNot(contains('Party')));
    expect(wardrobe.groupsFor('tops'), isNot(contains('Formal')));
    expect(wardrobe.categories, isNot(contains('shirts')));
    final alias = SlayLook.initial().equip((catalog['items'] as List)
        .firstWhere((i) => i['id'] == 'female-dress-collection-9'));
    expect(alias.isDressed, isTrue);
    expect(alias.items['dress'], 'female-dress-collection-9');
  });
  test('a category disappears after its sole duplicate is merged', () {
    final catalog = <String, dynamic>{
      'items': [
        {
          'id': 'dress',
          'category': 'dress',
          'body': 'female',
          'assetUrl': 'same.glb',
          'styleTags': ['casual', 'romantic']
        },
        {
          'id': 'duplicate',
          'category': 'outfit',
          'body': 'female',
          'assetUrl': 'same.glb',
          'styleTags': ['formal']
        },
        {
          'id': 'missing',
          'category': 'shirts',
          'body': 'female',
          'assetUrl': null,
          'styleTags': ['corporate']
        },
      ]
    };
    final wardrobe = SlayWardrobe(catalog, 'female');
    expect(wardrobe.categories, {'dress'});
    expect(wardrobe.groupsFor('outfit'), isEmpty);
    expect(wardrobe.groupsFor('dress'), ['Casual']);
    expect(wardrobe.canonicalId('duplicate'), 'dress');
    expect(wardrobe.categoryForId('duplicate'), 'dress');
  });
  test('corporate and traditional briefs have one clear home', () {
    expect(
        slayPrimaryStyle({
          'styleTags': ['casual', 'corporate', 'formal']
        }),
        'Corporate');
    expect(
        slayPrimaryStyle({
          'styleTags': ['romantic', 'traditional', 'bridal']
        }),
        'Traditional');
    expect(
        slayPrimaryStyle({
          'styleTags': ['romantic', 'party', 'elegant']
        }),
        'Date Night');
  });
}
