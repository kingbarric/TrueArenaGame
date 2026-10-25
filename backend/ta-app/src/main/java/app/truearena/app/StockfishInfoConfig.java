package app.truearena.app;

import app.truearena.api.bot.StockfishEngine;
import org.springframework.boot.actuate.info.InfoContributor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Operators can distinguish normal Stockfish play from degraded fallback play. */
@Configuration
public class StockfishInfoConfig {
    @Bean public InfoContributor stockfishInfo(StockfishEngine stockfish) {
        return builder -> builder.withDetail("stockfish", stockfish.status());
    }
}
