import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/features/settings/age_safety_screen.dart';

Map<String, dynamic> status(
        {bool enforced = true, String? band, bool? allowed}) =>
    {
      'enforced': enforced,
      'declarationRequired': band == null,
      'canAccess': allowed ?? (!enforced || band == 'ADULT'),
      'minimumAge': 18,
      'ageBand': band,
      'countryCode': band == null ? null : 'GB',
      'source': band == null ? null : 'self_declared',
      'restriction':
          band == null ? 'AGE_DECLARATION_REQUIRED' : 'TEEN_ACCESS_NOT_ENABLED',
      'teenAccessEnabled': false,
      'countries': [
        {'code': 'GB', 'name': 'United Kingdom'},
        {'code': 'US', 'name': 'United States'},
      ],
    };
AppState stateFor(Future<http.Response> Function(http.Request) handle) =>
    AppState(ApiClient(client: MockClient(handle)))
      ..identity = Identity.guest
      ..user =
          const UserView(id: 'guest-1', displayName: 'Guest', isGuest: true);
Widget gate(AppState state) => AppScope(
    state: state,
    child: MaterialApp(
        home: AgeSafetyGate(state: state, child: const Text('Private game'))));
void main() {
  testWidgets('age gate stays closed until the server responds',
      (tester) async {
    final response = Completer<http.Response>();
    final state = stateFor((_) => response.future);
    await tester.pumpWidget(gate(state));
    expect(find.text('Private game'), findsNothing);
    response
        .complete(http.Response(jsonEncode(status(band: 'AGE_13_15')), 200));
    await tester.pumpAndSettle();
    expect(find.text('Private game'), findsNothing);
    expect(find.textContaining('Teen access is not available yet'),
        findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets('disabled rollout leaves existing users access unchanged',
      (tester) async {
    final state = stateFor(
        (_) async => http.Response(jsonEncode(status(enforced: false)), 200));
    await tester.pumpWidget(gate(state));
    await tester.pumpAndSettle();
    expect(find.text('Private game'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets('network failure does not bypass the gate and can be retried',
      (tester) async {
    var calls = 0;
    final state = stateFor((_) async => ++calls == 1
        ? http.Response('{}', 503)
        : http.Response(jsonEncode(status(band: 'ADULT')), 200));
    await tester.pumpWidget(gate(state));
    await tester.pumpAndSettle();
    expect(find.text('Private game'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Private game'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets('saving a minor declaration does not unlock the app',
      (tester) async {
    var writes = 0;
    final state = stateFor((r) async {
      if (r.method == 'PUT') {
        writes++;
        expect(jsonDecode(r.body), {
          'ageBand': 'AGE_13_15',
          'countryCode': 'GB',
          'noticeAcknowledged': true
        });
        return http.Response(jsonEncode(status(band: 'AGE_13_15')), 200);
      }
      return http.Response(jsonEncode(status()), 200);
    });
    await tester.pumpWidget(gate(state));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.text('Age range'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('13–15').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Country where you live'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('United Kingdom').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save age details'));
    await tester.tap(find.text('Save age details'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.text('Private game'), findsNothing);
    expect(find.textContaining('Teen access is not available yet'),
        findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets('failed declaration stays editable without opening app content',
      (tester) async {
    final state = stateFor((_) async => http.Response('{}', 503));
    await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(home: AgeSafetyScreen(initial: status()))));
    await tester.tap(find.text('Age range'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('18 or older').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Country where you live'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('United Kingdom').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save age details'));
    await tester.tap(find.text('Save age details'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save. Check your details and try again.'),
        findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
