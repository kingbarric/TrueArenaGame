import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/app.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/shell/main_shell.dart';
import 'package:truearena/theme/neon_theme.dart';
import 'package:truearena/widgets/hide_on_scroll_nav.dart';

void main() {
  group('bottom menu hides on scroll', () {
    Future<void> pump(WidgetTester tester, {Widget? body}) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HideOnScrollNav(
              body: body ??
                  ListView(children: [for (var i = 0; i < 60; i++) SizedBox(height: 60, child: Text('row $i'))]),
              nav: const SizedBox(height: 50, width: 200, child: Text('MENU')),
            ),
          ),
        ));

    Offset navOffset(WidgetTester tester) =>
        tester.widget<AnimatedSlide>(find.byKey(const ValueKey('hide-on-scroll-nav'))).offset;

    testWidgets('scrolling down hides it, scrolling up brings it back', (tester) async {
      await pump(tester);
      expect(navOffset(tester), Offset.zero);

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(navOffset(tester), isNot(Offset.zero), reason: 'hidden while reading down');

      await tester.drag(find.byType(ListView), const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(navOffset(tester), Offset.zero, reason: 'back as soon as you scroll up');
    });

    testWidgets('a hidden menu cannot be tapped by accident', (tester) async {
      await pump(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      final ignore = tester.widget<IgnorePointer>(
          find.ancestor(of: find.byKey(const ValueKey('hide-on-scroll-nav')), matching: find.byType(IgnorePointer)).first);
      expect(ignore.ignoring, isTrue);
    });

    testWidgets('a sideways swipe (e.g. the player-card carousel) leaves it alone', (tester) async {
      await pump(tester,
          body: PageView(children: [for (var i = 0; i < 4; i++) Center(child: Text('card $i'))]));
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
      await tester.pumpAndSettle();
      expect(navOffset(tester), Offset.zero);
    });
  });

  group('keyboard', () {
    late FocusNode focus;

    Future<void> pump(WidgetTester tester, {VoidCallback? onSend}) {
      focus = FocusNode();
      addTearDown(focus.dispose);
      return tester.pumpWidget(MaterialApp(
        builder: (context, child) => DismissKeyboardOnOutsideTap(child: child!),
        home: Scaffold(
          body: Column(children: [
            TextField(key: const ValueKey('box'), focusNode: focus),
            ElevatedButton(onPressed: onSend ?? () {}, child: const Text('Send')),
            Expanded(
              child: ListView(children: [for (var i = 0; i < 40; i++) SizedBox(height: 50, child: Text('item $i'))]),
            ),
          ]),
        ),
      ));
    }

    testWidgets('tapping outside the text box puts the keyboard away', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('box')));
      await tester.pump();
      expect(focus.hasFocus, isTrue);

      await tester.tap(find.text('item 3')); // plain content, not a control
      await tester.pump();
      expect(focus.hasFocus, isFalse);
    });

    testWidgets('dragging the list puts the keyboard away', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('box')));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
    });

    testWidgets('a button keeps the keyboard up (so Send works for the next message)', (tester) async {
      var sent = 0;
      await pump(tester, onSend: () => sent++);
      await tester.tap(find.byKey(const ValueKey('box')));
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(sent, 1);
      expect(focus.hasFocus, isTrue);
    });
  });

  testWidgets('the real app shell hides its menu when a tab scrolls down, and brings it back', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({'ta_main_tab_v2': 5}); // open on "You" (the Profile tab)
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final state = AppState(ApiClient(client: MockClient((_) async => http.Response('[]', 200))));
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(theme: NeonTheme.dark, home: const MainShell()),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    tester.takeException(); // fonts/network aren't what's under test

    Offset nav() => tester.widget<AnimatedSlide>(find.byKey(const ValueKey('hide-on-scroll-nav'))).offset;
    expect(nav(), Offset.zero);

    final list = find.byType(ListView).hitTestable().first;
    await tester.drag(list, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 400));
    expect(nav(), isNot(Offset.zero), reason: 'scrolling the page down hides the menu');

    await tester.drag(list, const Offset(0, 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(nav(), Offset.zero, reason: 'scrolling back up shows it again');
  });
}
