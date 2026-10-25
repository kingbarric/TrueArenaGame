import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';

void main() {
  testWidgets('a stalled request times out and a later request succeeds',
      (tester) async {
    final hung = Completer<http.Response>();
    var online = false;
    Object? failure;
    final api = ApiClient(
        requestTimeout: const Duration(milliseconds: 20),
        client: MockClient((_) => online
            ? Future.value(http.Response('{"ok":true}', 200))
            : hung.future));
    final first = api.get('/me').catchError((Object e) {
      failure = e;
      return null;
    });
    await tester.pump(const Duration(milliseconds: 21));
    await first;
    expect(failure, isA<ApiException>());
    online = true;
    expect(await api.get('/me'), {'ok': true});
    hung.complete(http.Response('{}', 200));
    await tester.pump();
  });
  testWidgets(
      'stalled token refresh releases its lock and can recover on the next request',
      (tester) async {
    final refresh = Completer<bool>();
    Object? failure;
    final api = ApiClient(
        requestTimeout: const Duration(milliseconds: 20),
        client: MockClient((r) async => http.Response(
            '{}', r.headers['authorization'] == 'Bearer fresh' ? 200 : 401)))
      ..bearer = 'old';
    api.refreshHandler = () => refresh.future;
    final first = api.get('/me').catchError((Object e) {
      failure = e;
      return null;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 21));
    await first;
    expect(failure, isA<ApiException>());
    api.refreshHandler = () async {
      api.bearer = 'fresh';
      return true;
    };
    expect(await api.get('/me'), {});
    refresh.complete(false);
    await tester.pump();
  });
}
