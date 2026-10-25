package app.truearena.api.bot;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class StockfishConfig {
    @Bean(destroyMethod = "close")
    public StockfishEngine stockfishEngine(
            @Value("${bots.chess.stockfish.enabled:true}") boolean enabled,
            @Value("${bots.chess.stockfish.path:stockfish}") String path,
            @Value("${bots.chess.stockfish.processes:2}") int processes,
            @Value("${bots.chess.stockfish.hash-mb:16}") int hashMb,
            @Value("${bots.chess.stockfish.max-think-ms:1500}") long maxThinkMs,
            @Value("${bots.chess.stockfish.restart-backoff-ms:1000}") long restartBackoffMs) {
        var engine = new StockfishEngine(new StockfishEngine.Settings(enabled, path, processes, hashMb,
                maxThinkMs, restartBackoffMs));
        engine.warmUp();
        return engine;
    }
}
