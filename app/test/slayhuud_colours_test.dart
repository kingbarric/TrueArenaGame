import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:truearena/features/slayhuud/slay_colour_picker.dart';
import 'package:truearena/features/slayhuud/slay_models.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  test(
      'saved colours persist and reset only when their item is replaced or removed',
      () {
    final look = SlayLook.initial('male').copy(items: {
      'shirts': 'male-tee-relaxed',
      'trousers': 'male-trousers-cargo',
      'shoes': 'shoe-1'
    }).copy(itemColours: {'shirts': 'red', 'shoes': 'blue'});
    final restored = SlayLook.fromJson(jsonDecode(jsonEncode(look.toJson())));
    expect(restored.itemColours, look.itemColours);
    expect(restored.copy(pose: 'editorial').itemColours, look.itemColours);
    final changed =
        restored.equip({'category': 'shirts', 'id': 'male-tee-polo'});
    expect(changed.itemColours, {'shoes': 'blue'});
    expect(changed.copy(items: {...changed.items}..remove('shoes')).itemColours,
        isEmpty);
    expect(
        SlayLook.fromJson({...look.toJson()}..remove('itemColours'))
            .itemColours,
        isEmpty);
  });
  testWidgets(
      'colour swatches choose dye and restore original without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 550);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final chosen = <String?>[];
    await tester.pumpWidget(MaterialApp(
        theme: NeonTheme.dark,
        home: Scaffold(
            body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
                child: SlayColourPicker(
                    palette: const {'red': '#a53541', 'blue': '#48879a'},
                    selected: 'red',
                    onChanged: chosen.add)))));
    await tester.tap(find.byTooltip('blue'));
    await tester.pump();
    await tester.tap(find.byTooltip('Original colour'));
    await tester.pump();
    expect(chosen, ['blue', null]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('colour buttons disable during runway and wardrobe loading',
      (tester) async {
    var called = false;
    await tester.pumpWidget(MaterialApp(
        theme: NeonTheme.dark,
        home: Scaffold(
            body: SlayColourPicker(
                palette: const {'red': '#a53541'},
                selected: null,
                enabled: false,
                onChanged: (_) => called = true))));
    await tester.tap(find.byTooltip('red'));
    expect(called, isFalse);
  });
}
