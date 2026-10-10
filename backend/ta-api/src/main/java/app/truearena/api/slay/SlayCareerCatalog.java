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

    /** Pieces a 4★ or 5★ result can unlock, in the order they are given. */
    public record Rewards(List<String> four, List<String> five) {}

    /**
     * One career stage: where it happens (its dressing room and event venue are
     * drawn by the renderer from {@code location}), the poses and clothing
     * collection it opens per avatar body, and its reward pools.
     */
    public record Chapter(
            int chapter,
            String title,
            String location,
            String room,
            String venue,
            List<String> poses,
            Map<String, List<String>> collection,
            Map<String, Rewards> rewards) {}

    public record Content(List<Challenge> challenges, List<Rank> ranks, List<Chapter> chapters) {}

    /** Hair and beauty follow normal ownership; career stages gate clothing and accessories. */
    public static final Set<String> BEAUTY = Set.of("hair", "makeup", "eyes");

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

    public Chapter chapter(int n) {
        return content.chapters().stream()
                .filter(c -> c.chapter() == n)
                .findFirst()
                .orElseThrow(() -> new IllegalStateException("Missing career chapter " + n));
    }

    /** Stage collections opened by reaching {@code rank}; granted to the wardrobe. */
    public Set<String> stageItems(String body, int rank) {
        Set<String> items = new LinkedHashSet<>();
        content.chapters().stream()
                .filter(c -> c.chapter() <= rank)
                .forEach(c -> items.addAll(c.collection().getOrDefault(body, List.of())));
        return items;
    }

    /** Clothing usable in career at {@code rank}: stage collections plus reward pieces already won. */
    public Set<String> careerItems(String body, int rank, Set<String> owned) {
        Set<String> items = stageItems(body, rank);
        content.chapters().stream()
                .filter(c -> c.chapter() <= rank)
                .map(c -> c.rewards().get(body))
                .filter(Objects::nonNull)
                .forEach(
                        r ->
                                java.util.stream.Stream.concat(r.four().stream(), r.five().stream())
                                        .filter(owned::contains)
                                        .forEach(items::add));
        return items;
    }

    public List<String> poses(int rank) {
        return content.chapters().stream()
                .filter(c -> c.chapter() <= rank)
                .flatMap(c -> c.poses().stream())
                .toList();
    }

    /** The next piece a {@code stars}-star result unlocks in this chapter, if any is left. */
    public Optional<String> nextReward(String body, int chapter, int stars, Set<String> owned) {
        Rewards pool = chapter(chapter).rewards().get(body);
        if (pool == null || stars < 4) return Optional.empty();
        return (stars >= 5 ? pool.five() : pool.four())
                .stream().filter(id -> !owned.contains(id)).findFirst();
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
