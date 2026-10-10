// Local UI preview only. This entrypoint uses fixture responses and never signs into PlayHuud.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'core/api_client.dart';
import 'core/app_state.dart';
import 'features/slayhuud/slay_hub_screen.dart';
import 'features/games/game_select_screen.dart';
import 'theme/neon_theme.dart';
import 'dev/slay_preview_scoring.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final catalog = Map<String, dynamic>.from(jsonDecode(
      await rootBundle.loadString('assets/slay_renderer/catalog.json')));
  final owned = (catalog['items'] as List)
      .where((i) => i['isDefault'] == true)
      .map((i) => i['id'])
      .toList();
  int balance = 600;
  final looks = <String, Map<String, dynamic>>{};
  final competitions = <String, Map<String, dynamic>>{};
  final api = ApiClient(client: MockClient((request) async {
    final path = request.url.path.replaceFirst('/api/v1', '');
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(request.body));
    dynamic result;
    if (path == '/me/wallet') {
      result = {
        'balance': balance,
        'tier': {
          'tier': 'Bronze',
          'lifetimeCoins': 600,
          'nextTier': 'Silver',
          'coinsToNextTier': 400,
          'tierProgress': .6
        },
        'recent': []
      };
    } else if (path == '/slay/catalog') {
      result = catalog;
    } else if (path == '/slay/profile') {
      result = {
        'xp': 240,
        'owned': owned,
        'stats': {'wins': 3, 'competitions': 7, 'top_three': 4}
      };
    } else if (path == '/slay/competitions' && request.method == 'GET') {
      result = competitions.values.toList();
    } else if (path == '/slay/competitions' && request.method == 'POST') {
      final id = 'preview-${competitions.length + 1}';
      result = {
        'id': id,
        'mode': body['mode'],
        'status': 'lobby',
        'theme': (catalog['themes'] as List)
            .firstWhere((t) => t['id'] == body['themeId']),
        'round': 1,
        'seats': body['seats'],
        'contestants': 0,
        'judges': 0,
        'host': true,
        'role': 'spectator',
        'entries': [],
        'contestantBody': body['contestantBody'],
        'developmentAssets': true,
        'deadline': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
        'serverTime': DateTime.now().toUtc().toIso8601String()
      };
      competitions[id] = result;
    } else if (path.startsWith('/slay/competitions/')) {
      final parts = path.split('/');
      final c = competitions[parts[3]];
      if (c == null) {
        return http.Response('{"message":"Unknown preview competition"}', 404);
      }
      if (parts.last == 'join') {
        c['role'] = body['role'];
        c['body'] = body['body'];
        if (body['role'] == 'contestant') {
          c['contestants'] = (c['contestants'] as int) + 1;
        } else {
          c['judges'] = (c['judges'] as int) + 1;
        }
      }
      if (parts.last == 'start') {
        c['status'] = 'styling';
        c['deadline'] = DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 3))
            .toIso8601String();
      }
      if (parts.last == 'submit') {
        c['submitted'] = true;
        c['status'] = 'voting';
      }
      if (parts.last == 'cancel') c['status'] = 'cancelled';
      c['serverTime'] = DateTime.now().toUtc().toIso8601String();
      result = c;
    } else if (path == '/slay/looks') {
      final id = 'preview-look-${looks.length + 1}';
      looks[id] = body;
      result = {'id': id};
    } else if (path.endsWith('/snapshot')) {
      result = null;
    } else if (path.startsWith('/slay/looks/') && request.method == 'GET') {
      result = {
        'look': looks[path.split('/').last],
        'catalogVersion': catalog['version']
      };
    } else if (path.startsWith('/slay/solo/')) {
      final look = looks[body['lookId']];
      final themes = (catalog['themes'] as List).cast<Map>();
      final theme = themes.where((t) => t['id'] == path.split('/')[3]);
      if (look == null || theme.isEmpty) {
        return http.Response('{"message":"Unknown look or theme"}', 404);
      }
      try {
        result = {
          ...scoreSlayPreview(
              look, Map<String, dynamic>.from(theme.single), catalog),
          'preview': true
        };
      } on StateError catch (error) {
        return http.Response(jsonEncode({'message': error.message}), 400);
      }
    } else if (path == '/slay/wardrobe/buy') {
      final item = (catalog['items'] as List)
          .firstWhere((i) => i['id'] == body['itemId']);
      final cost = (item['coinCost'] as num).toInt();
      if (owned.contains(item['id']) || balance < cost) {
        return http.Response(
            '{"message":"Not enough coins or already owned"}', 409);
      }
      balance -= cost;
      owned.add(body['itemId']);
      result = null;
    } else if (path.startsWith('/championships/')) {
      result = [];
    } else if (path == '/huud/posts') {
      result = {};
    } else {
      return http.Response(
          '{"message":"This action is unavailable in the UI preview"}', 404);
    }
    return http.Response(result == null ? '' : jsonEncode(result), 200,
        headers: {'content-type': 'application/json'});
  }));
  runApp(AppScope(
      state: AppState(api),
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: NeonTheme.dark,
          builder: (context, child) => Banner(
              message: 'UI PREVIEW',
              location: BannerLocation.topEnd,
              color: NeonColors.dark.brand,
              child: child!),
          home: const GameSelectScreen(),
          initialRoute: '/slayhuud',
          routes: {'/slayhuud': (_) => const SlayHubScreen()})));
}
