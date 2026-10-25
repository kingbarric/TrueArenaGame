package app.truearena;

import app.truearena.api.bot.*;
import app.truearena.app.ScanInfoConfig;
import app.truearena.engine.*;
import app.truearena.game.draughts.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.boot.actuate.info.*;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.core.env.MapPropertySource;
import java.util.*;
import static org.assertj.core.api.Assertions.assertThat;

class ScanWiringTest {
    private AnnotationConfigApplicationContext context(boolean enabled) {
        var context = new AnnotationConfigApplicationContext();
        context.getEnvironment().getPropertySources().addFirst(new MapPropertySource("test", Map.of(
                "bots.chess.stockfish.enabled", false, "bots.draughts.scan.enabled", enabled,
                "bots.draughts.scan.path", System.getProperty("scan.test.path", "missing-scan"),
                "bots.draughts.scan.directory", System.getProperty("scan.test.directory", "."),
                "bots.draughts.scan.processes", 1, "bots.draughts.scan.max-think-ms", 100)));
        context.register(StockfishConfig.class, ScanConfig.class, GameBotAdapterFactory.class, ScanInfoConfig.class);
        context.refresh(); return context;
    }

    @Test void disabledScanWiresFactoryAndReportsStatus() {
        try (var context = context(false)) {
            assertThat(context.getBean(GameBotAdapterFactory.class).create("draughts")).isInstanceOf(DraughtsBotAdapter.class);
            var info = new Info.Builder(); context.getBean(InfoContributor.class).contribute(info);
            assertThat(info.build().getDetails()).containsEntry("scan", context.getBean(ScanEngine.class).status());
        }
    }

    @Test @EnabledIfSystemProperty(named = "scan.test.path", matches = ".+")
    void configuredScanServesStandardGamesAndClosesWithTheApplication() {
        ScanEngine engine;
        try (var context = context(true)) {
            engine = context.getBean(ScanEngine.class);
            var bot = context.getBean(GameBotAdapterFactory.class).create("draughts");
            var game = new DraughtsModule();
            GameState state = game.initialState(List.of("a", "b"), new DraughtsConfig(60, true), RandomSource.seeded(17));
            String actor = game.playersToAct(state).iterator().next();
            bot.onFrame("SNAPSHOT", game.visibleStateFor(state, actor).data(), actor, Difficulty.HARD);
            game.onPlayerAction(state, bot.decideLocally(actor, Difficulty.HARD).orElseThrow());
            assertThat(engine.status()).containsEntry("scanTurns", 1L).containsEntry("fallbackRequests", 0L);
        }
        assertThat(engine.status()).containsEntry("readyProcesses", 0L);
    }
}
