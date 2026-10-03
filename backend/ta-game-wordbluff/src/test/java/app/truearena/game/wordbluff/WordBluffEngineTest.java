package app.truearena.game.wordbluff;

import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import app.truearena.engine.WinResult;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class WordBluffEngineTest {

    private final WordBluffModule module = new WordBluffModule();

    private List<String> players(int n) {
        return IntStream.rangeClosed(1, n).mapToObj(i -> "p" + i).toList();
    }

    @Test
    void rejectsFewerThanFourPlayers() {
        assertThatThrownBy(() -> module.initialState(players(3), WordBluffConfig.defaults(), RandomSource.seeded(1)))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_ENOUGH_PLAYERS");
    }

    @Test
    void splitsIntoTwoTeamsAndStartsTurn() {
        GameState state = module.initialState(players(6), WordBluffConfig.defaults(), RandomSource.seeded(42));
        WordBluffState s = (WordBluffState) state;
        assertThat(s.teamA.size() + s.teamB.size()).isEqualTo(6);
        assertThat(s.phase()).isEqualTo("Turn");
        assertThat(s.round()).isEqualTo(1);
    }

    @Test
    void onlyDescriberCanSpinRevealAndResolve() {
        GameState state = module.initialState(players(4), WordBluffConfig.defaults(), RandomSource.seeded(7));
        WordBluffState s = (WordBluffState) state;
        String describer = s.currentDescriber();
        String other = s.teamA.contains(describer) ? s.teamB.get(0) : s.teamA.get(0);

        assertThatThrownBy(() -> module.onPlayerAction(state, PlayerAction.of(other, "SPIN", java.util.Map.of())))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_YOUR_TURN");
    }

    @Test
    void aMarkedWordDoesNotScoreUntilBothTeamsAcceptTheReview() {
        GameState state = module.initialState(players(4), WordBluffConfig.defaults(), RandomSource.seeded(3));
        WordBluffState s = (WordBluffState) state;
        String startingTeam = s.turnTeam;

        state = playWord(state, true);

        WordBluffState marked = (WordBluffState) state;
        assertThat(marked.turnAttempts).hasSize(1);
        assertThat(marked.turnAttempts.get(0).correct()).isTrue();
        // the point is only *proposed* — the scoreboard has not moved
        assertThat(marked.scoreOf(startingTeam)).isZero();
        // Resolving a word doesn't end the turn — the next one from the same
        // category is already up, because the describer is racing a clock.
        assertThat(marked.currentWord).isNotNull();
        assertThat(marked.currentCategory).isNotNull();

        state = endTurnAndCommit(state);
        assertThat(((WordBluffState) state).scoreOf(startingTeam)).isEqualTo(1);
    }

    @Test
    void onlyTheOpposingTeamMayMarkAWord() {
        GameState state = module.initialState(players(4), WordBluffConfig.defaults(), RandomSource.seeded(11));
        WordBluffState s = (WordBluffState) state;
        String describer = s.currentDescriber();
        String teammate = s.teamOf(s.turnTeam).stream().filter(p -> !p.equals(describer)).findFirst().orElseThrow();

        GameState revealed = module.onPlayerAction(
                module.onPlayerAction(state, PlayerAction.of(describer, "SPIN", java.util.Map.of())),
                PlayerAction.of(describer, "REVEAL", java.util.Map.of()));

        // the describer cannot award their own team the point...
        assertThatThrownBy(() -> module.onPlayerAction(revealed,
                PlayerAction.of(describer, "MARK", java.util.Map.of("correct", true))))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_YOUR_CALL");
        // ...nor can their partner
        assertThatThrownBy(() -> module.onPlayerAction(revealed,
                PlayerAction.of(teammate, "MARK", java.util.Map.of("correct", true))))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_YOUR_CALL");
    }

    @Test
    void lateMarkCannotResolveTheNextWord() {
        GameState state = module.initialState(players(4), WordBluffConfig.defaults(), RandomSource.seeded(11));
        WordBluffState start = (WordBluffState) state;
        state = module.onPlayerAction(state, PlayerAction.of(start.currentDescriber(), "SPIN", java.util.Map.of()));
        String oldWord = ((WordBluffState) state).currentWord;
        String judge = opponentOf((WordBluffState) state);
        state = module.onPlayerAction(state, PlayerAction.of(judge, "MARK",
                java.util.Map.of("correct", true, "word", oldWord)));
        GameState nextWord = state;
        assertThat(((WordBluffState) nextWord).currentWord).isNotEqualTo(oldWord);
        assertThatThrownBy(() -> module.onPlayerAction(nextWord, PlayerAction.of(judge, "MARK",
                java.util.Map.of("correct", true, "word", oldWord))))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "STALE_WORD");
    }

    @Test
    void eitherSideCanCorrectACallDuringReviewAndThatResetsAcceptance() {
        GameState state = module.initialState(players(4), WordBluffConfig.defaults(), RandomSource.seeded(5));
        WordBluffState start = (WordBluffState) state;
        String startingTeam = start.turnTeam;

        state = playWord(state, true);
        state = module.onPhaseElapsed(state, "Turn");
        WordBluffState review = (WordBluffState) state;
        assertThat(review.phase()).isEqualTo("Review");

        // one side accepts, then the other side disputes the call
        state = module.onPlayerAction(state, PlayerAction.of(review.teamA.get(0), "REVIEW_ACCEPT", java.util.Map.of()));
        assertThat(((WordBluffState) state).reviewAccepted).hasSize(1);

        state = module.onPlayerAction(state, PlayerAction.of(review.teamB.get(0), "REVIEW_TOGGLE", java.util.Map.of("index", 0)));
        WordBluffState corrected = (WordBluffState) state;
        assertThat(corrected.turnAttempts.get(0).correct()).isFalse();
        // a correction invalidates the earlier sign-off
        assertThat(corrected.reviewAccepted).isEmpty();

        state = module.onPlayerAction(state, PlayerAction.of(review.teamA.get(0), "REVIEW_ACCEPT", java.util.Map.of()));
        state = module.onPlayerAction(state, PlayerAction.of(review.teamB.get(0), "REVIEW_ACCEPT", java.util.Map.of()));
        // the disputed word scored nothing
        assertThat(((WordBluffState) state).scoreOf(startingTeam)).isZero();
    }

    @Test
    void skipDoesNotScoreButConsumesTheWord() {
        GameState state = module.initialState(players(4), WordBluffConfig.defaults(), RandomSource.seeded(9));
        WordBluffState s = (WordBluffState) state;
        String describer = s.currentDescriber();

        // The wheel is spun once a turn; after that, resolving a word puts
        // the next one from the same category straight up.
        if (s.currentCategory == null) {
            state = module.onPlayerAction(state, PlayerAction.of(describer, "SPIN", java.util.Map.of()));
        }
        WordBluffState revealed = (WordBluffState) state;
        // find the revealed word via events (describer-only event)
        String word = revealed.events.stream()
                .filter(e -> e.type().equals("WORD_REVEALED"))
                .reduce((a, b) -> b).orElseThrow().payload().get("word").toString();

        state = module.onPlayerAction(state, PlayerAction.of(describer, "SKIP", java.util.Map.of()));
        WordBluffState after = (WordBluffState) state;
        assertThat(after.teamAScore + after.teamBScore).isZero();
        assertThat(after.usedWords).contains(word);
    }

    @Test
    void turnEndRotatesToOtherTeamAndAdvancesDescriberOnReturn() {
        GameState state = module.initialState(players(4), WordBluffConfig.defaults(), RandomSource.seeded(11));
        WordBluffState s = (WordBluffState) state;
        String firstTeam = s.turnTeam;

        state = module.onPhaseElapsed(state, "Turn"); // time runs out -> TurnEnd (score 0 < target)
        WordBluffState afterEnd = (WordBluffState) state;
        assertThat(afterEnd.phase()).isEqualTo("Review");

        state = module.onPhaseElapsed(state, "Review");
        WordBluffState next = (WordBluffState) state;
        assertThat(next.phase()).isEqualTo("Turn");
        assertThat(next.turnTeam).isNotEqualTo(firstTeam);
        assertThat(next.round()).isEqualTo(2);
    }

    @Test
    void reachingTargetScoreEndsGameImmediatelyAfterTurn() {
        WordBluffConfig lowTarget = new WordBluffConfig(10, 60);
        GameState state = module.initialState(players(4), lowTarget, RandomSource.seeded(5));
        WordBluffState s = (WordBluffState) state;
        String winningTeam = s.turnTeam;

        // one turn worth enough correct words to hit the target outright
        for (int i = 0; i < lowTarget.targetScore(); i++) {
            state = playWord(state, true);
        }
        state = endTurnAndCommit(state);

        assertThat(state.finished()).isTrue();
        Optional<WinResult> win = module.checkWinCondition(state);
        assertThat(win).isPresent();
        assertThat(win.get().winningSide()).isEqualTo(winningTeam);
        assertThat(module.visibleStateFor(state, s.currentDescriber()).data())
                .containsEntry("winningTeam", winningTeam);
    }

    @Test
    void noWordRepeatsWithinASession() {
        GameState state = module.initialState(players(4), new WordBluffConfig(200, 60), RandomSource.seeded(21));
        Set<String> seen = new java.util.HashSet<>();

        for (int i = 0; i < 150; i++) {
            WordBluffState s = (WordBluffState) state;
            if (s.finished()) break;
            String describer = s.currentDescriber();
            // One spin a turn; each resolve puts the next word up itself.
            if (s.currentCategory == null) {
                state = module.onPlayerAction(state, PlayerAction.of(describer, "SPIN", java.util.Map.of()));
            }
            WordBluffState revealed = (WordBluffState) state;
            String word = revealed.events.stream()
                    .filter(e -> e.type().equals("WORD_REVEALED"))
                    .reduce((a, b) -> b).orElseThrow().payload().get("word").toString();
            assertThat(seen).doesNotContain(word);
            seen.add(word);
            state = i % 2 == 0
                    ? module.onPlayerAction(state, PlayerAction.of(opponentOf(s), "MARK", java.util.Map.of("correct", true)))
                    : module.onPlayerAction(state, PlayerAction.of(describer, "SKIP", java.util.Map.of()));
        }
    }

    // ---- helpers for the review-scoring rules ----

    /** An opponent of whoever is describing — the only side allowed to mark. */
    private static String opponentOf(WordBluffState s) {
        String describer = s.currentDescriber();
        return s.teamA.contains(describer) ? s.teamB.get(0) : s.teamA.get(0);
    }

    /** Play one word to a mark. Nothing scores until the turn is committed. */
    private GameState playWord(GameState state, boolean correct) {
        WordBluffState s = (WordBluffState) state;
        String describer = s.currentDescriber();
        // The wheel is spun once a turn; after that, resolving a word puts
        // the next one from the same category straight up.
        if (s.currentCategory == null) {
            state = module.onPlayerAction(state, PlayerAction.of(describer, "SPIN", java.util.Map.of()));
        }
        return module.onPlayerAction(state,
                PlayerAction.of(opponentOf(s), "MARK", java.util.Map.of("correct", correct)));
    }

    /** End the turn and have both teams sign off, which is what banks the score. */
    private GameState endTurnAndCommit(GameState state) {
        WordBluffState s = (WordBluffState) state;
        state = module.onPhaseElapsed(state, "Turn");
        WordBluffState reviewing = (WordBluffState) state;
        GameState summary = module.onPlayerAction(
                module.onPlayerAction(state, PlayerAction.of(reviewing.teamA.get(0), "REVIEW_ACCEPT", java.util.Map.of())),
                PlayerAction.of(reviewing.teamB.get(0), "REVIEW_ACCEPT", java.util.Map.of()));
        assertThat(summary.phase()).isEqualTo("Summary");
        return module.onPhaseElapsed(summary, "Summary");
    }
}
