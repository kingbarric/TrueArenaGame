# syntax=docker/dockerfile:1

FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY .mvn ./.mvn
COPY mvnw pom.xml ./
COPY ta-engine/pom.xml ta-engine/
COPY ta-game-truearena/pom.xml ta-game-truearena/
COPY ta-persistence/pom.xml ta-persistence/
COPY ta-room/pom.xml ta-room/
COPY ta-ws/pom.xml ta-ws/
COPY ta-voice/pom.xml ta-voice/
COPY ta-api/pom.xml ta-api/
COPY ta-app/pom.xml ta-app/
COPY ta-contract-tests/pom.xml ta-contract-tests/
RUN ./mvnw -B -q dependency:go-offline -DskipTests || true
COPY . .
RUN ./mvnw -B -q -DskipTests -pl ta-app -am package

FROM eclipse-temurin:21-jre AS runtime
RUN useradd -r -u 10001 appuser
WORKDIR /app
COPY --from=build /src/ta-app/target/truearena-backend.jar app.jar
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --retries=12 \
  CMD ["sh", "-c", "wget -qO- http://localhost:8080/actuator/health | grep -q UP"]
ENTRYPOINT ["java", "-jar", "app.jar"]
