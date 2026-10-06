package app.truearena.api.bot;

import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.game.chess.ChessConfig;
import app.truearena.game.chess.ChessModule;
import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@link ChessBotAdapter} driven by the snapshots {@link ChessModule}
 * really produces — if the agent misread them it would silently never move.
 */
class ChessBotAdapterTest {

    private static final String HUMAN = "alice";
    private static final String BOT = "bot-1";

    private final ChessModule module = new ChessModule();

    private GameState start(long seed) {
        return module.initialState(List.of(HUMAN, BOT), ChessConfig.defaults(), RandomSource.seeded(seed));
    }

    private Map<String, Object> snapshot(GameState state) {
        Map<String, Object> view = new HashMap<>(module.broadcastState(state).data());
        view.put("lobby", false);
        return view;
    }

    private ChessBotAdapter adapter() {
        ChessBotAdapter a = new ChessBotAdapter();
        a.pacing = false;
        a.thinkCapMs = 60;
        return a;
    }

    @SuppressWarnings("unchecked")
    private PlayerAction humanMove(GameState state, Random rng) {
        Map<String, List<String>> legal = (Map<String, List<String>>) snapshot(state).get("legalMoves");
        List<String> froms = List.copyOf(legal.keySet());
        String from = froms.get(rng.nextInt(froms.size()));
        List<String> tos = legal.get(from);
        String to = tos.get(rng.nextInt(tos.size()));
        Map<String, Object> data = new HashMap<>(Map.of("from", from, "to", to));
        List<?> board = (List<?>) snapshot(state).get("board");
        Object piece = board.get(app.truearena.game.chess.Square.parse(from));
        if (String.valueOf(piece).endsWith("P") && (to.endsWith("8") || to.endsWith("1"))) {
            data.put("promotion", "q");
        }
        return PlayerAction.of(HUMAN, "MOVE", data);
    }

    private GameState startWithBotAs(boolean white) {
        for (long seed = 1; ; seed++) {
            GameState state = start(seed);
            if (botIsWhite(state) == white) {
                return state;
            }
        }
    }

    private boolean botIsWhite(GameState state) {
        return BOT.equals(snapshot(state).get("white"));
    }

    @Test
    void movesOnlyOnItsOwnTurn() {
        for (long seed = 1; seed <= 6; seed++) {
            GameState state = start(seed);
            ChessBotAdapter bot = adapter();
            boolean acts = bot.onFrame("SNAPSHOT", snapshot(state), BOT, Difficulty.MEDIUM).isPresent();
            assertThat(acts).isEqualTo(botIsWhite(state));
        }
    }

    @Test
    void ignoresLobbySnapshotsAndEvents() {
        ChessBotAdapter bot = adapter();
        assertThat(bot.onFrame("SNAPSHOT", Map.of("lobby", true), BOT, Difficulty.MEDIUM)).isEmpty();
        assertThat(bot.onFrame("EVENT", Map.of("type", "MOVE_PLAYED", "data", Map.of()), BOT, Difficulty.MEDIUM)).isEmpty();
    }

    @Test
    void neverActsTwiceOnTheSamePosition() {
        GameState state = startWithBotAs(true);
        ChessBotAdapter bot = adapter();
        assertThat(bot.onFrame("SNAPSHOT", snapshot(state), BOT, Difficulty.EASY)).isPresent();
        assertThat(bot.decideLocally(BOT, Difficulty.EASY)).isPresent();
        // The same snapshot again (a reconnect, a spectator joining) is not a new turn.
        assertThat(bot.onFrame("SNAPSHOT", snapshot(state), BOT, Difficulty.EASY)).isEmpty();
    }

    @Test
    void playsAWholeGameOfLegalMovesAgainstAPerson() {
        for (Difficulty level : Difficulty.values()) {
            Random rng = new Random(level.ordinal() + 3);
            GameState state = start(level.ordinal() + 10);
            ChessBotAdapter bot = adapter();
            int botMoves = 0;
            for (int ply = 0; ply < 80 && !state.finished(); ply++) {
                if (bot.onFrame("SNAPSHOT", snapshot(state), BOT, level).isPresent()) {
                    PlayerAction action = bot.decideLocally(BOT, level).orElseThrow();
                    // onPlayerAction throws RuleViolation on anything illegal.
                    state = module.onPlayerAction(state, action);
                    botMoves++;
                } else {
                    state = module.onPlayerAction(state, humanMove(state, rng));
                }
            }
            // Either the game ran its course or the agent mated a random mover early.
            assertThat(botMoves).as(level + " agent moved").isPositive();
            assertThat(state.finished() || botMoves > 5).as(level + " agent kept playing").isTrue();
        }
    }

    @Test
    void answersADrawOfferAndPlaysOnInALevelPosition() {
        GameState state = startWithBotAs(false);
        ChessBotAdapter bot = adapter();
        state = module.onPlayerAction(state, PlayerAction.of(HUMAN, "OFFER_DRAW", Map.of()));
        assertThat(bot.onFrame("SNAPSHOT", snapshot(state), BOT, Difficulty.MEDIUM)).isPresent();
        PlayerAction answer = bot.decideLocally(BOT, Difficulty.MEDIUM).orElseThrow();
        assertThat(answer.type()).isEqualTo("DECLINE_DRAW"); // level position: play on
        state = module.onPlayerAction(state, answer);
        assertThat(module.broadcastState(state).data().get("pendingDrawOffer")).isNull();
    }

    @Test
    void waitsOutAPauseAndMovesOnResume() {
        GameState state = startWithBotAs(true);
        ChessBotAdapter bot = adapter();
        Map<String, Object> paused = snapshot(state);
        paused.put("paused", true);
        assertThat(bot.onFrame("SNAPSHOT", paused, BOT, Difficulty.EASY)).isEmpty();

        Map<String, Object> resumed = Map.of("type", "GAME_RESUMED", "data", Map.of("by", HUMAN));
        assertThat(bot.onFrame("EVENT", resumed, BOT, Difficulty.EASY)).isPresent();
        PlayerAction move = bot.decideLocally(BOT, Difficulty.EASY).orElseThrow();
        assertThat(move.type()).isEqualTo("MOVE");

        // Paused again mid-thought: the move was refused. Resuming retries it.
        bot.onFrame("EVENT", Map.of("type", "GAME_PAUSED", "data", Map.of("by", HUMAN)), BOT, Difficulty.EASY);
        assertThat(bot.onFrame("EVENT", resumed, BOT, Difficulty.EASY)).isPresent();
    }

    @Test
    void factoryKnowsChess() {
        GameBotAdapter adapter = new GameBotAdapterFactory().create("chess");
        assertThat(adapter).isInstanceOf(ChessBotAdapter.class);
        assertThat(adapter.decidesLocally()).isTrue();
    }
}
