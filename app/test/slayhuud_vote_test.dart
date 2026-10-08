import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/slayhuud/slay_competition_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  Future<void> open(WidgetTester tester, Map<String, dynamic> state,
      List<String> posted, ThemeData theme) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(client: MockClient((request) async {
      final path = request.url.path;
      dynamic result;
      if (path.endsWith('/catalog'))
        result = {'items': []};
      else if (path.endsWith('/profile'))
        result = {'owned': []};
      else if (path.endsWith('/ballot') && request.method == 'GET')
        result = {
          'id': 'ballot',
          'entryA': 'entry-a',
          'entryB': 'entry-b',
          'imageA': '/slay/looks/look-a/snapshot',
          'imageB': '/slay/looks/look-b/snapshot'
        };
      else if (path.contains('/ballots/')) {
        posted.add(request.body);
        result = null;
      } else if (path.endsWith('/final-vote')) {
        posted.add(request.body);
        state['judged'] = true;
        result = state;
      } else
        result = state;
      return http.Response(result == null ? '' : jsonEncode(result), 200,
          headers: {'content-type': 'application/json'});
    }));
    await tester.pumpWidget(AppScope(
        state: AppState(api),
        child: MaterialApp(
            theme: theme,
            home: const SlayCompetitionScreen(competitionId: 'comp'))));
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> competition() => {
        'id': 'comp',
        'mode': 'group',
        'status': 'voting',
        'round': 1,
        'role': 'spectator',
        'theme': {
          'title': 'First Date',
          'description': 'Dress for the theme.',
          'requiredCategories': []
        },
        'entries': [],
        'serverTime': DateTime.now().toUtc().toIso8601String(),
        'rated': false
      };

  testWidgets(
      'community voting displays two anonymous looks and keeps the selected PlayHuud theme',
      (tester) async {
    final posted = <String>[];
    await open(tester, competition(), posted, NeonTheme.supercarDark);
    expect(
        Theme.of(tester.element(find.byType(SlayCompetitionScreen)))
            .extension<NeonColors>()!
            .bg,
        NeonColors.supercarDark.bg);
    await tester.tap(find.text('Start voting'));
    await tester.pumpAndSettle();
    expect(find.text('Look A'), findsOneWidget);
    expect(find.text('Look B'), findsOneWidget);
    await tester.tap(find.text('Look A'));
    await tester.pumpAndSettle();
    expect(jsonDecode(posted.single)['entryId'], 'entry-a');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'final judges choose one finalist and cannot press a second final choice',
      (tester) async {
    final state = competition()
      ..addAll({
        'mode': 'slay_or_pass',
        'role': 'judge',
        'finalRound': true,
        'judged': false,
        'entries': [
          {
            'id': 'a',
            'lookId': 'look-a',
            'image': '/slay/looks/look-a/snapshot'
          },
          {
            'id': 'b',
            'lookId': 'look-b',
            'image': '/slay/looks/look-b/snapshot'
          }
        ]
      });
    final posted = <String>[];
    await open(tester, state, posted, NeonTheme.light);
    await tester.tap(find.text('Look 1'));
    await tester.pumpAndSettle();
    expect(posted, hasLength(1));
    expect(jsonDecode(posted.single)['entryId'], 'a');
    expect(find.text('Look 2'), findsNothing);
    expect(find.text('Your final vote is in. Waiting for the other judges.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
