# TrueArena app (Flutter)

Neon Night-Market UI (see `design/set-the-night.html` for the reference), light + dark.

## First run

Platform folders aren't committed — generate them once:

```bash
cd app
flutter create --org app.truearena --project-name truearena .
flutter pub get
flutter run --dart-define=API_BASE=http://localhost:8080     # or a LAN IP for a real device
```

`flutter analyze` and `flutter test` work without the platform folders.

Google Fonts (Unbounded, Archivo) are fetched at first launch; bundle them under
`assets/fonts/` before shipping offline.

## Layout

```
lib/
  main.dart              boot: build ApiClient + AppState, bootstrap(), runApp
  app.dart               MaterialApp — NeonTheme light/dark, home by identity
  theme/neon_theme.dart  NeonColors ThemeExtension (light+dark) + text theme
  core/
    api_client.dart      JSON client; API_BASE via --dart-define; Bearer + X-Device-Id
    app_state.dart       AppState (ChangeNotifier) + AppScope; identity: anonymous|guest|account
    device_id.dart       stable per-install UUID for guest play (persisted)
    models.dart          UserView, AuthTokens, ModePreset, TwistMeta
  widgets/neon.dart      NeonButton, NeonCard, MarqueeBar, Avatar
  features/
    onboarding/          welcome → phone → otp  (POST /auth/otp/*, GET /me)
    home/                home_screen  (guest banner + "New game")
    modes/               mode_select_screen  (GET /config/presets, presets-first)
```

## What works now

- Welcome → **phone + OTP** sign-in against the backend (`000000` in the `local` profile),
  or **Play as guest** (nickname + device id, one game, cleared afterwards).
- **Mode select** loads the five builtin presets from `GET /api/v1/config/presets` and
  shows player range / traitors / veil / twist count. "Open the room" and "Customize
  setup" are stubbed — the lobby and the GameConfig editor are the next screens.
- Theme toggle (light/dark), persisted.
