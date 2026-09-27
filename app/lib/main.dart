import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/app_state.dart';
import 'core/game_music.dart';
import 'core/game_sfx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(ApiClient());
  await GameMusic.load();
  await GameSfx.load();
  await state.bootstrap();
  runApp(TrueArenaApp(state: state));
}
