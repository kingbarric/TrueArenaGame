package app.truearena.api.bot;

import app.truearena.game.chess.Move;
import app.truearena.game.chess.Position;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/** Bounded, reusable UCI processes. A failed request returns empty so the Java engine can keep play moving. */
public final class StockfishEngine implements ChessMoveSource, AutoCloseable {
    private static final Logger log = LoggerFactory.getLogger(StockfishEngine.class);
    private static final String EOF = "\u0000EOF";
    private final Settings settings;
    private final List<Worker> workers = new ArrayList<>();
    private final ArrayBlockingQueue<Worker> idle;
    private final AtomicBoolean closed = new AtomicBoolean();
    private final AtomicLong successes = new AtomicLong();
    private final AtomicLong fallbacks = new AtomicLong();
    private final AtomicLong nextWarning = new AtomicLong();
    private volatile String lastFailure = "none";

    public record Settings(boolean enabled, String executable, int processes, int hashMb,
                           long maxThinkMs, long restartBackoffMs) {
        public Settings {
            if (executable == null || executable.isBlank() || processes < 1 || processes > 8
                    || hashMb < 1 || hashMb > 256 || maxThinkMs < 10 || maxThinkMs > 10000
                    || restartBackoffMs < 0 || restartBackoffMs > 60000)
                throw new IllegalArgumentException("Invalid Stockfish resource settings");
        }
    }

    public StockfishEngine(Settings settings) {
        this.settings = settings;
        idle = new ArrayBlockingQueue<>(settings.processes());
        for (int i = 0; i < settings.processes(); i++) {
            Worker worker = new Worker(i);
            workers.add(worker);
            idle.add(worker);
        }
    }

    /** Run at backend startup, keeping process/network-weight loading outside players' clocks. */
    public void warmUp() {
        if (!settings.enabled()) return;
        for (Worker worker : workers) {
            try {
                long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
                worker.ready(deadline);
                worker.send("position startpos");
                worker.send("go nodes 1"); // Load NNUE weights before any player's clock is running.
                worker.await("bestmove ", deadline);
            }
            catch (IOException | InterruptedException e) {
                worker.failed();
                warn(e);
                if (e instanceof InterruptedException) { Thread.currentThread().interrupt(); break; }
            }
        }
    }

    @Override public Optional<Move> choose(Position position, List<String> uciHistory, Difficulty level, long budgetMs) {
        if (closed.get() || !settings.enabled() || position.legalMoves().isEmpty()) return Optional.empty();
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(Math.max(1, budgetMs));
        Worker worker = null;
        try {
            // Contention is bounded by the same total budget as handshake and search.
            worker = idle.poll(Math.max(1, remaining(deadline)), TimeUnit.NANOSECONDS);
            if (worker == null) throw new IOException("engine pool busy");
            worker.ready(deadline);
            worker.send("ucinewgame"); // Clear all state before this pool slot serves another match.
            worker.send("setoption name UCI_LimitStrength value false");
            worker.send("setoption name Skill Level value " + skill(level));
            worker.send("isready");
            worker.await("readyok", deadline);
            worker.send(positionCommand(position, uciHistory));
            long searchMs = Math.min(settings.maxThinkMs(), TimeUnit.NANOSECONDS.toMillis(remaining(deadline)) - 15);
            if (searchMs < 1) throw new IOException("clock budget exhausted before search");
            worker.send("go movetime " + searchMs);
            String answer = worker.await("bestmove ", deadline);
            String[] parts = answer.trim().split("\\s+");
            if (parts.length < 2) throw new IOException("malformed engine response");
            String uci = parts[1];
            Optional<Move> move = position.legalMoves().stream().filter(candidate -> candidate.uci().equals(uci)).findFirst();
            if (move.isEmpty()) throw new IOException("engine returned an illegal or missing move");
            successes.incrementAndGet();
            return move;
        } catch (IOException | InterruptedException | RuntimeException e) {
            fallbacks.incrementAndGet();
            if (worker != null) worker.failed(); // Never reuse a process with unread/stale output.
            warn(e);
            if (e instanceof InterruptedException) Thread.currentThread().interrupt();
            return Optional.empty();
        } finally {
            if (worker != null && !closed.get()) idle.offer(worker);
        }
    }

    static int skill(Difficulty level) {
        return switch (level) { case EASY -> 2; case MEDIUM -> 10; case HARD -> 20; };
    }

    static String positionCommand(Position position, List<String> history) {
        // Full UCI history preserves repetition information. Validate against the snapshot,
        // and fall back to canonical FEN for imported/test positions without complete history.
        if (!history.isEmpty()) {
            Position replay = Position.initial();
            boolean valid = true;
            for (String uci : history) {
                Optional<Move> move = replay.legalMoves().stream().filter(candidate -> candidate.uci().equals(uci)).findFirst();
                if (move.isEmpty()) { valid = false; break; }
                replay = replay.play(move.get());
            }
            if (valid && replay.fen().equals(position.fen())) return "position startpos moves " + String.join(" ", history);
        }
        return "position fen " + position.fen();
    }

    public Map<String, Object> status() {
        return Map.of("enabled", settings.enabled(), "readyProcesses", workers.stream().filter(Worker::alive).count(),
                "maxProcesses", settings.processes(), "stockfishMoves", successes.get(),
                "fallbackRequests", fallbacks.get(), "lastFailure", lastFailure);
    }

    private void warn(Exception failure) {
        String message = failure.getMessage();
        lastFailure = message == null ? failure.getClass().getSimpleName()
                : message.startsWith("Cannot run program") ? "process unavailable" : message;
        long now = System.currentTimeMillis(), next = nextWarning.get();
        if (now >= next && nextWarning.compareAndSet(next, now + 30000))
            log.warn("Stockfish unavailable; built-in Chess fallback will be used: {}", lastFailure);
    }

    private static long remaining(long deadline) throws IOException {
        long nanos = deadline - System.nanoTime();
        if (nanos <= 0) throw new IOException("engine deadline exceeded");
        return nanos;
    }

    @Override public void close() {
        if (!closed.compareAndSet(false, true)) return;
        idle.clear();
        workers.forEach(Worker::destroy);
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
            Process started = new ProcessBuilder(settings.executable()).redirectErrorStream(true).start();
            process = started;
            input = new BufferedWriter(new OutputStreamWriter(started.getOutputStream(), StandardCharsets.UTF_8));
            ArrayBlockingQueue<String> lines = new ArrayBlockingQueue<>(256);
            output = lines;
            Thread.ofVirtual().name("stockfish-output-" + index).start(() -> {
                try (var reader = new BufferedReader(new InputStreamReader(started.getInputStream(), StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = reader.readLine()) != null) {
                        if (!lines.offer(line)) { started.destroyForcibly(); break; }
                    }
                } catch (IOException ignored) { /* process termination is observed by the requester */ }
                finally { lines.offer(EOF); }
            });
            if (closed.get()) { destroy(); throw new IOException("engine pool closed"); }
            send("uci");
            await("uciok", deadline);
            send("setoption name Threads value 1");
            send("setoption name Hash value " + settings.hashMb());
            send("setoption name Ponder value false");
            send("isready");
            await("readyok", deadline);
        }

        void send(String command) throws IOException {
            input.write(command); input.newLine(); input.flush();
        }

        String await(String prefix, long deadline) throws IOException, InterruptedException {
            while (true) {
                String line = output.poll(remaining(deadline), TimeUnit.NANOSECONDS);
                if (line == null) throw new IOException("engine deadline exceeded");
                if (line.equals(EOF)) throw new IOException("engine process exited");
                if (line.startsWith("info string CRITICAL ERROR")) throw new IOException("engine rejected its position or settings");
                if (line.startsWith(prefix)) return line;
            }
        }

        void failed() {
            destroy();
            retryAfter = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(settings.restartBackoffMs());
        }

        void destroy() {
            Process current = process;
            process = null;
            if (current != null) current.destroyForcibly();
        }
    }
}
