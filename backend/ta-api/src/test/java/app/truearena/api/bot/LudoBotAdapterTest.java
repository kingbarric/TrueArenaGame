package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class LudoBotAdapterTest {
    @Test void rollsThenChoosesOneOfTheServersLegalDieAndTokenPairs() {
        LudoBotAdapter bot = new LudoBotAdapter();
        bot.onFrame("SNAPSHOT", Map.of("phase", "Turn", "turnPlayer", "agent",
                "dice", List.of(), "legalMoves", List.of()), "agent", Difficulty.EASY);
        assertThat(bot.fallbackAction("agent").orElseThrow().type()).isEqualTo("ROLL");

        bot.onFrame("SNAPSHOT", Map.of("phase", "Turn", "turnPlayer", "agent",
                "dice", List.of(4, 6), "legalMoves", List.of(Map.of("token", 2, "die", 6))),
                "agent", Difficulty.EASY);
        assertThat(bot.parseAction("{\"token\": 2, \"die\": 6}", "agent")
                .map(PlayerAction::data)).contains(Map.of("token", 2, "die", 6));
        assertThat(bot.parseAction("{\"token\":0,\"die\":4}", "agent")).isEmpty();
        assertThat(bot.fallbackAction("agent").map(PlayerAction::data))
                .contains(Map.of("token", 2, "die", 6));
    }

    @Test void waitsForItsTurnAndDoesNothingAfterResults() {
        LudoBotAdapter bot = new LudoBotAdapter();
        assertThat(bot.onFrame("SNAPSHOT", Map.of("phase", "Turn", "turnPlayer", "human"),
                "agent", Difficulty.EASY)).isEmpty();
        assertThat(bot.onFrame("SNAPSHOT", Map.of("phase", "Results", "turnPlayer", "agent"),
                "agent", Difficulty.EASY)).isEmpty();
    }
}
