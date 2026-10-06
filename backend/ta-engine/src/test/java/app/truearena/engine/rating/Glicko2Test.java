package app.truearena.engine.rating;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The official rating has to be mathematically reproducible, so the engine is
 * pinned to the worked example in Glickman's own paper rather than to whatever
 * this implementation happens to produce.
 */
class Glicko2Test {

    @Test
    @DisplayName("reproduces the worked example from Glickman's Glicko-2 paper")
    void matchesPublishedReferenceValues() {
        RatingSnapshot player = new RatingSnapshot(1500, 200, 0.06);
        List<MatchOutcome> games = List.of(
                new MatchOutcome(new RatingSnapshot(1400, 30, 0.06), MatchOutcome.WIN),
                new MatchOutcome(new RatingSnapshot(1550, 100, 0.06), MatchOutcome.LOSS),
                new MatchOutcome(new RatingSnapshot(1700, 300, 0.06), MatchOutcome.LOSS));

        RatingSnapshot after = Glicko2.update(player, games);

        assertThat(after.rating()).isCloseTo(1464.06, org.assertj.core.data.Offset.offset(0.01));
        assertThat(after.deviation()).isCloseTo(151.52, org.assertj.core.data.Offset.offset(0.01));
        assertThat(after.volatility()).isCloseTo(0.05999, org.assertj.core.data.Offset.offset(0.00001));
    }

    @Test
    @DisplayName("beating a stronger opponent gains more than beating a weaker one")
    void opponentQualityDrivesTheGain() {
        RatingSnapshot me = new RatingSnapshot(1500, 80, 0.06);
        RatingSnapshot weak = new RatingSnapshot(1200, 80, 0.06);
        RatingSnapshot strong = new RatingSnapshot(1900, 80, 0.06);

        double vsWeak = Glicko2.update(me, List.of(new MatchOutcome(weak, MatchOutcome.WIN))).rating() - me.rating();
        double vsStrong = Glicko2.update(me, List.of(new MatchOutcome(strong, MatchOutcome.WIN))).rating() - me.rating();

        assertThat(vsWeak).isPositive();
        assertThat(vsStrong).isGreaterThan(vsWeak);
    }

    @Test
    @DisplayName("losing to a much weaker opponent costs more than losing to a stronger one")
    void losingToWeakerHurtsMore() {
        RatingSnapshot me = new RatingSnapshot(1500, 80, 0.06);
        RatingSnapshot weak = new RatingSnapshot(1200, 80, 0.06);
        RatingSnapshot strong = new RatingSnapshot(1900, 80, 0.06);

        double vsWeak = Glicko2.update(me, List.of(new MatchOutcome(weak, MatchOutcome.LOSS))).rating() - me.rating();
        double vsStrong = Glicko2.update(me, List.of(new MatchOutcome(strong, MatchOutcome.LOSS))).rating() - me.rating();

        assertThat(vsWeak).isNegative();
        assertThat(vsStrong).isNegative();
        assertThat(vsWeak).isLessThan(vsStrong); // more negative
    }

    @Test
    @DisplayName("a result against an uncertain opponent moves you less")
    void uncertainOpponentsCountForLess() {
        RatingSnapshot me = new RatingSnapshot(1500, 80, 0.06);
        RatingSnapshot established = new RatingSnapshot(1700, 40, 0.06);
        RatingSnapshot unknown = new RatingSnapshot(1700, 340, 0.06);

        double vsEstablished = Glicko2.update(me, List.of(new MatchOutcome(established, MatchOutcome.WIN))).rating();
        double vsUnknown = Glicko2.update(me, List.of(new MatchOutcome(unknown, MatchOutcome.WIN))).rating();

        assertThat(vsEstablished).isGreaterThan(vsUnknown);
    }

    @Test
    @DisplayName("a new account's uncertainty collapses quickly, so placement games mean something")
    void newAccountsConvergeFast() {
        RatingSnapshot state = RatingSnapshot.initial();
        assertThat(state.deviation()).isEqualTo(350.0);

        RatingSnapshot opponent = new RatingSnapshot(1500, 60, 0.06);
        for (int game = 0; game < 10; game++) {
            state = Glicko2.update(state, List.of(new MatchOutcome(opponent, MatchOutcome.WIN)));
        }

        // Roughly 350 → 140: the account is no longer an unknown quantity, which is
        // what the provisional threshold is waiting for. It doesn't collapse further
        // than that on a ten-game winning streak, because once the rating has run
        // well clear of the opponent each further win is an expected result and
        // therefore tells the system very little.
        assertThat(state.deviation()).isLessThan(150.0);
        assertThat(state.rating()).isGreaterThan(1700.0);
    }

    @Test
    @DisplayName("a draw between equals barely moves the rating but still sharpens it")
    void drawBetweenEquals() {
        RatingSnapshot me = new RatingSnapshot(1500, 120, 0.06);
        RatingSnapshot after = Glicko2.update(me, List.of(
                new MatchOutcome(new RatingSnapshot(1500, 120, 0.06), MatchOutcome.DRAW)));

        assertThat(after.rating()).isCloseTo(1500.0, org.assertj.core.data.Offset.offset(0.5));
        assertThat(after.deviation()).isLessThan(me.deviation());
    }

    @Test
    @DisplayName("not playing leaves the rating alone and widens the deviation, capped at the initial maximum")
    void inactivityOnlyWidensUncertainty() {
        RatingSnapshot me = new RatingSnapshot(1842, 60, 0.06);
        RatingSnapshot after = Glicko2.update(me, List.of());

        assertThat(after.rating()).isEqualTo(1842.0);
        assertThat(after.deviation()).isGreaterThan(60.0).isLessThanOrEqualTo(350.0);
    }

    @Test
    @DisplayName("a multi-player game is one rating update over every opponent")
    void multiPlayerExpandsPairwise() {
        Map<String, String> outcome = Map.of(
                "a", PairwiseOutcomes.WON,
                "b", PairwiseOutcomes.LOST,
                "c", PairwiseOutcomes.LOST,
                "d", PairwiseOutcomes.LOST);
        Map<String, RatingSnapshot> ratings = Map.of(
                "a", new RatingSnapshot(1500, 80, 0.06),
                "b", new RatingSnapshot(1500, 80, 0.06),
                "c", new RatingSnapshot(1500, 80, 0.06),
                "d", new RatingSnapshot(1500, 80, 0.06));

        Map<String, List<MatchOutcome>> expanded = PairwiseOutcomes.expand(outcome, ratings);
        assertThat(expanded.get("a")).hasSize(3);

        RatingSnapshot winner = Glicko2.update(ratings.get("a"), expanded.get("a"));
        RatingSnapshot loser = Glicko2.update(ratings.get("b"), expanded.get("b"));

        // Winning a four-player game beats three opponents at once, so it is worth
        // more than a single 1v1 win — and the losers, who each lost to one and
        // drew with two, drop by much less than they would in a 1v1.
        assertThat(winner.rating()).isGreaterThan(1500.0);
        assertThat(loser.rating()).isLessThan(1500.0);
        assertThat(winner.rating() - 1500.0).isGreaterThan(1500.0 - loser.rating());
    }
}
