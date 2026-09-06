# syntax=docker/dockerfile:1

FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY gradlew settings.gradle.kts build.gradle.kts ./
COPY gradle ./gradle
COPY ta-app/build.gradle.kts ta-app/
COPY ta-api/build.gradle.kts ta-api/
COPY ta-ws/build.gradle.kts ta-ws/
COPY ta-engine/build.gradle.kts ta-engine/
COPY ta-game-truearena/build.gradle.kts ta-game-truearena/
COPY ta-room/build.gradle.kts ta-room/
COPY ta-voice/build.gradle.kts ta-voice/
COPY ta-persistence/build.gradle.kts ta-persistence/
COPY ta-contract-tests/build.gradle.kts ta-contract-tests/
RUN ./gradlew --no-daemon dependencies -q || true
COPY . .
RUN ./gradlew --no-daemon :ta-app:bootJar -x test

FROM eclipse-temurin:21-jre AS runtime
RUN useradd -r -u 10001 appuser
WORKDIR /app
COPY --from=build /src/ta-app/build/libs/truearena-backend.jar app.jar
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --retries=12 \
  CMD ["sh", "-c", "wget -qO- http://localhost:8080/actuator/health | grep -q UP"]
ENTRYPOINT ["java", "-jar", "app.jar"]
