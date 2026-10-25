package app.truearena;

import app.truearena.api.bot.*;
import app.truearena.app.StockfishInfoConfig;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.boot.actuate.info.Info;
import org.springframework.boot.actuate.info.InfoContributor;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.core.env.MapPropertySource;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class StockfishWiringTest {
    private AnnotationConfigApplicationContext context(boolean enabled, String path) {
        var context = new AnnotationConfigApplicationContext();
        context.getEnvironment().getPropertySources().addFirst(new MapPropertySource("test", Map.of(
                "bots.chess.stockfish.enabled", enabled,
                "bots.draughts.scan.enabled", false,
                "bots.chess.stockfish.path", path,
                "bots.chess.stockfish.processes", 1)));
        context.register(StockfishConfig.class, ScanConfig.class, GameBotAdapterFactory.class, StockfishInfoConfig.class);
        context.refresh();
        return context;
    }

    @Test void disabledEngineStillWiresFactoryAndReportsItsStatus() {
        try (var context = context(false, "missing-stockfish")) {
            assertThat(context.getBean(GameBotAdapterFactory.class).create("chess")).isInstanceOf(ChessBotAdapter.class);
            var info = new Info.Builder();
            context.getBean(InfoContributor.class).contribute(info);
            assertThat(info.build().getDetails()).containsEntry("stockfish", context.getBean(StockfishEngine.class).status());
            assertThat(context.getBean(StockfishEngine.class).status()).containsEntry("enabled", false);
        }
    }

    @Test
    @EnabledIfSystemProperty(named = "stockfish.test.path", matches = ".+")
    void factoryUsesConfiguredStockfishAndContextShutdownReleasesProcesses() {
        StockfishEngine engine;
        try (var context = context(true, System.getProperty("stockfish.test.path"))) {
            engine = context.getBean(StockfishEngine.class);
            var adapter = context.getBean(GameBotAdapterFactory.class).create("chess");
            var module = new app.truearena.game.chess.ChessModule();
            var state = module.initialState(java.util.List.of("a", "b"), app.truearena.game.chess.ChessConfig.defaults(),
                    app.truearena.engine.RandomSource.seeded(17));
            String actor = module.playersToAct(state).iterator().next();
            assertThat(adapter.onFrame("SNAPSHOT", module.visibleStateFor(state, actor).data(), actor, Difficulty.HARD)).isPresent();
            module.onPlayerAction(state, adapter.decideLocally(actor, Difficulty.HARD).orElseThrow());
            assertThat(engine.status()).containsEntry("stockfishMoves", 1L).containsEntry("fallbackRequests", 0L);
        }
        assertThat(engine.status()).containsEntry("readyProcesses", 0L);
    }
}
