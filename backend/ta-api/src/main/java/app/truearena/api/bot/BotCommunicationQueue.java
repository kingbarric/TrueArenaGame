package app.truearena.api.bot;

import reactor.core.Disposable;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;

import java.util.concurrent.ArrayBlockingQueue;
import java.util.function.Supplier;

/** A bounded, independently consumed queue: a slow model cannot stall game frames. */
final class BotCommunicationQueue implements AutoCloseable {
    private final Sinks.Many<Supplier<Mono<Void>>> queue =
            Sinks.many().unicast().onBackpressureBuffer(new ArrayBlockingQueue<>(8));
    private final Disposable worker = queue.asFlux()
            .concatMap(task -> Mono.defer(task).onErrorResume(error -> Mono.empty()), 1)
            .subscribe();

    synchronized void offer(Supplier<Mono<Void>> task) {
        queue.tryEmitNext(task); // Full queues drop optional dialogue, never gameplay.
    }

    @Override public synchronized void close() {
        worker.dispose();
        queue.tryEmitComplete();
    }
}
