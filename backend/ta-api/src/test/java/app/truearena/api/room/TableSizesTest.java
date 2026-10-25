package app.truearena.api.room;

import app.truearena.engine.GameConfig;
import app.truearena.engine.GameModule;
import app.truearena.engine.GameSettings;
import app.truearena.engine.RandomSource;
import app.truearena.game.chess.ChessConfig;
import app.truearena.game.chess.ChessModule;
import app.truearena.game.draughts.DraughtsConfig;
import app.truearena.game.draughts.DraughtsModule;
import app.truearena.game.goosi.GoosiConfig;
import app.truearena.game.goosi.GoosiModule;
import app.truearena.game.ludo.LudoConfig;
import app.truearena.game.ludo.LudoModule;
import app.truearena.game.monopoly.MonopolyConfig;
import app.truearena.game.monopoly.MonopolyModule;
import app.truearena.game.truearena.ConfigValidator;
import app.truearena.game.truearena.Presets;
import app.truearena.game.whot.WhotConfig;
import app.truearena.game.whot.WhotModule;
import app.truearena.game.wordbluff.WordBluffConfig;
import app.truearena.game.wordbluff.WordBluffModule;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** What the app is told is each game's minimum must be exactly what the game itself accepts. */
class TableSizesTest {

    private static List<String> players(int n) {
        return IntStream.range(0, n).mapToObj(i -> "p" + i).toList();
    }

    /** One fewer than the minimum is refused; the minimum itself starts. */
    private static void startsAtExactly(String gameType, String config, GameModule module, GameSettings settings) {
        int min = TableSizes.minPlayers(gameType, config);
        assertThatThrownBy(() -> module.initialState(players(min - 1), settings, RandomSource.seeded(1)))
                .as("%s with %d players", gameType, min - 1).isInstanceOf(RuntimeException.class);
        assertThat(module.initialState(players(min), settings, RandomSource.seeded(1))).isNotNull();
    }

    @Test void everyGameStartsAtTheMinimumTheAppShows() {
        startsAtExactly("draughts", null, new DraughtsModule(), DraughtsConfig.defaults());
        startsAtExactly("chess", null, new ChessModule(), ChessConfig.defaults());
        startsAtExactly("goosi", null, new GoosiModule(), GoosiConfig.defaults());
        startsAtExactly("ludo", null, new LudoModule(), LudoConfig.defaults());
        startsAtExactly("whot", null, new WhotModule(), WhotConfig.defaults());
        startsAtExactly("wordbluff", null, new WordBluffModule(), WordBluffConfig.defaults());
        startsAtExactly("monopoly", null, new MonopolyModule(), MonopolyConfig.defaults());
    }

    @Test void theTellStartsWithTwoTeamsOfTwo() {
        WhotConfig d = WhotConfig.defaults();
        WhotConfig tell = new WhotConfig(d.turnSeconds(), d.startingHand(), d.includeWhot(), d.pickTwo(),
                d.pickTwoStacking(), d.generalMarket(), d.holdOn(), d.suspension(), "tell", d.tellRule(), d.tellMinCards());
        startsAtExactly("whot", "{\"mode\":\"tell\"}", new WhotModule(), tell);
    }

    @Test void eachTraitorsModeStartsAtItsOwnMinimum() throws Exception {
        ObjectMapper json = new ObjectMapper();
        for (Presets.Mode mode : Presets.ALL) {
            int min = TableSizes.minPlayers("truearena", json.writeValueAsString(mode.config()));
            assertThat(ConfigValidator.validate(seated(mode.config(), min - 1)).ok()).as("%s at %d", mode.slug(), min - 1).isFalse();
            assertThat(ConfigValidator.validate(seated(mode.config(), min)).ok()).as("%s at %d", mode.slug(), min).isTrue();
        }
        // No rules stored: the server plays Classic Conspiracy.
        assertThat(TableSizes.minPlayers("truearena", null))
                .isEqualTo(Presets.CLASSIC_CONSPIRACY.config().table().minPlayers());
    }

    /** The mode's rules with {@code n} people at the table, as the server seats them at Start. */
    private static GameConfig seated(GameConfig base, int n) {
        GameConfig.Table t = base.table();
        return new GameConfig(base.catalogVersion(), base.preset(),
                new GameConfig.Table(n, t.minPlayers(), t.maxPlayers(), t.adminOverride(), t.traitorCurve()),
                base.timers(), base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(),
                base.suddenDeathSeconds(), base.afk(), base.voteReveal(), base.endgameVeil(), base.twists());
    }
}
