import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';

void main() {
  test('SQL, HTML and authentication errors expose only the standard public message', () async {
    for (final response in [
      http.Response('{"message":"UPDATE huud_spaces violates SQL constraint (password=secret)"}', 500),
      http.Response('<html>nginx 502 /var/db/internal.sql</html>', 502),
      http.Response('', 401),
    ]) {
      final api = ApiClient(client: MockClient((_) async => response));
      try {
        await api.patch('/huud-spaces/h1', {'background':'blank'});
        fail('Expected request failure');
      } on ApiException catch (error) {
        expect(error.message, userErrorMessage);
        expect(error.toString(), userErrorMessage);
        expect(error.status, response.statusCode);
      }
    }
  });
  test('network failures use the same message', () async {
    final api = ApiClient(client: MockClient((_) async => throw const SocketException('internal hostname')));
    await expectLater(api.get('/me'), throwsA(isA<ApiException>().having((e) => e.message, 'message', userErrorMessage)));
  });
  test('machine outcome codes remain available without displaying server text', () async {
    final api = ApiClient(client: MockClient((_) async => http.Response('{"message":"hidden","code":"ALREADY_PLAYING"}',409)));
    await expectLater(api.get('/me'), throwsA(isA<ApiException>()
      .having((e) => e.message, 'message',userErrorMessage)
      .having((e) => e.diagnosticMessage, 'code', 'ALREADY_PLAYING')));
  });
}
