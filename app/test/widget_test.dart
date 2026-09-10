import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truearena/app.dart';
import 'package:truearena/core/api_client.dart';
import 'package:truearena/core/app_state.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('boots to the welcome screen with the wordmark', (tester) async {
    final state = AppState(ApiClient()); // no bootstrap() → stays anonymous, no network
    await tester.pumpWidget(TrueArenaApp(state: state));
    await tester.pump();

    expect(find.textContaining('TRUE'), findsWidgets);
    expect(find.text('SIGN IN WITH PHONE'), findsOneWidget);
    expect(find.text('PLAY AS GUEST'), findsOneWidget);
  });
}
