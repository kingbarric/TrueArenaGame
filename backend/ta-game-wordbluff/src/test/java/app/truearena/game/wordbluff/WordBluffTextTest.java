package app.truearena.game.wordbluff;

import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Test;
import java.util.List;
import java.util.Map;
import static org.assertj.core.api.Assertions.*;

class WordBluffTextTest {
    private final WordBluffModule module = new WordBluffModule();

    private WordBluffState turn(boolean textMode) {
        var state = (WordBluffState) module.initialState(List.of("a", "b", "c", "d"),
                new WordBluffConfig(30, 60, textMode), RandomSource.seeded(42));
        state = (WordBluffState) module.onPlayerAction(state, PlayerAction.of(state.currentDescriber(), "SPIN", Map.of()));
        return (WordBluffState) module.onPlayerAction(state,
                PlayerAction.of(state.currentDescriber(), "START_TURN_CLOCK", Map.of()));
    }

    @Test void cluesArePublicButTheAnswerIsHiddenFromTheGuesser() {
        var state = turn(true);
        String partner = state.teamOf(state.turnTeam).stream().filter(p -> !p.equals(state.currentDescriber())).findFirst().orElseThrow();
        var next = (WordBluffState) module.onPlayerAction(state, PlayerAction.of(state.currentDescriber(),
                "TEXT_CLUE", Map.of("text", "Describe its use and where it is found", "wordIndex", 0)));
        assertThat(next.events()).anyMatch(e -> e.type().equals("TEXT_CLUE"));
        assertThat(module.visibleStateFor(next, partner).data()).doesNotContainKey("yourWord");
        assertThat(next.currentWord).isEqualTo(state.currentWord);
    }

    @Test void incorrectGuessesDoNotConsumeTheWordAndCorrectGuessesWaitForReview() {
        var state = turn(true);
        String partner = state.teamOf(state.turnTeam).stream().filter(p -> !p.equals(state.currentDescriber())).findFirst().orElseThrow();
        var wrong = (WordBluffState) module.onPlayerAction(state, PlayerAction.of(partner, "TEXT_GUESS",
                Map.of("text", "definitely not the answer", "wordIndex", 0)));
        assertThat(wrong.turnAttempts).isEmpty();
        assertThat(wrong.currentWord).isEqualTo(state.currentWord);
        var correct = (WordBluffState) module.onPlayerAction(wrong, PlayerAction.of(partner, "TEXT_GUESS",
                Map.of("text", state.currentWord.toUpperCase() + "!", "wordIndex", 0)));
        assertThat(correct.turnAttempts).hasSize(1);
        assertThat(correct.turnAttempts.get(0).correct()).isTrue();
        assertThat(correct.scoreOf(state.turnTeam)).isZero();
        assertThatThrownBy(() -> module.onPlayerAction(correct, PlayerAction.of(partner, "TEXT_GUESS",
                Map.of("text", correct.currentWord, "wordIndex", 0))))
                .isInstanceOf(RuleViolation.class).hasFieldOrPropertyWithValue("code", "STALE_WORD");
    }

    @Test void rejectsLeakedWordsWrongRolesAndTextInVoiceGames() {
        var state = turn(true);
        String judge = state.otherTeam(state.turnTeam).equals("A") ? state.teamA.get(0) : state.teamB.get(0);
        assertThatThrownBy(() -> module.onPlayerAction(state, PlayerAction.of(state.currentDescriber(), "TEXT_CLUE",
                Map.of("text", "It is " + state.currentWord, "wordIndex", 0))))
                .hasFieldOrPropertyWithValue("code", "WORD_IN_CLUE");
        assertThatThrownBy(() -> module.onPlayerAction(state, PlayerAction.of(judge, "TEXT_GUESS",
                Map.of("text", state.currentWord, "wordIndex", 0))))
                .hasFieldOrPropertyWithValue("code", "NOT_A_GUESSER");
        var voice = turn(false);
        assertThatThrownBy(() -> module.onPlayerAction(voice, PlayerAction.of(voice.currentDescriber(), "TEXT_CLUE",
                Map.of("text", "A clue", "wordIndex", 0))))
                .hasFieldOrPropertyWithValue("code", "VOICE_GAME");
    }
}
