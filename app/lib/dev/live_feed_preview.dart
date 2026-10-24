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
import '../features/profile/match_history_box.dart';
import '../features/competitive/player_profile_screen.dart';
import '../features/competitive/competitive_models.dart';
import '../theme/neon_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  const gameEntryPreview = bool.fromEnvironment('PREVIEW_GAME_ENTRY');
  await prefs.setInt('ta_main_tab_v4', gameEntryPreview ? 2 : 0);
  final now = DateTime.now().toUtc();
  final people = [
    for (final name in ['Beverly', 'Alex', 'Chloe', 'Ethan', 'Maya'])
      {
        'userId': name.toLowerCase(),
        'displayName': name,
        'username': name.toLowerCase(),
        'friend': true,
        'here': true
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
        'members': [for (var j = 0; j < 4; j++) people[(i + j) % people.length]],
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
  String? selectedGame = const bool.fromEnvironment('PREVIEW_GAME_CONFLICT') ? 'whot' : null, selectedMode;
  Map<String, dynamic> gameHuud() => {
    ...rooms[1], 'status': 'active', 'code': 'PRE123', 'live': true,
    'youAreHost': true, 'youOwn': true, 'youAreIn': true,
    'currentGame': selectedGame == null ? null : {
      'roomId': 'preview-game', 'code': 'GAME12', 'gameType': selectedGame,
      'mode': selectedMode, 'status': 'waiting', 'players': 1, 'seats': 4,
      'playerIds': ['me'], 'youArePlaying': true,
      'table': [{'userId': 'me', 'displayName': 'Riley', 'username': 'riley', 'bot': false}],
    },
  };
  final api = ApiClient(client: MockClient((request) async {
    final path = request.url.path.replaceFirst('/api/v1', '');
    dynamic body;
    if (path == '/huud-spaces/current' || path == '/huud-spaces/preview-1') {
      body = gameHuud();
    } else if (path == '/huud-spaces/preview-1/game' && request.method == 'POST') {
      final chosen = jsonDecode(request.body) as Map;
      selectedGame = chosen['gameType'] as String;
      selectedMode = chosen['mode'] as String?;
      body = {};
    } else if (path == '/me/matches') {
      final q = request.url.queryParameters;
      final history = [for (var i = 0; i < 18; i++) {
        'matchId': 'preview-match-$i', 'gameType': ['whot','chess','ludo'][i % 3],
        'outcome': i % 3 == 0 ? 'lost' : 'won',
        'completedAt': now.subtract(Duration(hours: i * 5)).toIso8601String(),
        'opponents': [{'userId': 'preview-player-$i', 'username': i.isEven ? 'alex' : 'beverly', 'displayName': i.isEven ? 'Alex' : 'Beverly'}],
      }];
      body = history.where((m) {
        final game = q['gameType'], opponent = q['opponent'];
        final date = DateTime.parse(m['completedAt'] as String);
        return (game == null || m['gameType'] == game)
            && (opponent == null || (m['opponents'] as List).toString().toLowerCase().contains(opponent.toLowerCase()))
            && (q['from'] == null || !date.isBefore(DateTime.parse(q['from']!)))
            && (q['until'] == null || date.isBefore(DateTime.parse(q['until']!)));
      }).take(10).toList();
    } else if (path == '/huud-spaces/preview-1/messages') {
      body = [];
    } else if (path == '/huud-spaces/live') {
      body = rooms;
    } else if (path == '/huud-spaces/mine') {
      body = [{...rooms[1], 'live': true, 'youOwn': true, 'liveCount': 5},
          {...rooms[3], 'live': false, 'youOwn': false, 'liveCount': 0}];
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
  final strength = {'score':63,'basis':'glicko2','games':100,'ranks': {
    'global':{'rank':23,'status':'ranked'},'country':{'rank':13,'status':'ranked'},'region':{'rank':2,'status':'ranked'}}};
  final profile = CompetitiveProfile.fromJson({
    'userId':'me','username':'riley','displayName':'Riley','playhuudId':'#000127',
    'strength':strength, 'profileComplete':true,
    'location':{'countryCode':'NG','countryName':'Nigeria','regionCode':'NG-RI','regionName':'Rivers'},
    'games':[for(final game in ['draughts','chess']) {'gameType':game,'rating':1842,'strength':strength,
      'provisional':false,'stats':{'gamesPlayed':12,'wins':3,'losses':9,'winRate':.25}}],
  });
  runApp(AppScope(
      state: state,
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: const bool.fromEnvironment('PREVIEW_LIGHT')
              ? NeonTheme.light
              : NeonTheme.dark,
          home: const bool.fromEnvironment('PREVIEW_PROFILE')
              ? Scaffold(appBar: AppBar(title: const Text('Profile'),actions:[Builder(builder:(context)=>IconButton(tooltip:'Preview Games',icon:const Icon(Icons.sports_esports),onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const MainShell(initialIndex:2)))))]),body:SingleChildScrollView(child:Column(children:[CompetitiveRecordSection(profile:profile,own:false,ratedGames:const ['draughts','chess']),const Padding(padding:EdgeInsets.all(16),child:MatchHistoryBox())])))
              : const bool.fromEnvironment('PREVIEW_HISTORY')
              ? Scaffold(appBar: AppBar(title: const Text('Profile')), body: const SingleChildScrollView(padding: EdgeInsets.all(16), child: MatchHistoryBox()))
              : const MainShell(initialIndex: 0))));
}
