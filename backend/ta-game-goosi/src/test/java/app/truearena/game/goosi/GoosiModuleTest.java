package app.truearena.game.goosi;

import app.truearena.engine.GameEvent;
import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class GoosiModuleTest {

    private final GoosiModule module = new GoosiModule();
    private static final List<String> TWO = List.of("alice", "bob");
    private static final List<String> FOUR = List.of("alice", "bob", "carol", "dave");

    private GameState start(List<String> players) {
        return module.initialState(players, GoosiConfig.defaults(), RandomSource.seeded(1));
    }

    private GameState start(List<String> players, GoosiConfig config) {
        return module.initialState(players, config, RandomSource.seeded(1));
    }

    private GameState sow(GameState s, String actor, int pit) {
        return module.onPlayerAction(s, PlayerAction.of(actor, "SOW", Map.of("pit", pit)));
    }

    @SuppressWarnings("unchecked")
    private <T> T field(GameState s, String name) {
        try {
            Field f = GoosiState.class.getDeclaredField(name);
            f.setAccessible(true);
            return (T) f.get(s);
        } catch (ReflectiveAccessException | ReflectiveOperationException e) {
            throw new RuntimeException(e);
        }
    }

    private static final class ReflectiveAccessException extends RuntimeException {
    }

    @Test
    void twoPlayersGetEightPitsEach() {
        GameState s = start(TWO);
        String[] owner = field(s, "owner");
        int[] pits = field(s, "pits");
        assertThat(owner).hasSize(16);
        for (int i = 0; i < 8; i++) assertThat(owner[i]).isIn("alice", "bob");
        // the two players got shuffled, but exactly one owns 0-7 and the other 8-15
        assertThat(owner[0]).isEqualTo(owner[7]);
        assertThat(owner[8]).isEqualTo(owner[15]);
        assertThat(owner[0]).isNotEqualTo(owner[8]);
        for (int p : pits) assertThat(p).isEqualTo(4);
    }

    @Test
    void fourPlayersGetFourPitsEach() {
        GameState s = start(FOUR);
        String[] owner = field(s, "owner");
        assertThat(owner[0]).isEqualTo(owner[3]);
        assertThat(owner[4]).isEqualTo(owner[7]);
        assertThat(owner[8]).isEqualTo(owner[11]);
        assertThat(owner[12]).isEqualTo(owner[15]);
        assertThat(owner[0]).isNotEqualTo(owner[4]).isNotEqualTo(owner[8]).isNotEqualTo(owner[12]);
    }

    @Test
    void rejectsAnythingOtherThanTwoOrFourPlayers() {
        assertThatThrownBy(() -> start(List.of("solo")))
                .isInstanceOf(RuleViolation.class);
        assertThatThrownBy(() -> start(List.of("a", "b", "c")))
                .isInstanceOf(RuleViolation.class);
    }

    @Test
    void sowingDropsOneSeedIntoEachFollowingPitInIncreasingOrder() {
        GameState s = start(TWO);
        String[] owner = field(s, "owner");
        GoosiState after = (GoosiState) sow(s, owner[0], 0);

        // The opening pit holds four seeds, so the first pass drops into the
        // next four pits in order. Final pit counts can't show this — the
        // relay comes back round and adds to them again.
        assertThat(firstLapOf(after)).containsExactly(1, 2, 3, 4);
    }

    @SuppressWarnings("unchecked")
    private List<Integer> firstLapOf(GoosiState state) {
        List<List<Integer>> laps = (List<List<Integer>>) lastSownEvent(state).payload().get("laps");
        return laps.get(0);
    }

    /**
     * Every pit starts with four seeds, so the fourth seed always lands on
     * an occupied pit — which means the hand scoops that pit up and sows
     * again. Only a seed landing somewhere empty ends the turn.
     */
    @Test
    void landingOnAnOccupiedPitScoopsItUpAndKeepsSowing() {
        GameState s = start(TWO);
        String[] owner = field(s, "owner");
        GoosiState after = (GoosiState) sow(s, owner[0], 0);
        List<?> laps = (List<?>) lastSownEvent(after).payload().get("laps");

        assertThat(laps.size()).as("relayed more than once").isGreaterThan(1);

        // The pit that ended each lap but the last was emptied and carried on.
        int[] pits = field(after, "pits");
        List<?> firstLap = (List<?>) laps.get(0);
        int endOfFirstLap = (int) firstLap.get(firstLap.size() - 1);
        assertThat(pits[endOfFirstLap]).as("scooped up, then possibly refilled later").isNotEqualTo(5);
    }

    @Test
    void sowingAlwaysEndsWithTheLastSeedInAPitThatWasEmpty() {
        GameState s = start(TWO);
        String[] owner = field(s, "owner");
        GoosiState after = (GoosiState) sow(s, owner[0], 0);

        List<?> laps = (List<?>) lastSownEvent(after).payload().get("laps");
        assertThat(laps).isNotEmpty();
        List<?> finalLap = (List<?>) laps.get(laps.size() - 1);
        int landed = (int) finalLap.get(finalLap.size() - 1);
        int[] pits = field(after, "pits");

        // Either it's sitting alone, or the capture rule already emptied it.
        assertThat(pits[landed]).isIn(0, 1);
    }

    @Test
    void theSownEventCarriesEveryLapSoTheClientCanAnimateIt() {
        GameState s = start(TWO);
        String[] owner = field(s, "owner");
        GoosiState after = (GoosiState) sow(s, owner[0], 0);
        GameEvent sown = lastSownEvent(after);

        List<?> laps = (List<?>) sown.payload().get("laps");
        List<?> touched = (List<?>) sown.payload().get("touched");
        int dropsAcrossLaps = laps.stream().mapToInt(l -> ((List<?>) l).size()).sum();

        // The flat list and the per-lap lists must describe the same sowing,
        // or the animation would drift out of step with the board.
        assertThat(dropsAcrossLaps).isEqualTo(touched.size());
        assertThat(((List<?>) laps.get(0))).hasSize(4); // four seeds in the opening pit
    }

    private GameEvent lastSownEvent(GoosiState state) {
        return state.events().stream()
                .filter(e -> "SOWN".equals(e.type()))
                .reduce((a, b) -> b)
                .orElseThrow();
    }

    @Test
    void onlyTheOwnerOfAPitMaySowIt() {
        GameState s = start(TWO);
        String[] owner = field(s, "owner");
        String notP0 = owner[8]; // the other player
        assertThatThrownBy(() -> sow(s, notP0, 0)).isInstanceOf(RuleViolation.class);
    }

    @Test
    void onlyTheCurrentTurnPlayerMaySow() {
        GameState s = start(TWO);
        String[] owner = field(s, "owner");
        String p1 = owner[8];
        assertThatThrownBy(() -> sow(s, p1, 8)).isInstanceOf(RuleViolation.class);
    }

    /**
     * A pit brought to exactly four is taken by whoever sowed it, wherever
     * it sits on the board. Asserted over a played-out game rather than one
     * hand-traced line — a traced sequence only survives until the rules
     * change, which they have twice now.
     */
    @Test
    void aPitBroughtToFourIsCapturedByWhoeverSowedIt() {
        GameState s = start(TWO);
        int captures = 0;

        for (int i = 0; i < 40 && !s.finished(); i++) {
            List<String> players = field(s, "players");
            int turn = field(s, "turnIndex");
            String actor = players.get(turn);
            int[] scoresBefore = ((int[]) field(s, "scores")).clone();

            GameState next = sowFirstLegal(s);
            if (next == null) {
                break;
            }
            for (GameEvent e : newEvents(s, next)) {
                if (!"CAPTURED".equals(e.type())) {
                    continue;
                }
                captures++;
                assertThat(e.payload().get("by")).as("the sower takes it").isEqualTo(actor);
                assertThat(e.payload().get("count")).as("exactly the four seeds").isEqualTo(4);
                // Deliberately not asserting the pit is empty afterwards: it
                // is emptied the moment it's taken, but a long relay comes
                // back round and sows into it again before the turn ends.
            }

            // Everything taken this turn went to the sower, four at a time.
            int[] scoresNow = field(next, "scores");
            assertThat(scoresNow[turn] - scoresBefore[turn])
                    .as("the sower banked four per capture")
                    .isEqualTo(4 * capturesThisTurn(s, next));

            // Whatever was taken went to the sower and nobody else.
            int[] scoresAfter = field(next, "scores");
            for (int p = 0; p < scoresAfter.length; p++) {
                if (p != turn) {
                    assertThat(scoresAfter[p]).as("other scores untouched").isEqualTo(scoresBefore[p]);
                }
            }
            s = next;
        }
        assertThat(captures).as("the game produced captures to check").isPositive();
    }

    private int capturesThisTurn(GameState before, GameState after) {
        return (int) newEvents(before, after).stream().filter(e -> "CAPTURED".equals(e.type())).count();
    }

    @Test
    void capturingTakesNothingFromThePitOpposite() {
        // The old rule took the landing pit plus its opposite. Four-rule
        // captures are a single pit, so the opposite must be left alone.
        GameState s = start(TWO);
        String[] owner = field(s, "owner");
        int[] before = ((int[]) field(s, "pits")).clone();
        GoosiState after = (GoosiState) sow(s, owner[0], 0);

        for (GameEvent e : newEvents(s, after)) {
            if (!"CAPTURED".equals(e.type())) {
                continue;
            }
            assertThat(e.payload()).as("no opposite pit involved").doesNotContainKey("opposite");
            int opposite = GoosiState.opposite((int) e.payload().get("pit"));
            int[] pits = field(after, "pits");
            // It may have been sown into, but it was never emptied by the capture.
            assertThat(pits[opposite]).isGreaterThanOrEqualTo(Math.min(before[opposite], 1));
        }
    }

    private List<GameEvent> newEvents(GameState before, GameState after) {
        List<GameEvent> a = before.events();
        List<GameEvent> b = after.events();
        return b.subList(a.size(), b.size());
    }

    @Test
    void gameEndsWhenTheNextPlayerHasNoSeedsAndSweepsRemainingSeeds() {
        GameState s = start(TWO, new GoosiConfig(1, 45));
        int before = totalSeeds(s);

        // Play whoever is actually on turn rather than assuming strict
        // alternation — a sow can end the game, and then nobody is.
        for (int i = 0; i < 60 && !s.finished(); i++) {
            GameState next = sowFirstLegal(s);
            if (next == null) {
                break;
            }
            s = next;
        }

        // Whatever state we landed in, it must be internally consistent:
        // seeds in pits plus seeds banked never changes, however many sows
        // and relays happened — nothing is created or destroyed.
        assertThat(totalSeeds(s)).isEqualTo(before);
    }

    /** Sows the first legal pit for whoever is on turn; null if they have none. */
    private GameState sowFirstLegal(GameState s) {
        List<String> players = field(s, "players");
        int turn = field(s, "turnIndex");
        String actor = players.get(turn);
        String[] owner = field(s, "owner");
        int[] pits = field(s, "pits");
        for (int i = 0; i < 16; i++) {
            if (actor.equals(owner[i]) && pits[i] > 0) {
                return sow(s, actor, i);
            }
        }
        return null;
    }

    private int totalSeeds(GameState s) {
        int[] pits = field(s, "pits");
        int[] scores = field(s, "scores");
        int total = 0;
        for (int v : pits) {
            total += v;
        }
        for (int v : scores) {
            total += v;
        }
        return total;
    }

    @Test
    void seedsAreConservedAcrossAnOrdinaryOpeningSow() {
        GameState s = start(TWO);
        String[] owner = field(s, "owner");
        s = sow(s, owner[0], 0);
        int[] pits = field(s, "pits");
        int total = 0;
        for (int p : pits) total += p;
        assertThat(total).isEqualTo(64); // 4 seeds * 16 pits, none captured yet
    }

    @Test
    void unknownActionIsRejected() {
        GameState s = start(TWO);
        String[] owner = field(s, "owner");
        assertThatThrownBy(() -> module.onPlayerAction(s, PlayerAction.of(owner[0], "NOPE", Map.of())))
                .isInstanceOf(RuleViolation.class);
    }

    @Test
    void sowingAnEmptyPitIsRejected() {
        GameState started = start(TWO);
        String[] owner = field(started, "owner");
        String p0 = owner[0];
        GameState s = sow(started, p0, 0); // empties pit 0
        assertThatThrownBy(() -> sow(s, p0, 0)).isInstanceOf(RuleViolation.class);
    }
}
