package app.truearena.api.bot;

import app.truearena.game.chess.Position;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledOnOs;
import org.junit.jupiter.api.condition.OS;
import org.junit.jupiter.api.io.TempDir;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.PosixFilePermissions;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.Executors;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

@EnabledOnOs({OS.LINUX, OS.MAC})
class StockfishEngineTest {
    @TempDir Path temporary;

    private Path log() { return temporary.resolve("commands.log"); }

    private StockfishEngine engine(String mode, int processes) throws Exception {
        Path executable = temporary.resolve("engine with spaces.sh");
        String java = Path.of(System.getProperty("java.home"), "bin", "java").toString();
        String command = "#!/bin/sh\nexec " + quote(java) + " -cp " + quote(System.getProperty("java.class.path"))
                + " " + quote(FakeEngine.class.getName()) + " " + quote(mode) + " " + quote(log().toString())
                + " " + quote(temporary.resolve("crashed-once").toString()) + "\n";
        Files.writeString(executable, command);
        Files.setPosixFilePermissions(executable, PosixFilePermissions.fromString("rwx------"));
        return new StockfishEngine(new StockfishEngine.Settings(true, executable.toString(), processes, 16, 200, 0));
    }

    private static String quote(String text) { return "'" + text.replace("'", "'\"'\"'") + "'"; }

    private String commands() throws Exception { return Files.exists(log()) ? Files.readString(log()) : ""; }

    @Test void reusesABoundedProcessAndSetsStrengthForEachGame() throws Exception {
        try (var engine = engine("normal", 1)) {
            engine.warmUp();
            for (Difficulty level : Difficulty.values())
                assertThat(engine.choose(Position.initial(), List.of(), level, 1000)).get()
                        .extracting(move -> move.uci()).isEqualTo("e2e4");
            assertThat(commands()).contains("setoption name Threads value 1", "setoption name Hash value 16",
                    "setoption name Ponder value false", "setoption name Skill Level value 2",
                    "setoption name Skill Level value 10", "setoption name Skill Level value 20",
                    "setoption name UCI_LimitStrength value false");
            assertThat(commands().lines().filter(line -> line.startsWith("started ")).count()).isEqualTo(1);
            assertThat(engine.status()).containsEntry("stockfishMoves", 3L).containsEntry("fallbackRequests", 0L);
        }
    }

    @Test void transmitsLegalMoveHistoryForRepetitionAndRejectsCommandInjection() throws Exception {
        try (var engine = engine("reply:b8c6", 1)) {
            engine.warmUp();
            var history = List.of("e2e4", "e7e5", "g1f3");
            Position position = Position.initial();
            for (String uci : history) {
                var move = position.legalMoves().stream().filter(m -> m.uci().equals(uci)).findFirst().orElseThrow();
                position = position.play(move);
            }
            assertThat(engine.choose(position, history, Difficulty.HARD, 1000)).isPresent();
            assertThat(commands()).contains("position startpos moves e2e4 e7e5 g1f3");
            assertThat(StockfishEngine.positionCommand(position, List.of("e2e4\nquit")))
                    .isEqualTo("position fen " + position.fen());
        }
    }

    @Test void timeoutCrashAndIllegalResponsesReturnControlForFallback() throws Exception {
        var expected = java.util.Map.of("hang", "engine deadline exceeded", "crash", "engine process exited",
                "illegal", "engine returned an illegal or missing move", "malformed", "malformed engine response");
        for (String mode : List.of("hang", "crash", "illegal", "malformed")) {
            try (var engine = engine(mode, 1)) {
                long start = System.nanoTime();
                assertThat(engine.choose(Position.initial(), List.of(), Difficulty.HARD, mode.equals("hang") ? 700 : 3000))
                        .as(mode).isEmpty();
                assertThat(Duration.ofNanos(System.nanoTime() - start)).isLessThan(Duration.ofSeconds(4));
                assertThat(engine.status()).containsEntry("fallbackRequests", 1L).containsEntry("readyProcesses", 0L)
                        .containsEntry("lastFailure", expected.get(mode));
            }
        }
    }

    @Test void restartsAfterAFailureWithoutReadingOldResponses() throws Exception {
        try (var engine = engine("crash-once", 1)) {
            assertThat(engine.choose(Position.initial(), List.of(), Difficulty.HARD, 3000)).isEmpty();
            assertThat(engine.status()).containsEntry("lastFailure", "engine process exited");
            assertThat(engine.choose(Position.initial(), List.of(), Difficulty.HARD, 3000)).isPresent();
            assertThat(commands().lines().filter(line -> line.startsWith("started ")).count()).isEqualTo(2);
            assertThat(engine.status()).containsEntry("fallbackRequests", 1L).containsEntry("stockfishMoves", 1L);
        }
    }

    @Test void poolCapacityAndShutdownBoundNativeProcessesAndPendingRequests() throws Exception {
        try (var engine = engine("hang", 2); var threads = Executors.newVirtualThreadPerTaskExecutor()) {
            var first = threads.submit(() -> engine.choose(Position.initial(), List.of(), Difficulty.HARD, 5000));
            var second = threads.submit(() -> engine.choose(Position.initial(), List.of(), Difficulty.HARD, 5000));
            await().atMost(Duration.ofSeconds(3)).until(() ->
                    commands().lines().filter(line -> line.startsWith("go movetime")).count() == 2);
            assertThat(engine.choose(Position.initial(), List.of(), Difficulty.HARD, 100)).isEmpty();
            assertThat(commands().lines().filter(line -> line.startsWith("started ")).count()).isEqualTo(2);
            engine.close();
            assertThat(first.get(2, java.util.concurrent.TimeUnit.SECONDS)).isEmpty();
            assertThat(second.get(2, java.util.concurrent.TimeUnit.SECONDS)).isEmpty();
            assertThat(engine.status()).containsEntry("readyProcesses", 0L);
        }
    }

    @Test void missingExecutableAndDisabledEngineKeepFallbackAvailable() {
        var settings = new StockfishEngine.Settings(true, temporary.resolve("missing").toString(), 1, 16, 100, 0);
        try (var engine = new StockfishEngine(settings)) {
            assertThat(engine.choose(Position.initial(), List.of(), Difficulty.HARD, 200)).isEmpty();
            assertThat(engine.status()).containsEntry("lastFailure", "process unavailable");
        }
        try (var engine = new StockfishEngine(new StockfishEngine.Settings(false, "missing", 1, 16, 100, 0))) {
            engine.warmUp();
            assertThat(engine.choose(Position.initial(), List.of(), Difficulty.HARD, 200)).isEmpty();
            assertThat(engine.status()).containsEntry("enabled", false).containsEntry("readyProcesses", 0L);
        }
    }

    /** Real child process, so tests cover pipe framing, process death and cancellation rather than mocking I/O. */
    public static class FakeEngine {
        public static void main(String[] arguments) throws Exception {
            String mode = arguments[0];
            Path log = Path.of(arguments[1]), marker = Path.of(arguments[2]);
            Files.writeString(log, "started " + ProcessHandle.current().pid() + "\n", StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            var reader = new BufferedReader(new InputStreamReader(System.in));
            String command;
            while ((command = reader.readLine()) != null) {
                Files.writeString(log, command + "\n", StandardOpenOption.APPEND);
                if (command.equals("uci")) System.out.println("id name Stockfish Test\nuciok");
                if (command.equals("isready")) System.out.println("readyok");
                if (command.startsWith("go ")) {
                    if (mode.equals("hang")) new java.util.concurrent.CountDownLatch(1).await();
                    if (mode.equals("crash")) System.exit(7);
                    if (mode.equals("crash-once") && !Files.exists(marker)) { Files.writeString(marker, "failed"); System.exit(7); }
                    System.out.println(mode.equals("malformed") ? "bestmove " : "bestmove " + (mode.equals("illegal") ? "e2e5"
                            : mode.startsWith("reply:") ? mode.substring(6) : "e2e4"));
                }
                System.out.flush();
            }
        }
    }
}
