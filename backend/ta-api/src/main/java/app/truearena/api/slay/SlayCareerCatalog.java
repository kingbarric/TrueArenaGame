package app.truearena.api.slay;

import app.truearena.engine.slay.SlayRules.Theme;

import com.fasterxml.jackson.databind.ObjectMapper;

import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.*;

/** Handcrafted career content and pure progression rules. PvP ratings stay separate. */
@Component
public class SlayCareerCatalog {
    public record Challenge(
            String id,
            String title,
            String brief,
            int chapter,
            String chapterTitle,
            String location,
            String themeId,
            List<String> styleTags,
            List<String> requiredCategories,
            String bonus,
            int minimumScore) {}

    public record Rank(
            String name, int minimumXp, int minimumCompleted, int minimumStars, String milestone) {}

    public record Content(List<Challenge> challenges, List<Rank> ranks) {}

    private final Content content;

    public SlayCareerCatalog(ObjectMapper mapper) throws Exception {
        try (var in = new ClassPathResource("slay/career.json").getInputStream()) {
            content = mapper.readValue(in, Content.class);
        }
    }

    public Content content() {
        return content;
    }

    public Challenge challenge(String id, LocalDate day) {
        if (id.equals("daily"))
            return content.challenges()
                    .get(Math.floorMod(day.toEpochDay(), content.challenges().size()));
        return content.challenges().stream()
                .filter(c -> c.id().equals(id))
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException("Unknown career event"));
    }

    public Theme theme(Challenge c) {
        return new Theme(
                c.id(),
                c.title(),
                c.brief(),
                c.styleTags(),
                c.requiredCategories(),
                List.of("watches", "bags", "jewellery", "accessories"),
                List.of("female", "male"),
                1,
                0,
                0,
                0,
                null);
    }

    public static int stars(double score) {
        return score >= 90 ? 5 : score >= 80 ? 4 : score >= 65 ? 3 : score >= 50 ? 2 : 1;
    }

    public int rank(int xp, Map<String, Double> bests) {
        var cleared =
                content.challenges().stream()
                        .filter(
                                c ->
                                        bests.containsKey(c.id())
                                                && bests.get(c.id()) >= c.minimumScore())
                        .toList();
        int totalStars = cleared.stream().mapToInt(c -> stars(bests.get(c.id()))).sum(), rank = 0;
        for (int n = 1; n < content.ranks().size(); n++) {
            var r = content.ranks().get(n);
            if (xp >= r.minimumXp()
                    && cleared.size() >= r.minimumCompleted()
                    && totalStars >= r.minimumStars()
                    && cleared.stream().anyMatch(c -> c.id().equals(r.milestone()))) rank = n;
            else break;
        }
        return rank;
    }
}
