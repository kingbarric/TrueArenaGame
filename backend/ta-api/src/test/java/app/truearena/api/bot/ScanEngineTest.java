package app.truearena.api.bot;

import app.truearena.game.draughts.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.*;
import org.junit.jupiter.api.io.TempDir;

import java.io.*;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermissions;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.Executors;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

@EnabledOnOs({OS.LINUX, OS.MAC})
class ScanEngineTest {
    @TempDir Path temporary;
    private Piece[] board() {
        Piece[] board = new Piece[50];
        Arrays.fill(board, 0, 20, Piece.A_MAN); Arrays.fill(board, 30, 50, Piece.B_MAN);
        return board;
    }
    private ScanEngine engine(String mode, int workers) throws Exception {
        Path executable = temporary.resolve("scan with spaces.sh");
        String command = "#!/bin/sh\nexec " + quote(Path.of(System.getProperty("java.home"), "bin", "java").toString())
                + " -cp " + quote(System.getProperty("java.class.path")) + " " + quote(FakeScan.class.getName())
                + " " + quote(mode) + " " + quote(temporary.resolve("commands.log").toString())
                + " " + quote(temporary.resolve("crashed").toString()) + "\n";
        Files.writeString(executable, command);
        Files.setPosixFilePermissions(executable, PosixFilePermissions.fromString("rwx------"));
        return new ScanEngine(new ScanEngine.Settings(true, executable.toString(), temporary.toString(), workers, 20, 100));
    }
    private static String quote(String value) { return "'" + value.replace("'", "'\"'\"'") + "'"; }
    private String commands() throws Exception {
        Path log = temporary.resolve("commands.log"); return Files.exists(log) ? Files.readString(log) : "";
    }

    @Test void reusesHubWorkerAndSetsResourcesAndDifficultyWithoutPondering() throws Exception {
        try (var engine = engine("normal", 1)) {
            engine.warmUp();
            for (Difficulty level : Difficulty.values())
                assertThat(engine.choose(board(), "A", level, 2000)).contains(List.of(new ScanMoveCodec.Move(19, 24)));
            assertThat(commands()).contains("set-param name=variant value=normal", "set-param name=threads value=1",
                    "set-param name=tt-size value=20", "set-param name=bb-size value=0", "set-param name=book value=false",
                    "set-param name=ponder value=false", "level depth=4", "level depth=8", "level depth=99", "new-game");
            assertThat(commands().lines().filter(line -> line.startsWith("started ")).count()).isEqualTo(1);
            assertThat(engine.status()).containsEntry("scanTurns", 3L).containsEntry("fallbackRequests", 0L);
        }
    }

    @Test void timeoutCrashAndIllegalOutputReleaseTheWorkerForFallback() throws Exception {
        Map<String, String> reasons = Map.of("hang", "engine deadline exceeded", "crash", "engine process exited",
                "illegal", "engine move disagrees with server rules", "empty", "engine returned no move");
        for (String mode : List.of("hang", "crash", "illegal", "empty")) {
            try (var engine = engine(mode, 1)) {
                engine.warmUp();
                assertThat(engine.choose(board(), "A", Difficulty.HARD, mode.equals("hang") ? 200 : 3000)).isEmpty();
                assertThat(engine.status()).containsEntry("readyProcesses", 0L).containsEntry("lastFailure", reasons.get(mode));
            }
        }
    }

    @Test void restartsACrashedWorkerAfterBackoffWithoutReusingOldOutput() throws Exception {
        try (var engine = engine("crash-once", 1)) {
            engine.warmUp();
            assertThat(engine.choose(board(), "A", Difficulty.HARD, 3000)).isEmpty();
            assertThat(engine.status()).containsEntry("lastFailure", "engine process exited");
            Thread.sleep(1100);
            assertThat(engine.choose(board(), "A", Difficulty.HARD, 3000)).isPresent();
            assertThat(commands().lines().filter(line -> line.startsWith("started ")).count()).isEqualTo(2);
            assertThat(engine.status()).containsEntry("scanTurns", 1L).containsEntry("fallbackRequests", 1L);
        }
    }

    @Test void boundedPoolAndShutdownCancelPendingSearches() throws Exception {
        try (var engine = engine("hang", 2); var executor = Executors.newVirtualThreadPerTaskExecutor()) {
            engine.warmUp();
            var first = executor.submit(() -> engine.choose(board(), "A", Difficulty.HARD, 5000));
            var second = executor.submit(() -> engine.choose(board(), "A", Difficulty.HARD, 5000));
            await().atMost(Duration.ofSeconds(3)).until(() -> commands().lines().filter(s -> s.equals("go think")).count() == 2);
            assertThat(engine.choose(board(), "A", Difficulty.HARD, 100)).isEmpty();
            engine.close();
            assertThat(first.get(2, java.util.concurrent.TimeUnit.SECONDS)).isEmpty();
            assertThat(second.get(2, java.util.concurrent.TimeUnit.SECONDS)).isEmpty();
            assertThat(engine.status()).containsEntry("readyProcesses", 0L);
        }
    }

    @Test void disabledOrMissingEngineLeavesFallbackAvailable() {
        try (var engine = new ScanEngine(new ScanEngine.Settings(false, "missing", temporary.toString(), 1, 20, 100))) {
            engine.warmUp(); assertThat(engine.choose(board(), "A", Difficulty.HARD, 200)).isEmpty();
            assertThat(engine.status()).containsEntry("enabled", false);
        }
        try (var engine = new ScanEngine(new ScanEngine.Settings(true, temporary.resolve("missing").toString(), temporary.toString(), 1, 20, 100))) {
            assertThat(engine.choose(board(), "A", Difficulty.HARD, 200)).isEmpty();
            assertThat(engine.status()).containsEntry("lastFailure", "process unavailable");
        }
    }

    public static class FakeScan {
        public static void main(String[] arguments) throws Exception {
            String mode = arguments[0]; Path log = Path.of(arguments[1]), marker = Path.of(arguments[2]);
            Files.writeString(log, "started " + ProcessHandle.current().pid() + "\n", StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            var reader = new BufferedReader(new InputStreamReader(System.in));
            String command;
            while ((command = reader.readLine()) != null) {
                Files.writeString(log, command + "\n", StandardOpenOption.APPEND);
                if (command.equals("hub")) System.out.println("id name=Scan version=3.1\nwait");
                if (command.equals("init")) System.out.println("ready");
                if (command.equals("ping")) System.out.println("pong");
                if (command.equals("go think")) {
                    if (mode.equals("hang")) new java.util.concurrent.CountDownLatch(1).await();
                    if (mode.equals("crash")) System.exit(7);
                    if (mode.equals("crash-once") && !Files.exists(marker)) { Files.writeString(marker, "crashed"); System.exit(7); }
                    System.out.println(mode.equals("empty") ? "done" : "done move=" + (mode.equals("illegal") ? "1-50" : "20-25"));
                }
                System.out.flush();
            }
        }
    }
}
