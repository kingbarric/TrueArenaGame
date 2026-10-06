import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/app_state.dart';
import 'core/game_music.dart';
import 'core/game_sfx.dart';
import 'core/push_notifications.dart';
import 'features/calls/incoming_call_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(ApiClient());
  final push = await PushNotifications.init(state);
  state.onSignedIn = () => push.requestPermissionAndRegister();
  state.onSignedOut = push.unregisterCurrentToken;
  IncomingCalls.attach(state);
  await GameMusic.load();
  await GameSfx.load();
  await state.bootstrap();
  runApp(TrueArenaApp(state: state));
}
