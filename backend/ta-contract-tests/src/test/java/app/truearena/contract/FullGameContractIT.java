package app.truearena.contract;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.WebSocket;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Full-session real-WebSocket integration test (Build Brief §8 / Plan 11.5) — what
 * {@code ta-contract-tests} was scaffolded for but never built past a placeholder.
 * Ports the exact scenario and bot strategy already hand-verified manually via
 * {@code backend/dev-tools/ws-smoke-test.mjs} (see docs/PROJECT_PLAN.md Phase 4) into a
 * real, repeatable JUnit IT: 6 real accounts, one ad-hoc Classic Conspiracy room, 6 real
 * WebSocket connections played to {@code GAME_OVER}, with the secret-data guarantee
 * checked on every frame every client actually received — the same invariant
 * {@code SecretDataGuaranteeTest} checks in-process, now proven at the transport layer.
 * Also exercises the two live-room behaviors nothing else covers end-to-end: reconnect
 * replay (a real {@code lastSeq} skips the full snapshot) and host migration (disconnect
 * the host, a connected human takes over within the 10s grace).
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("local") // enables the OTP dev-bypass code this test signs up with
@Tag("integration")
@Testcontainers
class FullGameContractIT {

    @Container
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:16");

    @Container
    static final GenericContainer<?> REDIS = new GenericContainer<>("redis:7").withExposedPorts(6379);

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        r.add("spring.r2dbc.url", () -> "r2dbc:postgresql://" + POSTGRES.getHost() + ":"
                + POSTGRES.getFirstMappedPort() + "/" + POSTGRES.getDatabaseName());
        r.add("spring.r2dbc.username", POSTGRES::getUsername);
        r.add("spring.r2dbc.password", POSTGRES::getPassword);
        r.add("spring.flyway.url", POSTGRES::getJdbcUrl);
        r.add("spring.flyway.user", POSTGRES::getUsername);
        r.add("spring.flyway.password", POSTGRES::getPassword);
        r.add("spring.data.redis.host", REDIS::getHost);
        r.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
    }

    @LocalServerPort
    private int port;

    private final TestRestTemplate rest = new TestRestTemplate();
    private final ObjectMapper mapper = new ObjectMapper();
    private final HttpClient http = HttpClient.newHttpClient();
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(4);
    private final List<String> violations = Collections.synchronizedList(new ArrayList<>());
    private final Set<String> advancedForPhase = Collections.synchronizedSet(new HashSet<>());
    private final AtomicBoolean finished = new AtomicBoolean(false);
    private final AtomicReference<String> winningSide = new AtomicReference<>();
    private TestClient host;

    private String baseHttp() {
        return "http://localhost:" + port;
    }

    private String baseWs() {
        return "ws://localhost:" + port;
    }

    /** One simulated real client: its own account, its own socket, its own view of the game. */
    private static final class TestClient {
        String phone;
        String name;
        String token;
        String userId;
        WebSocket ws;
        final List<Map<String, Object>> frames = Collections.synchronizedList(new ArrayList<>());
        volatile String myRole;
        volatile List<String> fellowTraitors = List.of();
        // Mutated (PLAYER_ELIMINATED) from this client's own WS-listener thread and read
        // from the scheduler's bot-action threads — needs real thread-safety, not just a
        // volatile reference, since the reassignment isn't the only mutation (remove() is too).
        volatile Set<String> alive = java.util.concurrent.ConcurrentHashMap.newKeySet();
    }

    private static Set<String> newAliveSet(List<String> ids) {
        Set<String> set = java.util.concurrent.ConcurrentHashMap.newKeySet();
        set.addAll(ids);
        return set;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> post(String path, Map<String, Object> body, String token) {
        HttpHeaders headers = new HttpHeaders();
        headers.set("Content-Type", "application/json");
        if (token != null) {
            headers.set("Authorization", "Bearer " + token);
        }
        var response = rest.exchange(baseHttp() + path, HttpMethod.POST, new HttpEntity<>(body, headers), Map.class);
        assertThat(response.getStatusCode().is2xxSuccessful()).as("%s -> %s", path, response.getStatusCode()).isTrue();
        return (Map<String, Object>) response.getBody();
    }

    @SuppressWarnings("unchecked")
    private TestClient signup(String phone) {
        Map<String, Object> res = post("/api/v1/auth/otp/verify", Map.of("phone", phone, "code", "000000"), null);
        TestClient c = new TestClient();
        c.phone = phone;
        c.token = (String) res.get("accessToken");
        Map<String, Object> user = (Map<String, Object>) res.get("user");
        c.userId = (String) user.get("id");
        c.name = (String) user.get("displayName");
        return c;
    }

    private void sendFrame(TestClient c, String type, Map<String, Object> payload) {
        try {
            Map<String, Object> env = new LinkedHashMap<>();
            env.put("v", 1);
            env.put("type", type);
            env.put("ts", System.currentTimeMillis());
            env.put("payload", payload);
            c.ws.sendText(mapper.writeValueAsString(env), true);
        } catch (Exception e) {
            violations.add("failed to send " + type + " for " + c.name + ": " + e);
        }
    }

    /** Opens a real WebSocket for this client's account against the running app, wiring
     * every received frame through {@link #handle}. Blocks until the handshake completes. */
    private void connect(TestClient c, UUID roomId) throws Exception {
        URI uri = URI.create(baseWs() + "/ws/room/" + roomId + "?token=" + c.token);
        WebSocket.Listener listener = new WebSocket.Listener() {
            private final StringBuilder buf = new StringBuilder();

            @Override
            public void onOpen(WebSocket webSocket) {
                webSocket.request(1);
            }

            @Override
            @SuppressWarnings("unchecked")
            public CompletionStage<?> onText(WebSocket webSocket, CharSequence data, boolean last) {
                buf.append(data);
                if (last) {
                    String msg = buf.toString();
                    buf.setLength(0);
                    try {
                        Map<String, Object> frame = mapper.readValue(msg, Map.class);
                        c.frames.add(frame);
                        handle(c, frame);
                    } catch (Exception e) {
                        violations.add("could not parse frame for " + c.name + ": " + e);
                    }
                }
                webSocket.request(1);
                return null;
            }

            @Override
            public void onError(WebSocket webSocket, Throwable error) {
                violations.add("socket error for " + c.name + ": " + error);
            }
        };
        c.ws = http.newWebSocketBuilder().buildAsync(uri, listener).get(10, TimeUnit.SECONDS);
        sendFrame(c, "HELLO", Map.of("lastSeq", 0));
    }

    @SuppressWarnings("unchecked")
    private void handle(TestClient c, Map<String, Object> env) {
        String type = (String) env.get("type");
        Map<String, Object> payload = (Map<String, Object>) env.getOrDefault("payload", Map.of());
        if ("SNAPSHOT".equals(type)) {
            if (Boolean.FALSE.equals(payload.get("lobby")) && payload.get("yourRole") != null) {
                c.myRole = (String) payload.get("yourRole");
                c.fellowTraitors = (List<String>) payload.getOrDefault("fellowTraitors", List.of());
                c.alive = newAliveSet((List<String>) payload.getOrDefault("alive", List.of()));
            }
            return;
        }
        if ("PHASE".equals(type)) {
            onPhase(c, (String) payload.get("phase"), ((Number) payload.get("round")).intValue());
            return;
        }
        if (!"EVENT".equals(type)) {
            return;
        }
        String geType = (String) payload.get("type");
        Map<String, Object> data = (Map<String, Object>) payload.getOrDefault("data", Map.of());
        checkNoLeak(c, geType, data);
        switch (geType) {
            case "ROLE_ASSIGNED" -> c.myRole = (String) data.get("role");
            case "FELLOW_TRAITORS" -> c.fellowTraitors = (List<String>) data.getOrDefault("ids", List.of());
            case "GAME_STARTED" -> c.alive = newAliveSet((List<String>) data.getOrDefault("players", List.of()));
            case "PLAYER_ELIMINATED" -> c.alive.remove(data.get("id"));
            case "GAME_OVER" -> {
                finished.set(true);
                winningSide.set((String) data.get("winningSide"));
            }
            default -> {
            }
        }
    }

    /** The transport-layer secret-data guarantee: a bare role attached to a specific id is
     * only legitimate via a publicly-revealed elimination or the end-of-game full reveal. */
    private void checkNoLeak(TestClient c, String geType, Map<String, Object> data) {
        Object role = data.get("role");
        Object id = data.get("id");
        if (role != null && id != null) {
            if ("PLAYER_ELIMINATED".equals(geType) && Boolean.TRUE.equals(data.get("roleShown"))) {
                return;
            }
            if ("FULL_REVEAL".equals(geType)) {
                return;
            }
            violations.add(c.name + " saw a bare role for " + id + " via " + geType + ": " + data);
        }
        if ("FULL_REVEAL".equals(geType) && !finished.get()) {
            violations.add(c.name + " received FULL_REVEAL before the game finished");
        }
    }

    private String pickTarget(TestClient c) {
        List<String> others = c.alive.stream().filter(id -> !id.equals(c.userId)).toList();
        List<String> notFellow = others.stream().filter(id -> !c.fellowTraitors.contains(id)).toList();
        if (!notFellow.isEmpty()) {
            return notFellow.get(0);
        }
        return others.isEmpty() ? null : others.get(0);
    }

    private static final List<String> UNTIMED_HOST_ADVANCE =
            List.of("RoleReveal", "MorningReveal", "RoundTable", "VoteReview", "Elimination", "WinCheck");

    private void onPhase(TestClient c, String phase, int round) {
        if (c == host) {
            String key = phase + ":" + round;
            if (UNTIMED_HOST_ADVANCE.contains(phase) && advancedForPhase.add(key)) {
                scheduler.schedule(() -> sendFrame(host, "PLAYER_ACTION", Map.of("action", "ADVANCE_PHASE")),
                        120, TimeUnit.MILLISECONDS);
            }
            if ("Results".equals(phase)) {
                finished.set(true);
            }
        }
        if ("Night".equals(phase) && c.myRole != null && c.myRole.contains("traitor")) {
            String target = pickTarget(c);
            if (target != null) {
                scheduler.schedule(() -> sendFrame(c, "PLAYER_ACTION", Map.of("action", "NIGHT_TARGET", "data", Map.of("target", target))),
                        150, TimeUnit.MILLISECONDS);
            }
        }
        if ("Vote".equals(phase)) {
            String target = pickTarget(c);
            if (target != null) {
                long delay = 200 + ThreadLocalRandom.current().nextInt(300);
                scheduler.schedule(() -> sendFrame(c, "PLAYER_ACTION", Map.of("action", "CAST_VOTE", "data", Map.of("target", target))),
                        delay, TimeUnit.MILLISECONDS);
            }
        }
    }

    @SuppressWarnings("unchecked")
    private long lastSeqSeen(TestClient c) {
        long max = 0;
        for (Map<String, Object> frame : List.copyOf(c.frames)) {
            if (!"EVENT".equals(frame.get("type"))) {
                continue;
            }
            Map<String, Object> payload = (Map<String, Object>) frame.get("payload");
            Object seq = payload == null ? null : payload.get("seq");
            if (seq instanceof Number n && n.longValue() > max) {
                max = n.longValue();
            }
        }
        return max;
    }

    @Test
    void sixPlayerGame_noSecretDataLeak_reconnectReplaysInsteadOfResnapshotting_hostMigratesOnDisconnect() throws Exception {
        int n = 6;
        List<TestClient> clients = new ArrayList<>();
        for (int i = 1; i <= n; i++) {
            clients.add(signup("090000" + String.format("%04d", i)));
        }
        host = clients.get(0);

        Map<String, Object> room = post("/api/v1/rooms", Map.of(), host.token);
        UUID roomId = UUID.fromString((String) room.get("id"));
        String code = (String) room.get("code");
        for (int i = 1; i < n; i++) {
            post("/api/v1/rooms/join", Map.of("code", code), clients.get(i).token);
        }

        for (TestClient c : clients) {
            connect(c, roomId);
        }
        Thread.sleep(800); // let every socket HELLO + settle before starting

        sendFrame(host, "GAME_START", Map.of());

        // ---- reconnect: a real lastSeq skips the full snapshot ----
        TestClient reconnecting = clients.get(1);
        long deadlineForFirstEvent = System.currentTimeMillis() + 5000;
        while (lastSeqSeen(reconnecting) == 0 && System.currentTimeMillis() < deadlineForFirstEvent) {
            Thread.sleep(50);
        }
        long seenSeq = lastSeqSeen(reconnecting);
        assertThat(seenSeq).as("at least one EVENT should have reached this player by now").isGreaterThan(0);
        reconnecting.ws.abort();
        reconnecting.frames.clear();
        URI uri = URI.create(baseWs() + "/ws/room/" + roomId + "?token=" + reconnecting.token);
        WebSocket.Listener listener = new WebSocket.Listener() {
            private final StringBuilder buf = new StringBuilder();

            @Override
            public void onOpen(WebSocket webSocket) {
                webSocket.request(1);
            }

            @Override
            @SuppressWarnings("unchecked")
            public CompletionStage<?> onText(WebSocket webSocket, CharSequence data, boolean last) {
                buf.append(data);
                if (last) {
                    String msg = buf.toString();
                    buf.setLength(0);
                    try {
                        Map<String, Object> frame = mapper.readValue(msg, Map.class);
                        reconnecting.frames.add(frame);
                        handle(reconnecting, frame);
                    } catch (Exception e) {
                        violations.add("reconnect parse failure: " + e);
                    }
                }
                webSocket.request(1);
                return null;
            }

            @Override
            public void onError(WebSocket webSocket, Throwable error) {
                violations.add("reconnect socket error: " + error);
            }
        };
        reconnecting.ws = http.newWebSocketBuilder().buildAsync(uri, listener).get(10, TimeUnit.SECONDS);
        sendFrame(reconnecting, "HELLO", Map.of("lastSeq", seenSeq));
        long reconnectWait = System.currentTimeMillis() + 3000;
        while (reconnecting.frames.isEmpty() && System.currentTimeMillis() < reconnectWait) {
            Thread.sleep(50);
        }
        assertThat(reconnecting.frames).as("real lastSeq means no full snapshot on reconnect")
                .noneMatch(f -> "SNAPSHOT".equals(f.get("type")));
        assertThat(reconnecting.frames).as("reconnect should still get the current PHASE")
                .anyMatch(f -> "PHASE".equals(f.get("type")));

        // ---- play the rest of the game to completion ----
        long gameDeadline = System.currentTimeMillis() + 30_000;
        while (!finished.get() && System.currentTimeMillis() < gameDeadline) {
            Thread.sleep(250);
        }
        assertThat(violations).as("no client should ever see another player's un-revealed role").isEmpty();
        assertThat(finished.get()).as("the game should reach GAME_OVER/Results within the deadline").isTrue();
        assertThat(winningSide.get()).isIn("faithful", "traitors");

        // ---- host migration: disconnect the host, a connected human takes over ----
        TestClient survivor = clients.get(2);
        survivor.frames.clear();
        host.ws.abort();
        long migrationDeadline = System.currentTimeMillis() + 12_000;
        boolean migrated = false;
        while (!migrated && System.currentTimeMillis() < migrationDeadline) {
            migrated = List.copyOf(survivor.frames).stream().anyMatch(f -> "EVENT".equals(f.get("type"))
                    && "HOST_CHANGED".equals(((Map<?, ?>) f.get("payload")).get("type")));
            if (!migrated) {
                Thread.sleep(200);
            }
        }
        assertThat(migrated).as("a connected human should take over as host within the 10s grace").isTrue();

        for (TestClient c : clients) {
            try {
                c.ws.abort();
            } catch (Exception ignored) {
            }
        }
        scheduler.shutdownNow();
    }
}
