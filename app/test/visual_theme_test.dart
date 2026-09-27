import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/app.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/profile/profile_screen.dart';
import 'package:truearena/features/settings/settings_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('players can switch between all three visual themes',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(ApiClient())..themeMode = ThemeMode.dark;
    await tester.pumpWidget(TrueArenaApp(state: state));
    TrueArenaApp.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    await tester.pumpAndSettle();

    expect(state.visualTheme, VisualTheme.palmWine);
    await tester.scrollUntilVisible(find.text('Nebula'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Nebula'));
    await tester.pumpAndSettle();
    expect(state.visualTheme, VisualTheme.nebula);
    expect(
        Theme.of(tester.element(find.byType(SettingsScreen)))
            .extension<NeonColors>()!
            .bg,
        NeonColors.nebulaDark.bg);
    expect((await SharedPreferences.getInstance()).getString('ta_visual_theme'),
        VisualTheme.nebula.name);

    await state.setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(
        Theme.of(tester.element(find.byType(SettingsScreen)))
            .extension<NeonColors>()!
            .bg,
        NeonColors.nebulaLight.bg);

    await tester.ensureVisible(find.text('Supercar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supercar'));
    await tester.pumpAndSettle();
    expect(state.visualTheme, VisualTheme.supercar);
    expect(
        Theme.of(tester.element(find.byType(SettingsScreen)))
            .extension<NeonColors>()!
            .bg,
        NeonColors.supercarLight.bg);
    expect((await SharedPreferences.getInstance()).getString('ta_visual_theme'),
        VisualTheme.supercar.name);

    await state.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(
        Theme.of(tester.element(find.byType(SettingsScreen)))
            .extension<NeonColors>()!
            .bg,
        NeonColors.supercarDark.bg);

    await tester.ensureVisible(find.text('Palm Wine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Palm Wine'));
    await tester.pumpAndSettle();
    expect(state.visualTheme, VisualTheme.palmWine);
    expect(
        Theme.of(tester.element(find.byType(SettingsScreen)))
            .extension<NeonColors>()!
            .bg,
        NeonColors.dark.bg);
  });

  testWidgets('three theme previews stay usable on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    VisualTheme selected = VisualTheme.palmWine;
    await tester.pumpWidget(MaterialApp(
      theme: NeonTheme.dark,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: VisualThemePicker(
              value: selected,
              onChanged: (choice) => selected = choice,
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Supercar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supercar'));
    expect(selected, VisualTheme.supercar);
    expect(tester.takeException(), isNull);
  });

  testWidgets('players can change the visual theme from Profile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(ApiClient())..themeMode = ThemeMode.dark;
    await tester.pumpWidget(TrueArenaApp(state: state));
    TrueArenaApp.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('APPEARANCE'), findsOneWidget);
    await tester.ensureVisible(find.text('Supercar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Supercar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.visualTheme, VisualTheme.supercar);
    expect((await SharedPreferences.getInstance()).getString('ta_visual_theme'),
        VisualTheme.supercar.name);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Nebula routes keep an opaque backdrop during navigation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: NeonTheme.nebulaLight,
      home: Builder(builder: (context) {
        return Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Second screen')),
            )),
            child: const Text('Open'),
          ),
        );
      }),
    ));

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final routeBackdrops = tester
        .widgetList<DecoratedBox>(find.ancestor(
          of: find.text('Second screen'),
          matching: find.byType(DecoratedBox),
        ))
        .toList();
    expect(
      routeBackdrops.any((box) {
        final decoration = box.decoration;
        return decoration is BoxDecoration &&
            decoration.gradient ==
                NeonTheme.backdrop(NeonDesignKind.nebula, Brightness.light);
      }),
      isTrue,
    );
    expect(
      find.ancestor(
        of: find.text('Second screen'),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
