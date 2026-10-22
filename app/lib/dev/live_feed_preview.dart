// Local visual fixture for the existing Live tab. All requests stay in memory.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../features/shell/main_shell.dart';
import '../theme/neon_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('ta_main_tab_v4', 0);
  final now = DateTime.now().toUtc();
  final people = [
    for (final name in ['Beverly', 'Alex', 'Chloe', 'Ethan', 'Maya'])
      {
        'userId': name.toLowerCase(),
        'displayName': name,
        'username': name.toLowerCase(),
        'friend': true
      }
  ];
  const names = [
    'The after-hours Huud',
    'The Sunday Club',
    'Good music, good people',
    'The plot twist',
    'Friday catch-up',
    'The late shift',
    'A little conversation',
    'The weekend crew'
  ];
  final rooms = [
    for (var i = 0; i < names.length; i++)
      {
        'id': 'preview-$i',
        'name': names[i],
        'privacy': i.isEven ? 'public' : 'friends',
        'memberCount': 4 + i,
        'members': [people[i % people.length]],
        'host': people[i % people.length],
        'youAreIn': i == 1,
        'gameType': i == 2 ? 'whot' : null,
        'gameStatus': i == 2 ? 'playing' : null,
      }
  ];
  final posts = <Map<String, dynamic>>[
    for (var i = 0; i < people.length; i++)
      {
        'id': 'text:preview-$i',
        'kind': 'post',
        'actor': people[i],
        'at': now.subtract(Duration(minutes: 3 + i * 5)).toIso8601String(),
        'message': [
          'Some people feel like home. Pull up, we’re talking about the friends who changed our lives.',
          'Hot take: the group chat is funnier than the actual night out.',
          'Friday catch-up at 8? Same Huud, new stories.',
          'There’s something about a conversation that accidentally lasts three hours.',
          'Good music. Better conversation. Who is coming in tonight?',
        ][i],
        'reactions': {
          'total': 4 + i,
          'counts': {'❤️': 3 + i, '😂': 1},
          'mine': null
        }
      }
  ];
  final shares = [
    for (var i = 0; i < 4; i++)
      {
        'id': 'huud:preview-$i',
        'kind': 'huud',
        'actor': people[i],
        'at': now.subtract(Duration(minutes: 5 + i * 7)).toIso8601String(),
        'message': [
          'Come catch up with us.',
          'We’re talking all things music.',
          'A place for your people.',
          'Bring a story.'
        ][i],
        'huud': {
          'huudSpaceId': 'preview-$i',
          'name': names[i],
          'privacy': 'public',
          'people': 4 + i,
          'players': 0,
          'seats': 4,
          'access': 'join'
        }
      }
  ];
  final api = ApiClient(client: MockClient((request) async {
    final path = request.url.path.replaceFirst('/api/v1', '');
    dynamic body;
    if (path == '/huud-spaces/live') {
      body = rooms;
    } else if (path == '/friends') {
      body = people;
    } else if (path == '/huud/feed') {
      body = request.url.queryParameters['tab'] == 'friends' ? posts : shares;
    } else if (path == '/huud/text-posts' && request.method == 'POST') {
      final text = jsonDecode(request.body)['body'];
      final post = {
        'id': 'text:preview-new',
        'kind': 'post',
        'actor': {'userId': 'me', 'displayName': 'Riley', 'username': 'riley'},
        'at': DateTime.now().toUtc().toIso8601String(),
        'message': text
      };
      posts.insert(0, post);
      body = post;
    } else if (path.endsWith('/reaction')) {
      body = {
        'total': 8,
        'counts': {'❤️': 7, '😂': 1},
        'mine': '❤️'
      };
    } else if (path == '/rooms/discoverable' ||
        path == '/friends/requests' ||
        path == '/conversations') {
      body = [];
    } else {
      return http.Response('{"message":"Local preview only"}', 404,
          headers: {'content-type': 'application/json'});
    }
    return http.Response(jsonEncode(body), 200,
        headers: {'content-type': 'application/json'});
  }))
    ..bearer = 'local-live-feed-preview';
  final state = AppState(api)
    ..user = const UserView(
        id: 'me', displayName: 'Riley', username: 'riley', isGuest: false)
    ..identity = Identity.account;
  state.onlineFriends.value = {'beverly', 'alex', 'chloe'};
  runApp(AppScope(
      state: state,
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: const bool.fromEnvironment('PREVIEW_LIGHT')
              ? NeonTheme.light
              : NeonTheme.dark,
          home: const MainShell(initialIndex: 0))));
}
