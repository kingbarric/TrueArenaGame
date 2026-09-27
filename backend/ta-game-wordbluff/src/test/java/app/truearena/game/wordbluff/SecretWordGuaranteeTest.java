package app.truearena.game.wordbluff;

import app.truearena.engine.GameEvent;
import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.PlayerVisibleState;
import app.truearena.engine.RandomSource;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The current word is private to the describer and opposing judges. The
 * guessing team, broadcast view, and public events cannot see it.
 */
class SecretWordGuaranteeTest {

    private final WordBluffModule module = new WordBluffModule();

    @Test
    void currentWordNeverLeaksToNonDescriberOrBroadcast() {
        for (long seed = 1; seed <= 20; seed++) {
            playAndAudit(6, seed);
            playAndAudit(4, seed);
        }
    }

    private void playAndAudit(int n, long seed) {
        List<String> ids = IntStream.rangeClosed(1, n).mapToObj(i -> "p" + i).toList();
        GameState state = module.initialState(ids, new WordBluffConfig(15, 60), RandomSource.seeded(seed));
        audit(state, ids);

        int guard = 0;
        while (!state.finished() && guard++ < 300) {
            WordBluffState s = (WordBluffState) state;
            String describer = s.currentDescriber();
            if (s.currentWord == null && s.currentCategory == null) {
                state = module.onPlayerAction(state, PlayerAction.of(describer, "SPIN", java.util.Map.of()));
            } else if (s.currentWord == null) {
                state = module.onPlayerAction(state, PlayerAction.of(describer, "REVEAL", java.util.Map.of()));
            } else {
                String opponent = ((WordBluffState) state).teamA.contains(describer)
                        ? ((WordBluffState) state).teamB.get(0) : ((WordBluffState) state).teamA.get(0);
                state = guard % 2 == 0
                        ? module.onPlayerAction(state, PlayerAction.of(opponent, "MARK", java.util.Map.of("correct", true)))
                        : module.onPlayerAction(state, PlayerAction.of(describer, "SKIP", java.util.Map.of()));
            }
            audit(state, ids);
            if ("Turn".equals(state.phase()) && guard % 5 == 0) {
                state = module.onPhaseElapsed(state, "Turn");
                audit(state, ids);
                if ("Review".equals(state.phase())) {
                    state = module.onPhaseElapsed(state, "Review");
                    audit(state, ids);
                }
            }
        }
    }

    private void audit(GameState state, List<String> ids) {
        WordBluffState s = (WordBluffState) state;
        String describer = s.finished() ? null : s.currentDescriber();
        String word = s.currentWord;

        for (String id : ids) {
            PlayerVisibleState view = module.visibleStateFor(state, id);
            if (word != null) {
                boolean maySeeWord = id.equals(describer)
                        || s.otherTeam(s.turnTeam).equals(s.teamOfPlayer(id));
                if (maySeeWord) {
                    assertThat(view.data().get("yourWord")).isEqualTo(word);
                } else {
                    assertThat(view.data().values()).doesNotContain((Object) word);
                    assertThat(view.data()).doesNotContainKey("yourWord");
                }
            }
        }

        assertThat(module.broadcastState(state).data().values()).doesNotContain((Object) word);

        for (GameEvent e : s.events()) {
            if (e.type().equals("WORD_REVEALED")) {
                assertThat(e.visibility().isPublic()).isFalse();
            } else {
                assertThat(e.payload().values()).doesNotContain((Object) word);
            }
        }
    }
}
