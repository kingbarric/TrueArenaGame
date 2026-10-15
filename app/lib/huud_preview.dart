// Local UI fixture. No sign-in, real messages or voice sessions are created.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'core/api_client.dart';
import 'core/app_state.dart';
import 'core/models.dart';
import 'features/huudspace/huud_space_screen.dart';
import 'features/huudspace/huud_space_models.dart';
import 'theme/neon_theme.dart';
import 'features/profile/profile_screen.dart';
import 'features/onboarding/avatar_setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final catalog = Map<String, dynamic>.from(jsonDecode(
      await rootBundle.loadString('assets/slay_renderer/catalog.json')));
  const base = String.fromEnvironment('SLAY_ASSET_BASE',
      defaultValue:
          'https://pub-add3eaff74154969a3810cabdb63ef40.r2.dev/slay/');
  catalog['assets'] = {...catalog['assets'] as Map, 'base': base};
  final options = jsonDecode(
          await rootBundle.loadString('assets/slay_renderer/huud-avatars.json'))
      as Map;
  var avatarSaved = true;
  final chosenAvatars = [
    'male',
    'ella',
    'male',
    'girl02',
    'indian-male',
    'ella',
    'male',
    'beverly',
    'girl02',
    'indian-male',
    'ella',
    'male'
  ];
  final names = [
    'Riley',
    'Ava',
    'Michael',
    'Chloe',
    'Ethan',
    'Ella',
    'Oliver',
    'Grace',
    'Sophia',
    'James',
    'Maya',
    'Lucas'
  ];
  final members = [
    for (int i = 0; i < names.length; i++)
      {
        'userId': i == 0 ? 'me' : 'person-$i',
        'displayName': names[i],
        'username': names[i].toLowerCase(),
        'host': i == 0,
        'here': true,
        'canSpeak': true,
        'huudAvatarId': chosenAvatars[i],
        'huudOutfitId': (options['outfits'] as List)[i % 10]['id']
      }
  ];
  // Opt-in large away roster for checking the dropdown without real accounts.
  for (var i = 0; i < const int.fromEnvironment('PREVIEW_AWAY_COUNT'); i++) {
    final name = names[i % names.length].toLowerCase();
    members.add({
      'userId': 'away-$i',
      'displayName': names[i % names.length],
      'username': '$name${i + 1}',
      'here': false,
      'canSpeak': false,
    });
  }
  final huud = <String, dynamic>{
    'id': 'preview-huud',
    'code': 'HUUD12',
    'name': 'The Sunday Club',
    'privacy': 'friends',
    'status': 'active',
    'youAreIn': true,
    'youAreHost': true,
    'youOwn': true,
    'youCanSpeak': true,
    'live': true,
    'voiceRoom': 'huud-preview-only',
    'members': members,
    'memberCount': members.length,
    'liveCount': members.where((p) => p['here'] == true).length,
    'host': members[0],
    'requests': [],
    'currentGame': null,
    'background': 'blank'
  };
  final chat = <Map<String, dynamic>>[
    for (int i = 0; i < 12; i++)
      {
        'id': i + 1,
        'from': members[(i + 1) % members.length],
        'body': [
          'The new Huud is lovely ✨',
          'Who is joining the next game?',
          'I am in! Pull up a chair.',
          'Let’s try Chess after we catch up.'
        ][i % 4],
        'at': DateTime.now()
            .subtract(Duration(minutes: 12 - i))
            .toUtc()
            .toIso8601String()
      },
  ];
  final api = ApiClient(client: MockClient((r) async {
    final path = r.url.path.replaceFirst('/api/v1', '');
    dynamic result;
    if (path == '/me/huud-avatar') {
      if (r.method == 'PATCH') {
        final choice = jsonDecode(r.body);
        members[0]['huudAvatarId'] = choice['avatarId'];
        members[0]['huudOutfitId'] = choice['outfitId'];
        avatarSaved = true;
      }
      result = {
        'avatarId': members[0]['huudAvatarId'],
        'outfitId': members[0]['huudOutfitId'],
        'saved': avatarSaved,
        'catalog': options
      };
    } else if (path == '/slay/catalog') {
      result = catalog;
    } else if (path == '/huud-spaces/preview-huud/messages') {
      if (r.method == 'POST') {
        final body = jsonDecode(r.body);
        final m = {
          'id': chat.length + 1,
          'from': members[0],
          'body': body['body'],
          'at': DateTime.now().toUtc().toIso8601String()
        };
        chat.add(m);
        result = m;
      } else {
        result = chat;
      }
    } else if (path == '/friends') {
      result = [];
    } else if (path.startsWith('/calls/')) {
      return http.Response('{"message":"Voice disabled in UI preview"}', 403);
    } else if (path.startsWith('/huud-spaces/preview-huud')) {
      result = huud;
    } else {
      return http.Response('{"message":"Preview only"}', 404);
    }
    return http.Response(jsonEncode(result), 200,
        headers: {'content-type': 'application/json'});
  }))
    ..bearer = 'local-preview';
  final state = AppState(api)
    ..user = const UserView(
        id: 'me', displayName: 'Riley', username: 'riley', isGuest: false)
    ..identity = Identity.account;
  runApp(AppScope(
      state: state,
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: const bool.fromEnvironment('HUUD_DARK_PREVIEW')
              ? NeonTheme.dark : NeonTheme.light,
          home: Banner(
              message: 'UI PREVIEW',
              location: BannerLocation.topEnd,
              color: const Color(0xff486e59),
              child: Builder(
                  builder: (context) => Stack(children: [
                        const ProfileScreen(),
                        Positioned(bottom: 90, right:16, child: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AvatarSetupScreen())),child: const Text('Preview registration'))),
                        Positioned(
                            bottom: 20,
                            right: 16,
                            child: FloatingActionButton.extended(
                                heroTag: 'preview-huud',
                                icon: const Icon(Icons.weekend_rounded),
                                label: const Text('Open Huud'),
                                onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            Stack(children: [HuudSpaceScreen(
                                                id: 'preview-huud',
                                                initial:
                                                    HuudSpace.fromJson(huud),
                                                previewSpeakingIds: const {
                                                  'person-1'
                                                }), if (const bool.fromEnvironment('PREVIEW_PRESENCE_CONTROLS')) Positioned(top: 55, right: 14, child: TextButton(onPressed: () {
                                                  members[1]['here'] = members[1]['here'] != true;
                                                  huud['liveCount'] = members.where((p) => p['here'] == true).length;
                                                  // ignore: invalid_use_of_visible_for_testing_member
                                                  state.debugHuudSpaceEvent({'type':'HUUD_SPACE','data':{'huudSpaceId':'preview-huud','event':'presence','by':'person-1'}});
                                                }, child: const Text('Ava leave / return')))])))))
                      ]))))));
}
