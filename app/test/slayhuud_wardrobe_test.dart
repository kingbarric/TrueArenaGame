import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/features/slayhuud/slay_models.dart';

void main() {
  final wardrobe =
      (jsonDecode(File('assets/slay_renderer/catalog.json').readAsStringSync())[
              'items'] as List)
          .cast<Map>();

  test(
      'each casual shirt replaces a full suit with a wearable shirt and trousers',
      () {
    for (final shirt
        in wardrobe.where((i) => i['id'].toString().startsWith('male-tee-'))) {
      final look = SlayLook.initial('male').equip(shirt, wardrobe: wardrobe);
      expect(look.items['shirts'], shirt['id']);
      expect(look.items['trousers'], 'male-trousers-classic');
      expect(look.items.containsKey('outfit'), isFalse);
      expect(look.items['shoes'], 'shoe-1');
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
