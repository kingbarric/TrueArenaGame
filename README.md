# TrueArena

Social deduction party platform. Native app (Flutter) + reactive Java backend, with a
later web/host-display funnel surface.

- **Vision, scope, game spec:** the Build Brief (source of truth for product decisions).
- **Architecture:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **Implementation plan (checkboxed, phased):** [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md)

## Repository layout

```
backend/          Gradle multi-module, Java 21, Spring Boot 3 (WebFlux)
  ta-app          Boot entrypoint + wiring
  ta-api          REST: auth, groups, rooms
  ta-ws           Reactive WebSocket transport, fan-out, per-subscriber filtering
  ta-engine       Transport-agnostic game engine SPI + reducer harness (NO Spring)
  ta-game-truearena  The TrueArena GameModule
  ta-room         Redis-backed room registry, reconnection, host migration
  ta-voice        LiveKit token minting + webhooks + forced mute
  ta-persistence  R2DBC repos + Flyway migrations
  ta-contract-tests  Full-session ITs + the secret-data guarantee test
app/              Flutter app (iOS + Android)
shared/contract/  JSON Schema for the WS envelope; codegen source of truth
infra/            docker-compose dev stack, LiveKit config, smoke script
```

## One-command local dev

Prereqs: Docker, JDK 21. (Flutter only needed for `app/`.)

```bash
docker compose -f infra/docker-compose.yml up --build
```

Brings up Postgres, Redis, LiveKit, an SMS stub, and the backend. Health check:

```bash
curl -s localhost:8080/actuator/health
./infra/smoke.sh
```

Dev auth shortcut: with `SPRING_PROFILES_ACTIVE=local`, OTP code `000000` verifies any
phone number.

## Backend build & test

```bash
cd backend
./gradlew build          # unit + slice tests
./gradlew integrationTest # Testcontainers (needs Docker)
```

## Flutter app

```bash
cd app
flutter pub get
flutter run --dart-define=API_BASE=http://localhost:8080
flutter test
```
