# TrueArena app (Flutter)

Phase 0 ships the Dart-level project only. Before the first `flutter run`, generate the
platform folders (they are gitignored / not scaffolded here):

```bash
cd app
flutter create --org app.truearena --project-name truearena .
flutter pub get
```

`flutter analyze` and `flutter test` work without the platform folders.

```bash
flutter test
flutter run --dart-define=API_BASE=http://localhost:8080
```

Real screens land in Phase 10 of docs/PROJECT_PLAN.md.
