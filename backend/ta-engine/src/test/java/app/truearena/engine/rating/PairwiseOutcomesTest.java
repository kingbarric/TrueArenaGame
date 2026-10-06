package app.truearena.engine.rating;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class PairwiseOutcomesTest {

    private static final RatingSnapshot ANY = new RatingSnapshot(1500, 100, 0.06);

    @Test
    @DisplayName("a 1v1 gives each player exactly one opponent, scored opposite ways")
    void headToHead() {
        Map<String, List<MatchOutcome>> expanded = PairwiseOutcomes.expand(
                Map.of("a", PairwiseOutcomes.WON, "b", PairwiseOutcomes.LOST),
                Map.of("a", ANY, "b", ANY));

        assertThat(expanded.get("a")).singleElement()
                .extracting(MatchOutcome::score).isEqualTo(MatchOutcome.WIN);
        assertThat(expanded.get("b")).singleElement()
                .extracting(MatchOutcome::score).isEqualTo(MatchOutcome.LOSS);
    }

    @Test
    @DisplayName("an agreed draw scores 0.5 for both sides")
    void mutualDraw() {
        Map<String, List<MatchOutcome>> expanded = PairwiseOutcomes.expand(
                Map.of("a", PairwiseOutcomes.TIED, "b", PairwiseOutcomes.TIED),
                Map.of("a", ANY, "b", ANY));

        assertThat(expanded.get("a").getFirst().score()).isEqualTo(MatchOutcome.DRAW);
        assertThat(expanded.get("b").getFirst().score()).isEqualTo(MatchOutcome.DRAW);
    }

    @Test
    @DisplayName("a joint win over a third player beats them both and draws with each other")
    void sharedWinAgainstALoser() {
        Map<String, String> outcome = new LinkedHashMap<>();
        outcome.put("a", PairwiseOutcomes.TIED);
        outcome.put("b", PairwiseOutcomes.TIED);
        outcome.put("c", PairwiseOutcomes.LOST);

        Map<String, List<MatchOutcome>> expanded = PairwiseOutcomes.expand(outcome,
                Map.of("a", ANY, "b", ANY, "c", ANY));

        assertThat(expanded.get("a")).extracting(MatchOutcome::score)
                .containsExactly(MatchOutcome.DRAW, MatchOutcome.WIN);
        assertThat(expanded.get("c")).extracting(MatchOutcome::score)
                .containsExactly(MatchOutcome.LOSS, MatchOutcome.LOSS);
    }

    @Test
    @DisplayName("players with no rating state are invisible to the maths, not scored as losses")
    void unratedParticipantsAreSkipped() {
        Map<String, String> outcome = new LinkedHashMap<>();
        outcome.put("human", PairwiseOutcomes.WON);
        outcome.put("agent", PairwiseOutcomes.LOST);

        Map<String, List<MatchOutcome>> expanded = PairwiseOutcomes.expand(outcome, Map.of("human", ANY));

        assertThat(expanded).containsOnlyKeys("human");
        assertThat(expanded.get("human")).isEmpty();
    }

    @Test
    @DisplayName("an outcome label the rating engine doesn't know ranks below a win, never throws")
    void unknownOutcomeLabelDegradesSafely() {
        Map<String, List<MatchOutcome>> expanded = PairwiseOutcomes.expand(
                Map.of("a", PairwiseOutcomes.WON, "b", "eliminated"),
                Map.of("a", ANY, "b", ANY));

        assertThat(expanded.get("a").getFirst().score()).isEqualTo(MatchOutcome.WIN);
        assertThat(expanded.get("b").getFirst().score()).isEqualTo(MatchOutcome.LOSS);
    }
}
