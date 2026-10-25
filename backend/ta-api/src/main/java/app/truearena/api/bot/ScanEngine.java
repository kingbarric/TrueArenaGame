package app.truearena.api.bot;

import app.truearena.game.draughts.Piece;
import app.truearena.game.draughts.ScanMoveCodec;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.*;
import java.util.regex.Pattern;

/** Bounded persistent Scan Hub workers, serving compatible international positions only. */
public final class ScanEngine implements DraughtsMoveSource, AutoCloseable {
    private static final Logger log = LoggerFactory.getLogger(ScanEngine.class);
    private static final Pattern MOVE = Pattern.compile("(?:^|\\s)move=(?:\"([^\"]+)\"|([^\\s]+))");
    private static final String EOF = "\u0000EOF";
    public record Settings(boolean enabled, String executable, String directory, int processes, int ttSize, long maxThinkMs) {
        public Settings {
            if (executable == null || executable.isBlank() || directory == null || directory.isBlank()
                    || processes < 1 || processes > 8 || ttSize < 16 || ttSize > 24 || maxThinkMs < 10 || maxThinkMs > 10000)
                throw new IllegalArgumentException("Invalid Scan settings");
        }
    }
    private final Settings settings;
    private final List<Worker> workers = new ArrayList<>();
    private final ArrayBlockingQueue<Worker> idle;
    private final AtomicBoolean closed = new AtomicBoolean();
    private final AtomicLong moves = new AtomicLong(), fallbacks = new AtomicLong(), nextWarning = new AtomicLong();
    private volatile String lastFailure = "none";

    public ScanEngine(Settings settings) {
        this.settings = settings;
        idle = new ArrayBlockingQueue<>(settings.processes());
        for (int i = 0; i < settings.processes(); i++) { var worker = new Worker(i); workers.add(worker); idle.add(worker); }
    }

    public void warmUp() {
        if (!settings.enabled() || closed.get()) return;
        for (Worker worker : workers) {
            try { worker.ready(System.nanoTime() + TimeUnit.SECONDS.toNanos(5)); }
            catch (IOException | InterruptedException | RuntimeException e) {
                worker.failed(); warn(e);
                if (e instanceof InterruptedException) { Thread.currentThread().interrupt(); break; }
            }
        }
    }

    @Override public Optional<List<ScanMoveCodec.Move>> choose(Piece[] board, String side, Difficulty difficulty, long budgetMs) {
        if (!settings.enabled() || closed.get()) return Optional.empty();
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(Math.max(1, budgetMs));
        Worker worker = null;
        try {
            worker = idle.poll(remaining(deadline), TimeUnit.NANOSECONDS);
            if (worker == null) throw new IOException("engine pool busy");
            worker.ready(deadline);
            worker.send("new-game");
            worker.send("ping"); worker.await("pong", deadline);
            worker.send("pos pos=" + ScanMoveCodec.position(board, side));
            long searchMs = Math.min(settings.maxThinkMs(), TimeUnit.NANOSECONDS.toMillis(remaining(deadline)) - 50);
            if (searchMs < 1) throw new IOException("clock budget exhausted before search");
            int depth = switch (difficulty) { case EASY -> 4; case MEDIUM -> 8; case HARD -> 99; };
            worker.send("level depth=" + depth + " move-time=" + String.format(Locale.ROOT, "%.3f", searchMs / 1000.0));
            worker.send("go think");
            var matcher = MOVE.matcher(worker.await("done", deadline));
            if (!matcher.find()) throw new IOException("engine returned no move");
            String notation = matcher.group(1) != null ? matcher.group(1) : matcher.group(2);
            var result = ScanMoveCodec.resolve(board, side, notation);
            if (result.isEmpty()) throw new IOException("engine move disagrees with server rules");
            remaining(deadline);
            moves.incrementAndGet();
            return result;
        } catch (IOException | InterruptedException | RuntimeException e) {
            fallbacks.incrementAndGet(); if (worker != null) worker.failed(); warn(e);
            if (e instanceof InterruptedException) Thread.currentThread().interrupt();
            return Optional.empty();
        } finally { if (worker != null && !closed.get()) idle.offer(worker); }
    }

    public Map<String, Object> status() {
        return Map.of("enabled", settings.enabled(), "readyProcesses", workers.stream().filter(Worker::alive).count(),
                "maxProcesses", settings.processes(), "scanTurns", moves.get(), "fallbackRequests", fallbacks.get(), "lastFailure", lastFailure);
    }

    private void warn(Exception exception) {
        String message = exception.getMessage();
        lastFailure = message == null ? exception.getClass().getSimpleName()
                : message.startsWith("Cannot run program") ? "process unavailable" : message;
        long now = System.currentTimeMillis(), next = nextWarning.get();
        if (now >= next && nextWarning.compareAndSet(next, now + 30000)) log.warn("Scan unavailable; built-in Draughts fallback will be used: {}", lastFailure);
    }

    private static long remaining(long deadline) throws IOException {
        long left = deadline - System.nanoTime();
        if (left <= 0) throw new IOException("engine deadline exceeded");
        return left;
    }

    @Override public void close() {
        if (!closed.compareAndSet(false, true)) return;
        idle.clear(); workers.forEach(Worker::destroy);
    }

    private final class Worker {
        private final int index;
        private volatile Process process;
        private BufferedWriter input;
        private ArrayBlockingQueue<String> output;
        private long retryAfter;
        Worker(int index) { this.index = index; }
        boolean alive() { Process current = process; return current != null && current.isAlive(); }

        void ready(long deadline) throws IOException, InterruptedException {
            if (closed.get()) throw new IOException("engine pool closed");
            if (alive()) return;
            if (System.nanoTime() < retryAfter) throw new IOException("engine restart cooling down");
            Process started = new ProcessBuilder(settings.executable(), "hub").directory(new File(settings.directory()))
                    .redirectErrorStream(true).start();
            process = started;
            input = new BufferedWriter(new OutputStreamWriter(started.getOutputStream(), StandardCharsets.UTF_8));
            var lines = new ArrayBlockingQueue<String>(256); output = lines;
            Thread.ofVirtual().name("scan-output-" + index).start(() -> {
                try (var reader = new BufferedReader(new InputStreamReader(started.getInputStream(), StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = reader.readLine()) != null) if (!lines.offer(line)) { started.destroyForcibly(); break; }
                } catch (IOException ignored) { /* requester observes EOF */ }
                finally { lines.offer(EOF); }
            });
            if (closed.get()) { destroy(); throw new IOException("engine pool closed"); }
            send("hub"); await("wait", deadline);
            send("set-param name=variant value=normal"); send("set-param name=book value=false");
            send("set-param name=ponder value=false"); send("set-param name=threads value=1");
            send("set-param name=tt-size value=" + settings.ttSize()); send("set-param name=bb-size value=0");
            send("init"); await("ready", deadline);
        }

        void send(String command) throws IOException { input.write(command); input.newLine(); input.flush(); }
        String await(String command, long deadline) throws IOException, InterruptedException {
            while (true) {
                String line = output.poll(remaining(deadline), TimeUnit.NANOSECONDS);
                if (line == null) throw new IOException("engine deadline exceeded");
                if (line.equals(EOF)) throw new IOException("engine process exited");
                if (line.startsWith("error ")) throw new IOException("engine rejected position or settings");
                if (line.equals(command) || line.startsWith(command + " ")) return line;
            }
        }
        void failed() { destroy(); retryAfter = System.nanoTime() + TimeUnit.SECONDS.toNanos(1); }
        void destroy() { Process current = process; process = null; if (current != null) current.destroyForcibly(); }
    }
}
