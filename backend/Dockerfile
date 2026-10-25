# syntax=docker/dockerfile:1

FROM eclipse-temurin:21-jre AS stockfish
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY stockfish/install.sh /tmp/install-stockfish.sh
RUN sh /tmp/install-stockfish.sh /opt/stockfish

FROM eclipse-temurin:21-jre AS scan
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates unzip g++ make \
    && rm -rf /var/lib/apt/lists/*
COPY scan/install.sh /tmp/install-scan.sh
RUN sh /tmp/install-scan.sh /opt/scan

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
RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -r -u 10001 appuser
WORKDIR /app
COPY --from=build /src/ta-app/target/truearena-backend.jar app.jar
COPY --from=stockfish /opt/stockfish /opt/stockfish
ENV STOCKFISH_PATH=/opt/stockfish/stockfish
COPY --from=scan /opt/scan /opt/scan
ENV SCAN_PATH=/opt/scan/scan SCAN_DIRECTORY=/opt/scan
USER appuser
EXPOSE 8080
# temurin jre images ship neither curl nor wget; bash /dev/tcp is enough for a liveness probe.
HEALTHCHECK --interval=10s --timeout=3s --retries=12 \
  CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8080 && printf 'GET /actuator/health HTTP/1.0\\r\\n\\r\\n' >&3 && grep -q UP <&3"]
ENTRYPOINT ["java", "-jar", "app.jar"]
