import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';
import 'package:truearena/core/models.dart';
import 'package:truearena/widgets/match_coin_reward.dart';
void main() {
  testWidgets('reconnected results load exact reward receipt', (tester) async {
    final state=AppState(ApiClient(client:MockClient((req) async {
      expect(req.url.path, endsWith('/rooms/room-1/coin-reward'));
      return http.Response(jsonEncode({'amount':80,'baseAmount':50,'timeBonus':30,'vsAgent':false}),200);
    })))..identity=Identity.guest
      ..user=const UserView(id:'me',displayName:'Me',isGuest:true);
    await tester.pumpWidget(AppScope(state:state,child:const MaterialApp(home:Scaffold(body:MatchCoinReward(roomId:'room-1',foregroundColor:Colors.white)))));
    await tester.pumpAndSettle();
    expect(find.text('+80 coins earned'), findsOneWidget);
    final rewardContext=tester.element(find.text('+80 coins earned'));
    expect(DefaultTextStyle.of(rewardContext).style.color, Colors.white);
    expect(find.text('Result 50 · Time bonus 30'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); state.dispose();
  });
  testWidgets('delayed settlement retries without false reward', (tester) async {
    int calls=0;
    final state=AppState(ApiClient(client:MockClient((_) async => ++calls==1
      ? http.Response('{}',404)
      : http.Response(jsonEncode({'amount':50,'baseAmount':50,'timeBonus':0,'vsAgent':false}),200))))
      ..identity=Identity.guest..user=const UserView(id:'me',displayName:'Me',isGuest:true);
    await tester.pumpWidget(AppScope(state:state,child:const MaterialApp(home:Scaffold(body:MatchCoinReward(roomId:'room-1',foregroundColor:Colors.white)))));
    await tester.pumpAndSettle();
    expect(find.text('+0 coins earned'), findsNothing);
    await tester.pump(const Duration(seconds:1)); await tester.pumpAndSettle();
    expect(find.text('+50 coins earned'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); state.dispose();
  });
}
