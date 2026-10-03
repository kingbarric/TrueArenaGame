import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/chat/conversation_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  Future<void> open(WidgetTester tester, {required bool sendSucceeds}) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
        return http.Response(jsonEncode({'messages': []}), 200,
            headers: {'content-type': 'application/json'});
      }
      if (request.method == 'GET') {
        return http.Response(jsonEncode({'type': 'group'}), 200,
            headers: {'content-type': 'application/json'});
      }
      if (!sendSucceeds) return http.Response(jsonEncode({'message': 'Offline'}), 503);
      return http.Response(jsonEncode({
        'id': 'message-1', 'senderId': '', 'kind': 'text',
        'text': jsonDecode(request.body)['text'],
        'createdAt': DateTime.utc(2026, 9, 29).toIso8601String(),
      }), 201, headers: {'content-type': 'application/json'});
    });
    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient(client: client)),
      child: MaterialApp(theme: NeonTheme.dark, home: const ConversationScreen(
          conversationId: 'conversation-1', title: 'Chat')),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a failed send keeps the message available to retry', (tester) async {
    await open(tester, sendSucceeds: false);
    await tester.enterText(find.byType(TextField), 'Hello friend');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Hello friend'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('a successful send adds the acknowledged message immediately', (tester) async {
    await open(tester, sendSucceeds: true);
    await tester.enterText(find.byType(TextField), 'Hello friend');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Hello friend'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });
}
