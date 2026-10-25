import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/huudspace/huud_home_screen.dart';
import 'package:truearena/features/huudspace/huud_lounge.dart';
import 'package:truearena/features/huudspace/huud_space_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> room(String id, {bool member = false}) => {
      'id': id,
      'name': 'Huud $id',
      'privacy': 'public',
      'memberCount': 8,
      'youAreIn': member,
      'live': true,
      'liveCount': 8,
      'youOwn': false,
      'host': {
        'userId': 'host',
        'displayName': 'Beverly',
        'username': 'beverly',
        'host': true,
        'here': true
      },
      'members': [
        for (var i = 0; i < 6; i++)
          {
            'userId': 'person-$i',
            'displayName': 'Person $i',
            'username': 'person$i',
            'here': true,
          }
      ],
    };

Future<void> open(
    WidgetTester t, Future<http.Response> Function(http.Request) routes) async {
  await t.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final api = ApiClient(client: MockClient(routes))..bearer = 'discover-test';
  final state = AppState(api)
    ..user = const UserView(id: 'me', displayName: 'Riley', isGuest: false)
    ..identity = Identity.account;
  await t.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(theme: NeonTheme.dark, home: const HuudHomeScreen())));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> discover(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const ValueKey('huud-list-discover')));
  await t.tap(find.byKey(const ValueKey('huud-list-discover')));
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    HuudLounge.debugScenePlaceholder = true;
    addTearDown(() => HuudLounge.debugScenePlaceholder = false);
  });
  testWidgets(
      'Discover loads on demand, excludes memberships, and shows three faces plus the rest',
      (t) async {
    var discoveries = 0;
    await open(t, (r) async {
      if (r.url.path.endsWith('/mine')) return json([room('known')]);
      if (r.url.path.endsWith('/live')) {
        discoveries++;
        return json([room('known'), room('joined', member: true), room('new')]);
      }
      return json([]);
    });
    expect(discoveries, 0);
    expect(find.byKey(const ValueKey('member-huud-known')), findsOneWidget);
    await discover(t);
    expect(discoveries, 1);
    expect(find.byKey(const ValueKey('live-huud-known')), findsNothing);
    expect(find.byKey(const ValueKey('live-huud-joined')), findsNothing);
    expect(find.byKey(const ValueKey('live-huud-new')), findsOneWidget);
    final faces = find.byKey(const ValueKey('live-members-new'));
    expect(
        find.descendant(of: faces, matching: find.text('P')), findsNWidgets(3));
    expect(
        find.descendant(of: faces, matching: find.text('+5')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('huud-list-joined')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('member-huud-known')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-huud-new')), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'suggestions recover from an error and refresh while the tab stays open',
      (t) async {
    var discoveries = 0;
    await open(t, (r) async {
      if (r.url.path.endsWith('/mine')) return json([]);
      if (r.url.path.endsWith('/live')) {
        discoveries++;
        if (discoveries == 1) return json({'message': 'Unavailable'}, 503);
        return json(discoveries == 2 ? [] : [room('arrived')]);
      }
      return json([]);
    });
    await discover(t);
    expect(find.text("Couldn't load suggestions"), findsOneWidget);
    await t.ensureVisible(find.text('Try again'));
    await t.tap(find.text('Try again'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('More Huuds soon'), findsOneWidget);
    await t.pump(const Duration(seconds: 20));
    await t.pump();
    expect(find.byKey(const ValueKey('live-huud-arrived')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'joining a suggestion uses the real join action once and updates joined Huuds',
      (t) async {
    var joins = 0;
    var joined = false;
    final pending = Completer<http.Response>();
    await open(t, (r) async {
      if (r.url.path.endsWith('/mine')) {
        return json(joined ? [room('new', member: true)] : []);
      }
      if (r.url.path.endsWith('/live')) {
        return json([room('new', member: joined)]);
      }
      if (r.method == 'POST' && r.url.path.endsWith('/new/join')) {
        joins++;
        return pending.future;
      }
      if (r.url.path.endsWith('/new')) {
        return json({
          ...room('new', member: true),
          'code': 'ABC234',
          'status': 'active',
          'youAreHost': false,
          'voiceRoom': null,
        });
      }
      return json([]);
    });
    await discover(t);
    await t.ensureVisible(find.byKey(const ValueKey('live-enter-new')));
    await t.tap(find.byKey(const ValueKey('live-enter-new')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('live-enter-new')));
    await t.pump();
    expect(joins, 1);
    joined = true;
    pending.complete(json({
      ...room('new', member: true),
      'code': 'ABC234',
      'status': 'active',
      'youAreHost': false
    }));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(HuudSpaceScreen), findsOneWidget);
    Navigator.of(t.element(find.byType(HuudSpaceScreen))).pop();
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(HuudHomeScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('live-huud-new')), findsNothing);
    await t.scrollUntilVisible(
        find.byKey(const ValueKey('huud-list-joined')), -220,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.byKey(const ValueKey('huud-list-joined')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('member-huud-new')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
