package app.truearena.api.slay;

import static org.assertj.core.api.Assertions.*;

import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.*;

class SlayCareerCatalogTest {
    @Test
    void starsUseTheCareerThresholds() {
        assertThat(
                        java.util.stream.DoubleStream.of(0, 49, 50, 64, 65, 79, 80, 89, 90, 100)
                                .mapToInt(SlayCareerCatalog::stars)
                                .toArray())
                .containsExactly(1, 1, 2, 2, 3, 3, 4, 4, 5, 5);
    }

    @Test
    void rankNeedsXpClearsStarsAndTheFinaleTogether() throws Exception {
        var career = new SlayCareerCatalog(new ObjectMapper());
        Map<String, Double> best = new HashMap<>();
        assertThat(career.rank(5000, best)).isZero();
        career.content().challenges().subList(0, 4).forEach(c -> best.put(c.id(), 100d));
        assertThat(career.rank(399, best)).isZero();
        assertThat(career.rank(400, best)).isEqualTo(1);
        best.put("studio-finale", 79d);
        assertThat(career.rank(5000, best)).isZero();
        best.put("studio-finale", 80d);
        for (String id : List.of("hello-style", "coffee-date", "weekend-edit")) best.put(id, 49d);
        assertThat(career.rank(5000, best)).isZero();
    }

    @Test
    void contentUsesExistingScenesAndBothBodiesCanClearEveryFinale() throws Exception {
        var mapper = new ObjectMapper();
        var career = new SlayCareerCatalog(mapper);
        var wardrobe = new SlayCatalog(mapper, "");
        assertThat(career.content().challenges()).hasSize(20);
        assertThat(career.content().ranks()).hasSize(6);
        for (var c : career.content().challenges()) {
            assertThat(wardrobe.manifest().backgrounds()).contains(c.location());
            assertThat(wardrobe.theme(c.themeId())).isNotNull();
            assertThat(career.theme(c).bodyEligibility()).containsExactly("female", "male");
            if (c.minimumScore() > 0)
                for (String body : List.of("female", "male")) {
                    double max =
                            wardrobe.items().values().stream()
                                    .filter(
                                            i ->
                                                    i.category().equals("outfit")
                                                            && i.body().equals(body)
                                                            && i.isDefault())
                                    .mapToDouble(
                                            i ->
                                                    app.truearena.engine.slay.SlayRules.score(
                                                                    new app.truearena.engine.slay
                                                                            .SlayRules.Look(
                                                                            body,
                                                                            "skin",
                                                                            "classic",
                                                                            Map.of(
                                                                                    "outfit",
                                                                                    i.id(), "shoes",
                                                                                    "shoe-0"),
                                                                            "signature",
                                                                            c.location()),
                                                                    career.theme(c),
                                                                    wardrobe.items())
                                                            .overall())
                                    .max()
                                    .orElse(0);
                    assertThat(max)
                            .as(c.id() + "/" + body)
                            .isGreaterThanOrEqualTo(c.minimumScore());
                }
        }
        var allBests = new HashMap<String, Double>();
        career.content().challenges().forEach(c -> allBests.put(c.id(), 100d));
        assertThat(career.rank(20 * 140, allBests))
                .as("Career alone can reach Global Star")
                .isEqualTo(5);
        var day = LocalDate.of(2026, 10, 10);
        assertThat(career.challenge("daily", day)).isEqualTo(career.challenge("daily", day));
        assertThat(career.challenge("daily", day.plusDays(1)))
                .isNotEqualTo(career.challenge("daily", day));
    }
}
