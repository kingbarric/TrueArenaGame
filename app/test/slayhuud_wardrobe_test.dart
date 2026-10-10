import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/features/slayhuud/slay_models.dart';

void main() {
  final wardrobe =
      (jsonDecode(File('assets/slay_renderer/catalog.json').readAsStringSync())[
              'items'] as List)
          .cast<Map>();

  test('shirts and trousers are chosen separately from the underwear start',
      () {
    for (final shirt
        in wardrobe.where((i) => i['id'].toString().startsWith('male-tee-'))) {
      final start = SlayLook.initial('male');
      expect(start.items, {'hair': 'male-hair-0'});
      expect(start.isDressed, isFalse);
      final look = start.equip(shirt);
      expect(look.items['shirts'], shirt['id']);
      expect(look.items.containsKey('trousers'), isFalse);
      expect(look.isDressed, isFalse);
      final dressed = look.equip(
          wardrobe.firstWhere((i) => i['id'] == 'male-trousers-classic'));
      expect(dressed.isDressed, isTrue);
      expect(look.items.containsKey('outfit'), isFalse);
      expect(look.items.containsKey('shoes'), isFalse);
      final restored =
          look.equip(wardrobe.firstWhere((i) => i['id'] == 'male-dinner-suit'));
      expect(restored.items.containsKey('shirts'), isFalse);
      expect(restored.items.containsKey('trousers'), isFalse);
    }
  });

  test('changing a shirt preserves selected bottoms and optional accessories',
      () {
    final look = SlayLook.initial('male').copy(items: {
      'tops': 'old-top',
      'skirts': 'chosen-bottom',
      'watches': 'watch-gold'
    }).equip(wardrobe.firstWhere((i) => i['id'] == 'male-tee-polo'),
        wardrobe: wardrobe);
    expect(look.items['skirts'], 'chosen-bottom');
    expect(look.items['watches'], 'watch-gold');
    expect(look.items.containsKey('trousers'), isFalse);
    expect(look.items.containsKey('tops'), isFalse);
  });

  test('female sets include ten extra choices with both free and priced items',
      () {
    for (final category in ['dress', 'skirts', 'tops', 'trousers']) {
      final choices = wardrobe
          .where((i) =>
              i['id'].toString().startsWith('female-$category-collection-'))
          .toList();
      expect(choices, hasLength(10));
      expect(choices.where((i) => i['isDefault'] == true), hasLength(4));
      expect(
          choices.where(
              (i) => i['isDefault'] == false && (i['coinCost'] as int) > 0),
          hasLength(6));
      expect(choices.every((i) => i['assetUrl'] != null), isTrue);
      expect(
          choices.every(
              (i) => slayStyleGroups.keys.any((g) => slayMatchesStyle(i, g))),
          isTrue);
    }
    final top =
        wardrobe.firstWhere((i) => i['id'] == 'female-tops-collection-1');
    final skirt =
        wardrobe.firstWhere((i) => i['id'] == 'female-skirts-collection-1');
    final look = SlayLook.initial().equip(top).equip(skirt);
    expect(look.isDressed, isTrue);
    expect(slayMatchesStyle(top, 'Casual'), isTrue);
    expect(slayMatchesStyle(top, 'Corporate'), isFalse);
    expect(slayMatchesStyle(top, 'All'), isFalse);
  });

  test('optional beauty and accessories survive a look save and reload', () {
    var look = SlayLook.initial();
    for (final id in [
      'female-eyes-green',
      'female-lipstick-plum',
      'female-earrings-pearls',
      'female-bag-handbag',
      'watch-smart'
    ]) {
      look = look.equip(wardrobe.firstWhere((i) => i['id'] == id));
    }
    final restored = SlayLook.fromJson(jsonDecode(jsonEncode(look.toJson())));
    expect(restored.items, look.items);
    final removed = restored.copy(items: {...restored.items}..remove('eyes'));
    expect(removed.items.containsKey('eyes'), isFalse);
    expect(removed.items['makeup'], 'female-lipstick-plum');
    expect(restored.items['eyes'], 'female-eyes-green');
  });
}
