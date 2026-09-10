import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(ApiClient());
  await state.bootstrap();
  runApp(TrueArenaApp(state: state));
}
