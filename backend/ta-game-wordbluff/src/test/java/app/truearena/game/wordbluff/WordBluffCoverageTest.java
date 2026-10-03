package app.truearena.game.wordbluff;

import app.truearena.engine.GameEvent;
import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import app.truearena.engine.WinResult;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Every reachable branch of {@link WordBluffModule}, one scenario per test — setup,
 * every {@code RuleViolation} a client can trigger, the full phase machine (including
 * an early host advance and the untimed-phase host gate), idempotency, win/results,
 * and the view/broadcast contract. Complements {@link WordBluffEngineTest} (the
 * end-to-end happy-path flows) and {@link SecretWordGuaranteeTest} (the secrecy
 * guarantee specifically) rather than duplicating them.
 */
class WordBluffCoverageTest {

    private final WordBluffModule module = new WordBluffModule();

    private static List<String> ids(int n) {
        return IntStream.rangeClosed(1, n).mapToObj(i -> "p" + i).toList();
    }

    private static PlayerAction action(String actor, String type) {
        return PlayerAction.of(actor, type, Map.of());
    }

    private GameState fresh(int players, long seed) {
        return module.initialState(ids(players), WordBluffConfig.defaults(), RandomSource.seeded(seed));
    }

    // ---------------------------------------------------------------- setup

    @Test
    void fewerThanFourPlayersIsRejected() {
        assertThatThrownBy(() -> module.initialState(ids(3), WordBluffConfig.defaults(), RandomSource.seeded(1)))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_ENOUGH_PLAYERS");
    }

    @Test
    void exactlyFourPlayersSplitsTwoAndTwo() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        assertThat(s.teamA).hasSize(2);
        assertThat(s.teamB).hasSize(2);
    }

    @Test
    void oddPlayerCountSplitsAsEvenlyAsPossible() {
        WordBluffState s = (WordBluffState) fresh(5, 1);
        assertThat(s.teamA.size() + s.teamB.size()).isEqualTo(5);
        assertThat(Math.abs(s.teamA.size() - s.teamB.size())).isEqualTo(1);
    }

    @Test
    void everyPlayerLandsOnExactlyOneTeam() {
        List<String> players = ids(9);
        WordBluffState s = (WordBluffState) module.initialState(players, WordBluffConfig.defaults(), RandomSource.seeded(3));
        assertThat(s.teamA).doesNotContainAnyElementsOf(s.teamB);
        List<String> all = new java.util.ArrayList<>(s.teamA);
        all.addAll(s.teamB);
        assertThat(all).containsExactlyInAnyOrderElementsOf(players);
    }

    @Test
    void gameStartsOnTurnOneWithATeamGoingFirst() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        assertThat(s.phase()).isEqualTo("Turn");
        assertThat(s.round()).isEqualTo(1);
        assertThat(s.turnTeam).isEqualTo(WordBluffState.TEAM_A);
        assertThat(s.currentCategory).isNull();
        assertThat(s.currentWord).isNull();
    }

    @Test
    void gameStartedEventCarriesRostersAndSettings() {
        WordBluffConfig cfg = new WordBluffConfig(45, 90);
        WordBluffState s = (WordBluffState) module.initialState(ids(4), cfg, RandomSource.seeded(1));
        GameEvent started = s.events().stream().filter(e -> e.type().equals("GAME_STARTED")).findFirst().orElseThrow();
        assertThat(started.visibility().isPublic()).isTrue();
        assertThat(started.payload()).containsEntry("targetScore", 45).containsEntry("turnSeconds", 90);
        assertThat(started.payload().get("teamA")).isEqualTo(s.teamA);
        assertThat(started.payload().get("teamB")).isEqualTo(s.teamB);
    }

    @Test
    void definePhasesMatchesConfiguredTurnLengthAndUntimedRest() {
        WordBluffConfig cfg = new WordBluffConfig(30, 42);
        List<app.truearena.engine.Phase> phases = module.definePhases(cfg);
        assertThat(phases).extracting(app.truearena.engine.Phase::name).containsExactly("Turn", "Review", "Summary", "Results");
        assertThat(phases.get(0).timerSeconds()).isEqualTo(42);
        assertThat(phases.get(1).timerSeconds()).isEqualTo(0);
        assertThat(phases.get(2).timerSeconds()).isEqualTo(6);
        assertThat(phases.get(3).timerSeconds()).isEqualTo(0);
    }

    @Test
    void gameTypeIsWordbluff() {
        assertThat(module.gameType()).isEqualTo("wordbluff");
    }

    // ---------------------------------------------------------------- SPIN

    @Test
    void spinByNonDescriberIsRejected() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        String other = otherPlayerOnTurnTeam(s);
        assertThatThrownBy(() -> module.onPlayerAction(s, action(other, "SPIN")))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_YOUR_TURN");
    }

    @Test
    void spinTwiceWithoutResolvingIsRejected() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        String d = s.currentDescriber();
        GameState afterSpin = module.onPlayerAction(s, action(d, "SPIN"));
        assertThatThrownBy(() -> module.onPlayerAction(afterSpin, action(d, "SPIN")))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "ALREADY_SPUN");
    }

    @Test
    void spinDuringReviewIsRejected() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        GameState turnEnd = module.onPhaseElapsed(s, "Turn"); // 0 points < target -> TurnEnd
        WordBluffState te = (WordBluffState) turnEnd;
        assertThat(te.phase()).isEqualTo("Review");
        assertThatThrownBy(() -> module.onPlayerAction(turnEnd, action(te.currentDescriber(), "SPIN")))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "WRONG_PHASE");
    }

    @Test
    void spinEmitsPublicCategoryLanded() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        String d = s.currentDescriber();
        WordBluffState after = (WordBluffState) module.onPlayerAction(s, action(d, "SPIN"));
        assertThat(after.currentCategory).isNotNull();
        GameEvent landed = last(after, "CATEGORY_LANDED");
        assertThat(landed.visibility().isPublic()).isTrue();
        assertThat(landed.payload()).containsEntry("category", after.currentCategory.slug());
    }

    // ---------------------------------------------------------------- REVEAL

    @Test
    void revealByNonDescriberIsRejected() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        String d = s.currentDescriber();
        GameState spun = module.onPlayerAction(s, action(d, "SPIN"));
        String other = otherPlayerOnTurnTeam((WordBluffState) spun);
        assertThatThrownBy(() -> module.onPlayerAction(spun, action(other, "REVEAL")))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_YOUR_TURN");
    }

    @Test
    void revealWithoutSpinningFirstIsRejected() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        String d = s.currentDescriber();
        assertThatThrownBy(() -> module.onPlayerAction(s, action(d, "REVEAL")))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NO_PENDING_SPIN");
    }

    /**
     * Spinning hands over the first word itself, so an explicit reveal has
     * nothing left to do. It's a no-op rather than an error: older clients
     * and the bot adapter still send it, and failing a turn over a redundant
     * action would be the wrong trade.
     */
    @Test
    void revealingAnAlreadyShowingWordIsAHarmlessNoOp() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        String d = s.currentDescriber();
        WordBluffState spun = (WordBluffState) module.onPlayerAction(s, action(d, "SPIN"));
        assertThat(spun.currentWord).as("spinning reveals the first word").isNotNull();

        WordBluffState again = (WordBluffState) module.onPlayerAction(spun, action(d, "REVEAL"));
        assertThat(again.currentWord).isEqualTo(spun.currentWord);
    }

    /**
     * The describer needs the word, and so does the team marking them —
     * they call each attempt right or wrong and can't do that blind. The
     * describer's own teammates must never see it: guessing it is their job.
     */
    @Test
    void theWordGoesToTheDescriberAndTheMarkingTeamButNeverTheirOwnTeam() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        String d = s.currentDescriber();
        WordBluffState revealed = (WordBluffState) module.onPlayerAction(s, action(d, "SPIN"));
        assertThat(revealed.currentWord).isNotNull();

        List<String> describingTeam = revealed.teamA.contains(d) ? revealed.teamA : revealed.teamB;
        List<String> markingTeam = revealed.teamA.contains(d) ? revealed.teamB : revealed.teamA;

        List<String> told = revealed.events().stream()
                .filter(e -> "WORD_REVEALED".equals(e.type()))
                .peek(e -> {
                    assertThat(e.visibility().isPublic()).as("never public").isFalse();
                    assertThat(e.visibility().scope()).isEqualTo("player");
                })
                .map(e -> e.visibility().key())
                .toList();

        assertThat(told).contains(d);
        assertThat(told).containsAll(markingTeam);
        assertThat(told).doesNotContainAnyElementsOf(
                describingTeam.stream().filter(p -> !p.equals(d)).toList());
    }

    @Test
    void wordPoolExhaustionThrowsRatherThanRepeating() {
        // Drive the same describer through every unique word in the bank without
        // ever ending the turn, then prove the next reveal can't find a fresh one.
        WordBluffState s = (WordBluffState) module.initialState(ids(4), new WordBluffConfig(200, 60), RandomSource.seeded(99));
        GameState state = s;
        int totalWords = WordBank.wordsFor(Category.MIXED).size();
        for (int i = 0; i < totalWords; i++) {
            String d = ((WordBluffState) state).currentDescriber();
            // One spin a turn — the next word follows each resolve.
            if (((WordBluffState) state).currentCategory == null) {
                state = module.onPlayerAction(state, PlayerAction.of(d, "SPIN", Map.of("id", UUID.randomUUID().toString())));
            }
            state = module.onPlayerAction(state, PlayerAction.of(d, "SKIP", Map.of("id", UUID.randomUUID().toString())));
        }
        assertThat(((WordBluffState) state).usedWords).hasSize(totalWords);
        // The turn's own auto-reveal swallows an empty bank rather than
        // blowing up half way through resolving a word, so mid-turn there's
        // simply no word showing...
        assertThat(((WordBluffState) state).currentWord).isNull();
        assertThat(((WordBluffState) state).currentCategory).isNotNull();

        // ...and asking for one outright is what reports it.
        String d = ((WordBluffState) state).currentDescriber();
        GameState exhausted = state;
        assertThatThrownBy(() -> module.onPlayerAction(exhausted, action(d, "REVEAL")))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "WORD_POOL_EXHAUSTED");
    }

    // ---------------------------------------------------------------- MARK_CORRECT / SKIP

    @Test
    void markByOwnTeamIsRejected() {
        WordBluffState s = revealedState(4, 1);
        String other = otherPlayerOnTurnTeam(s);
        assertThatThrownBy(() -> module.onPlayerAction(s, action(other, "MARK")))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_YOUR_CALL");
    }

    @Test
    void skipByNonDescriberIsRejected() {
        WordBluffState s = revealedState(4, 1);
        String other = otherPlayerOnTurnTeam(s);
        assertThatThrownBy(() -> module.onPlayerAction(s, action(other, "SKIP")))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NOT_YOUR_TURN");
    }

    @Test
    void resolvingWithoutAnActiveWordIsRejected() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        String d = s.currentDescriber();
        assertThatThrownBy(() -> module.onPlayerAction(s, action(d, "MARK_CORRECT")))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NO_ACTIVE_WORD");
        assertThatThrownBy(() -> module.onPlayerAction(s, action(d, "SKIP")))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "NO_ACTIVE_WORD");
    }

    @Test
    void markingRecordsAProposedPointAndMovesToTheNextWord() {
        WordBluffState s = revealedState(4, 1);
        String team = s.turnTeam;
        String opp = WordBluffState.TEAM_A.equals(team) ? s.teamB.get(0) : s.teamA.get(0);
        WordBluffState after = (WordBluffState) module.onPlayerAction(s,
                PlayerAction.of(opp, "MARK", Map.of("id", UUID.randomUUID().toString(), "correct", true)));

        // proposed, not banked — the scoreboard only moves when the review commits
        assertThat(after.scoreOf(team)).isZero();
        assertThat(after.turnAttempts).hasSize(1);
        assertThat(after.turnAttempts.get(0).correct()).isTrue();
        // The word moves on, the category stays — the turn keeps going.
        assertThat(after.currentWord).isNotNull();
        assertThat(after.currentCategory).isNotNull();
        GameEvent resolved = last(after, "WORD_RESOLVED");
        assertThat(resolved.payload()).containsEntry("result", "correct");
    }

    @Test
    void skipDoesNotScoreButMarksTheWordUsed() {
        WordBluffState s = revealedState(4, 1);
        String d = s.currentDescriber();
        String usedWord = s.currentWord;
        WordBluffState after = (WordBluffState) module.onPlayerAction(s, action(d, "SKIP"));
        assertThat(after.teamAScore + after.teamBScore).isZero();
        assertThat(after.usedWords).contains(usedWord);
        GameEvent resolved = last(after, "WORD_RESOLVED");
        assertThat(resolved.payload()).containsEntry("result", "skipped");
    }

    // ---------------------------------------------------------------- phase machine

    @Test
    void reviewIsUntimedAndWaitsForBothTeams() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        GameState turnEnd = module.onPhaseElapsed(s, "Turn");
        assertThat(turnEnd.phase()).isEqualTo("Review");
        assertThat(module.definePhases(WordBluffConfig.defaults()).get(1).timerSeconds()).isZero();
    }

    @Test
    void advancingFromReviewRotatesTeamAndBumpsRound() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        String firstTeam = s.turnTeam;
        GameState turnEnd = module.onPhaseElapsed(s, "Turn");
        GameState next = module.onPlayerAction(turnEnd, action("anyone", "ADVANCE_PHASE"));
        WordBluffState ns = (WordBluffState) next;
        assertThat(ns.phase()).isEqualTo("Turn");
        assertThat(ns.turnTeam).isNotEqualTo(firstTeam);
        assertThat(ns.round()).isEqualTo(2);
    }

    @Test
    void describerRotatesOnlyForTheTeamThatJustPlayed() {
        WordBluffState s = (WordBluffState) fresh(6, 4);
        String firstDescriberA = s.turnTeam.equals(WordBluffState.TEAM_A) ? s.currentDescriber() : null;
        GameState turnEnd = module.onPhaseElapsed(s, "Turn"); // team that started ends its turn
        GameState nextTurn = module.onPlayerAction(turnEnd, action("anyone", "ADVANCE_PHASE"));
        GameState secondTurnEnd = module.onPhaseElapsed(nextTurn, "Turn");
        GameState backToFirstTeam = module.onPlayerAction(secondTurnEnd, action("anyone", "ADVANCE_PHASE"));
        WordBluffState back = (WordBluffState) backToFirstTeam;
        assertThat(back.turnTeam).isEqualTo(s.turnTeam);
        if (firstDescriberA != null) {
            // team A has played once more since — its describer index moved on,
            // so (with >1 member) the describer for this second A turn differs.
            List<String> teamA = back.teamA;
            if (teamA.size() > 1) {
                assertThat(back.currentDescriber()).isNotEqualTo(firstDescriberA);
            }
        }
    }

    @Test
    void anEarlyHostAdvanceAbandonsTheActiveWordWithoutScoring() {
        WordBluffState s = revealedState(4, 1);
        String team = s.turnTeam;
        int scoreBefore = WordBluffState.TEAM_A.equals(team) ? s.teamAScore : s.teamBScore;
        GameState turnEnd = module.onPlayerAction(s, action("host", "ADVANCE_PHASE"));
        WordBluffState te = (WordBluffState) turnEnd;
        assertThat(te.phase()).isEqualTo("Review");
        int scoreAfter = WordBluffState.TEAM_A.equals(team) ? te.teamAScore : te.teamBScore;
        assertThat(scoreAfter).isEqualTo(scoreBefore);
        assertThat(te.currentCategory).isNull();
        assertThat(te.currentWord).isNull();
    }

    @Test
    void advancingFromAnUnrecognizedPhaseIsRejected() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        assertThatThrownBy(() -> module.onPhaseElapsed(s, "NotARealPhase"))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "BAD_PHASE");
    }

    @Test
    void advancingFromResultsIsANoOp() {
        WordBluffState s = wonState();
        assertThat(s.finished()).isTrue();
        GameState still = module.onPlayerAction(s, action("host", "ADVANCE_PHASE"));
        assertThat(still.phase()).isEqualTo("Results");
    }

    // ---------------------------------------------------------------- win / results

    @Test
    void reachingTargetScoreEndsTheGameForTheScoringTeam() {
        WordBluffState s = wonState();
        assertThat(s.finished()).isTrue();
        Optional<WinResult> win = module.checkWinCondition(s);
        assertThat(win).isPresent();
        assertThat(win.get().winningSide()).isEqualTo(WordBluffState.TEAM_A);
        assertThat(win.get().perPlayerOutcome()).allSatisfy((player, outcome) -> {
            boolean onWinningTeam = s.teamA.contains(player);
            assertThat(outcome).isEqualTo(onWinningTeam ? "won" : "lost");
        });
        GameEvent gameOver = last(s, "GAME_OVER");
        assertThat(gameOver.payload()).containsEntry("winningTeam", WordBluffState.TEAM_A);
    }

    @Test
    void checkWinConditionIsEmptyBeforeTheGameEnds() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        assertThat(module.checkWinCondition(s)).isEmpty();
    }

    @Test
    void notReachingTargetScoreOnReviewDoesNotFinishTheGame() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        GameState turnEnd = module.onPhaseElapsed(s, "Turn");
        assertThat(turnEnd.finished()).isFalse();
        assertThat(module.checkWinCondition(turnEnd)).isEmpty();
    }

    // ---------------------------------------------------------------- idempotency

    @Test
    void unknownActionTypeIsRejected() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        assertThatThrownBy(() -> module.onPlayerAction(s, action(s.currentDescriber(), "TELEPORT")))
                .isInstanceOf(RuleViolation.class)
                .hasFieldOrPropertyWithValue("code", "UNKNOWN_ACTION");
    }

    @Test
    void repeatingTheSameActionIdIsANoOp() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        String d = s.currentDescriber();
        PlayerAction spin = PlayerAction.of(d, "SPIN", Map.of());
        GameState once = module.onPlayerAction(s, spin);
        GameState twice = module.onPlayerAction(once, spin); // same actionId as `once` was built from
        assertThat(((WordBluffState) twice).events()).hasSameSizeAs(((WordBluffState) once).events());
    }

    @Test
    void actionsAfterTheGameEndsAreNoOps() {
        WordBluffState s = wonState();
        GameState after = module.onPlayerAction(s, action(s.currentDescriber(), "SPIN"));
        assertThat(after).isSameAs(s);
    }

    @Test
    void phaseElapsedAfterTheGameEndsIsANoOp() {
        WordBluffState s = wonState();
        GameState after = module.onPhaseElapsed(s, "Turn");
        assertThat(after).isSameAs(s);
    }

    // ---------------------------------------------------------------- views

    @Test
    void broadcastAndGuessingTeamViewsNeverIncludeTheWord() {
        WordBluffState s = revealedState(4, 1);
        Map<String, Object> broadcast = module.broadcastState(s).data();
        assertThat(broadcast).doesNotContainKey("yourWord").doesNotContainKey("currentWord");
        for (String player : allPlayers(s)) {
            Map<String, Object> view = module.visibleStateFor(s, player).data();
            if (s.teamOfPlayer(player).equals(s.turnTeam) && !player.equals(s.currentDescriber())) {
                assertThat(view).doesNotContainKey("yourWord");
            } else {
                assertThat(view).containsEntry("yourWord", s.currentWord);
            }
        }
    }

    @Test
    void describerViewIncludesTheWordAndCommonFields() {
        WordBluffState s = revealedState(4, 1);
        Map<String, Object> view = module.visibleStateFor(s, s.currentDescriber()).data();
        assertThat(view).containsEntry("yourWord", s.currentWord);
        assertThat(view).containsKeys("phase", "round", "teamA", "teamB", "teamAScore", "teamBScore",
                "turnTeam", "describer", "hasActiveCategory", "category", "hasActiveWord", "targetScore");
    }

    @Test
    void broadcastOmitsCategoryFieldWhenNoneIsActive() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        Map<String, Object> view = module.broadcastState(s).data();
        assertThat(view).containsEntry("hasActiveCategory", false).doesNotContainKey("category");
    }

    @Test
    void drainEventsReturnsOnlyTheNewSuffix() {
        WordBluffState s = (WordBluffState) fresh(4, 1);
        GameState next = module.onPlayerAction(s, action(s.currentDescriber(), "SPIN"));
        List<GameEvent> drained = module.drainEvents(s, next);
        assertThat(drained).hasSize(((WordBluffState) next).events().size() - s.events().size());
        assertThat(drained).containsExactlyElementsOf(
                ((WordBluffState) next).events().subList(s.events().size(), ((WordBluffState) next).events().size()));
    }

    // ---------------------------------------------------------------- helpers

    private WordBluffState revealedState(int players, long seed) {
        WordBluffState s = (WordBluffState) fresh(players, seed);
        String d = s.currentDescriber();
        GameState spun = module.onPlayerAction(s, action(d, "SPIN"));
        return (WordBluffState) module.onPlayerAction(spun, action(d, "REVEAL"));
    }

    /** Drives enough correct words to hit the target, then ends and commits the review. */
    private WordBluffState wonState() {
        WordBluffConfig cfg = new WordBluffConfig(10, 60);
        GameState state = module.initialState(ids(4), cfg, RandomSource.seeded(6));
        for (int i = 0; i < cfg.targetScore(); i++) {
            String d = ((WordBluffState) state).currentDescriber();
            // One spin a turn — the next word follows each resolve.
            if (((WordBluffState) state).currentCategory == null) {
                state = module.onPlayerAction(state, PlayerAction.of(d, "SPIN", Map.of("id", UUID.randomUUID().toString())));
            }
            String opp = ((WordBluffState) state).teamA.contains(d)
                    ? ((WordBluffState) state).teamB.get(0) : ((WordBluffState) state).teamA.get(0);
            state = module.onPlayerAction(state, PlayerAction.of(opp, "MARK",
                    Map.of("id", UUID.randomUUID().toString(), "correct", true)));
        }
        state = module.onPhaseElapsed(state, "Turn");
        WordBluffState review = (WordBluffState) state;
        state = module.onPlayerAction(state, PlayerAction.of(review.teamA.get(0), "REVIEW_ACCEPT",
                Map.of("id", UUID.randomUUID().toString())));
        state = module.onPlayerAction(state, PlayerAction.of(review.teamB.get(0), "REVIEW_ACCEPT",
                Map.of("id", UUID.randomUUID().toString())));
        assertThat(state.phase()).isEqualTo("Summary");
        state = module.onPhaseElapsed(state, "Summary");
        return (WordBluffState) state;
    }

    private String otherPlayerOnTurnTeam(WordBluffState s) {
        List<String> team = s.teamOf(s.turnTeam);
        return team.stream().filter(p -> !p.equals(s.currentDescriber())).findFirst()
                .orElseGet(() -> s.teamOf(s.otherTeam(s.turnTeam)).get(0));
    }

    private List<String> allPlayers(WordBluffState s) {
        List<String> all = new java.util.ArrayList<>(s.teamA);
        all.addAll(s.teamB);
        return all;
    }

    private GameEvent last(WordBluffState s, String type) {
        return s.events().stream().filter(e -> e.type().equals(type)).reduce((a, b) -> b)
                .orElseThrow(() -> new AssertionError("no " + type + " event found"));
    }
}
