import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/features/wallet/wallet_screen.dart';
import 'package:truearena/theme/neon_theme.dart';

void main() {
  testWidgets('wallet shows several coin entries on a small phone',
      (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mock = MockClient((request) async => http.Response(
          jsonEncode({
            'balance': 120,
            'tier': {
              'tier': 'Bronze',
              'lifetimeCoins': 120,
              'nextTier': 'Silver',
              'coinsToNextTier': 80,
              'tierProgress': 0.6,
            },
            'recent': [
              for (final reason in [
                'match_win',
                'match_loss',
                'match_tie',
                'bot_added',
              ])
                {
                  'delta': 10,
                  'balanceAfter': 120,
                  'reason': reason,
                  'createdAt': '2026-09-25T12:00:00Z',
                },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ));
    await tester.pumpWidget(AppScope(
      state: AppState(ApiClient(client: mock)),
      child: MaterialApp(theme: NeonTheme.dark, home: const WalletScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Match won'), findsOneWidget);
    expect(find.text('Match played'), findsOneWidget);
    expect(find.text('Match tied'), findsOneWidget);
    expect(find.text('Cyber Agent added'), findsOneWidget);
    final firstTop = tester.getTopLeft(find.text('Match won')).dy;
    final secondTop = tester.getTopLeft(find.text('Match played')).dy;
    expect(secondTop - firstTop, lessThan(45));
    expect(tester.getTopLeft(find.text('Cyber Agent added')).dy, lessThan(568));
    expect(tester.takeException(), isNull);
  });
}
