# PlayHuud app (Flutter)

Neon Night-Market UI (reference: `design/set-the-night.html`), light + dark.

## Bootstrap (once)

Platform folders aren't committed. With a working Flutter SDK on `PATH`:

```bash
cd app
flutter create --org app.truearena --project-name truearena .   # adds android/ ios/ etc.
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE=http://localhost:8080         # LAN IP for a real device
```

If `flutter pub get` rejects a dependency version, bump it in `pubspec.yaml`
(`flutter_lints`, `google_fonts` track the SDK release).

Google Fonts (Unbounded, Archivo) are fetched at first launch — bundle them under
`assets/fonts/` before shipping offline.

## Layout

```
lib/
  main.dart               boot: ApiClient + AppState, bootstrap(), runApp
  app.dart                MaterialApp — NeonTheme light/dark, home by identity
  theme/neon_theme.dart   NeonColors ThemeExtension (light+dark) + text theme
  core/
    api_client.dart       JSON client; API_BASE via --dart-define; Bearer + X-Device-Id
    app_state.dart         AppState (ChangeNotifier) + AppScope; identity anonymous|guest|account
    device_id.dart         stable per-install UUID for guest play
    models.dart            UserView, AuthTokens, ModePreset, RoomView, TwistMeta
  widgets/
    neon.dart             NeonButton, NeonCard, MarqueeBar, Avatar
    neon_form.dart        FieldLabel, NeonSwitchRow, NeonStepper, NeonSegmented, NeonChip, NeonSlider
  features/
    onboarding/           welcome → phone → otp   (POST /auth/otp/*, GET /me)  ·  guest path
    home/                 home_screen  (guest "verify to keep stats" banner, New game)
    modes/                mode_select_screen   (GET /config/presets, presets-first)
    setup/                setup_screen   (GameConfig editor; GET /config/twists,
                          live POST /config/validate; "Save & open" when diverged)
    lobby/                lobby_screen   (room code + roster; account host → POST /rooms,
                          guests get an example roster)
```

## Flow that works today

`welcome → phone+OTP (or guest) → home → mode select → setup / lobby`, wired to the
running backend. In-game screens (role reveal, night, round table, vote, results)
need the WebSocket layer (Phase 4).

Backend must be up: `docker compose -f infra/docker-compose.yml up -d postgres redis`
then run `truearena-backend.jar` with `SPRING_PROFILES_ACTIVE=local` (OTP `000000`).
