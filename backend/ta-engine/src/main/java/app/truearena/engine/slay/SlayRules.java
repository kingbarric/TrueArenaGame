package app.truearena.engine.slay;

import java.util.*;

/** Pure, deterministic styling and community ranking rules. No graphics or I/O. */
public final class SlayRules {
    public static final Set<String> RECOLOUR_CATEGORIES = Set.of("shoes", "tops", "shirts");
    public static final Map<String, String> ITEM_COLOURS = Map.ofEntries(
            Map.entry("black", "#28262a"), Map.entry("white", "#eee5d6"),
            Map.entry("red", "#a53541"), Map.entry("pink", "#c98491"),
            Map.entry("blue", "#48879a"), Map.entry("navy", "#283d54"),
            Map.entry("green", "#397c65"), Map.entry("purple", "#674269"),
            Map.entry("gold", "#c39b55"), Map.entry("grey", "#8e8c87"),
            Map.entry("orange", "#c5773d"), Map.entry("yellow", "#ddba55"));
    public record Item(
            String id,
            String name,
            String category,
            String body,
            List<String> styleTags,
            List<String> colourTags,
            List<String> cultureTags,
            List<String> eventTags,
            String rarity,
            String assetUrl,
            String thumbnailUrl,
            List<String> hidesRegions,
            String attachmentBone,
            boolean isDefault,
            int coinCost,
            int unlockWins,
            String placeholder) {}

    public record Theme(
            String id,
            String title,
            String description,
            List<String> styleTags,
            List<String> requiredCategories,
            List<String> optionalCategories,
            List<String> bodyEligibility,
            double systemWeight,
            int stylingSeconds,
            int votingSeconds,
            int minVotes,
            Integer budget) {}

    public record Look(
            String body,
            String skinTone,
            String facePreset,
            Map<String, String> items,
            String pose,
            String background,
            Map<String, String> itemColours) {
        public Look {
            itemColours = itemColours == null ? Map.of() : Map.copyOf(itemColours);
        }
        public Look(String body, String skinTone, String facePreset, Map<String,String> items,
                String pose, String background) {
            this(body, skinTone, facePreset, items, pose, background, Map.of());
        }
    }

    public record Score(
            double themeFit,
            double requirements,
            double colour,
            double completeness,
            double overall,
            int stars,
            List<String> missing,
            List<String> feedback) {
        public Score(double themeFit, double requirements, double colour, double completeness,
                double overall, int stars, List<String> missing) {
            this(themeFit, requirements, colour, completeness, overall, stars, missing, List.of());
        }
    }

    public record Comparison(String a, String b, String winner) {}

    private SlayRules() {}

    public static void validate(
            Look look,
            Map<String, Item> catalogue,
            Set<String> owned,
            Set<String> skinTones,
            Set<String> faces,
            Set<String> poses,
            Set<String> backgrounds) {
        if (look == null || look.body() == null || !Set.of("male", "female").contains(look.body()))
            fail("Choose an avatar body");
        if (look.skinTone() == null
                || look.facePreset() == null
                || look.pose() == null
                || look.background() == null
                || !skinTones.contains(look.skinTone())
                || !faces.contains(look.facePreset())
                || !poses.contains(look.pose())
                || !backgrounds.contains(look.background())) fail("Unknown avatar selection");
        if (look.items() == null || look.items().isEmpty() || look.items().size() > 24)
            fail("Choose an outfit");
        for (var slot : look.items().entrySet()) {
            Item item = catalogue.get(slot.getValue());
            if (item == null || !slot.getKey().equals(item.category()))
                fail("Item does not match its wardrobe category");
            if (!item.isDefault() && !owned.contains(item.id()))
                fail("Unlock this item before equipping it");
            if (!item.body().equals("unisex") && !item.body().equals(look.body()))
                fail("Item does not fit this avatar");
        }
        for (var colour : look.itemColours().entrySet()) {
            if (!look.items().containsKey(colour.getKey())
                    || !RECOLOUR_CATEGORIES.contains(colour.getKey())
                    || !ITEM_COLOURS.containsKey(colour.getValue()))
                fail("Choose an available colour for your equipped shoes, shirt or top");
        }
        if (!look.items().containsKey("outfit")
                && !look.items().containsKey("dress")
                && !(look.items().containsKey("tops") && look.items().containsKey("trousers"))
                && !(look.items().containsKey("shirts") && look.items().containsKey("trousers"))
                && !(look.items().containsKey("tops") && look.items().containsKey("skirts")))
            fail("Complete your outfit before submitting");
        if ((look.items().containsKey("outfit") || look.items().containsKey("dress"))
                && look.items().keySet().stream()
                        .anyMatch(Set.of("tops", "shirts", "trousers", "skirts")::contains))
            fail("Choose a full outfit or separate garments");
    }

    public static Score score(Look look, Theme theme, Map<String, Item> catalogue) {
        if (!theme.bodyEligibility().contains(look.body()))
            fail("This avatar is not eligible for the theme");
        List<Item> items =
                look.items().values().stream()
                        .map(catalogue::get)
                        .filter(Objects::nonNull)
                        .toList();
        // Judge each main garment rather than combining all tags into a perfect
        // score. A formal hairstyle or bag cannot turn a casual outfit formal.
        Set<String> garmentCategories = Set.of("outfit", "dress", "tops", "shirts", "trousers", "skirts");
        Set<String> detailCategories = Set.of("shoes", "headwear", "bags", "jewellery", "watches", "glasses", "accessories", "makeup");
        List<Item> garments = items.stream().filter(i -> garmentCategories.contains(i.category())).toList();
        List<Item> details = items.stream().filter(i -> detailCategories.contains(i.category())).toList();
        double garmentFit = garments.stream().mapToDouble(i -> themeMatch(i, theme)).average().orElse(0);
        double detailFit = details.stream().mapToDouble(i -> themeMatch(i, theme) > 0 ? 100 : 0).average().orElse(garmentFit);
        double fit = .85 * garmentFit + .15 * detailFit;
        Set<String> categories = new HashSet<>();
        items.forEach(i -> categories.add(i.category()));
        if (categories.contains("dress")
                || (categories.contains("trousers") || categories.contains("skirts"))
                        && (categories.contains("tops") || categories.contains("shirts")))
            categories.add("outfit");
        List<String> missing =
                theme.requiredCategories().stream().filter(c -> !categories.contains(c)).toList();
        double requirements =
                theme.requiredCategories().isEmpty()
                        ? 100
                        : 100.0
                                * (theme.requiredCategories().size() - missing.size())
                                / theme.requiredCategories().size();
        Set<String> colours = new HashSet<>();
        items.stream().filter(i -> garmentCategories.contains(i.category()) || detailCategories.contains(i.category()))
                .forEach(i -> {
                    String chosen = look.itemColours().get(i.category());
                    if (chosen != null) colours.add(chosen);
                    else colours.addAll(i.colourTags());
                });
        // Neutral colours work together; multiple accent colours cost a small, explicit amount.
        colours.removeAll(Set.of("black", "white", "grey", "gray", "navy", "gold", "silver", "brown", "beige", "cream", "ivory", "nude"));
        double colour = garments.isEmpty() ? 0 : Math.max(20, 100 - Math.max(0, colours.size() - 2) * 20);
        Set<String> completionSlots = new LinkedHashSet<>(List.of("outfit", "shoes"));
        completionSlots.addAll(theme.requiredCategories());
        double completeness =
                100.0
                        * completionSlots.stream()
                                .filter(categories::contains)
                                .count()
                        / completionSlots.size();
        // Every missing requirement limits the whole look, not just one small
        // subscore. One missing item cannot still earn a three-star result.
        double cap = Math.max(0, 100 - 25 * missing.size());
        double overall = round(Math.min(cap, .50 * fit + .25 * requirements + .15 * colour + .10 * completeness));
        List<String> feedback = new ArrayList<>();
        if (!missing.isEmpty()) feedback.add("Missing required items: " + String.join(", ", missing) + ". Score limited to " + (int) cap + ".");
        for (Item garment : garments) {
            double match = themeMatch(garment, theme);
            if (match < 100) feedback.add(garment.name() + " matches " + (int) Math.round(match) + "% of the theme tags: " + String.join(", ", theme.styleTags()) + ".");
        }
        List<String> mismatchedDetails = details.stream().filter(i -> themeMatch(i, theme) == 0).map(Item::name).toList();
        if (!mismatchedDetails.isEmpty()) feedback.add("Details outside the theme: " + String.join(", ", mismatchedDetails) + ".");
        if (colours.size() > 2) feedback.add("Your palette has " + colours.size() + " accent colours. Try two accents with neutrals.");
        if (!categories.contains("shoes") && !missing.contains("shoes")) feedback.add("Footwear would complete the look.");
        if (feedback.isEmpty()) feedback.add("Your outfit, required items and palette match this brief.");
        if (theme.budget() != null
                && items.stream().mapToInt(Item::coinCost).sum() > theme.budget())
            fail("Look exceeds the challenge budget");
        return new Score(
                round(fit),
                round(requirements),
                round(colour),
                round(completeness),
                overall,
                overall >= 85 ? 3 : overall >= 65 ? 2 : overall >= 40 ? 1 : 0,
                missing,
                List.copyOf(feedback));
    }

    private static double themeMatch(Item item, Theme theme) {
        Set<String> tags = new HashSet<>(item.styleTags());
        tags.addAll(item.eventTags());
        tags.addAll(item.cultureTags());
        return theme.styleTags().isEmpty() ? 100 : 100.0 * theme.styleTags().stream().filter(tags::contains).count() / theme.styleTags().size();
    }

    /** Regularised Bradley–Terry: repeated votes don't privilege entries with more exposure. */
    public static Map<String, Double> community(List<String> entries, List<Comparison> votes) {
        Map<String, Double> strength = new LinkedHashMap<>();
        for (String id : entries) strength.put(id, 1.0);
        if (entries.size() < 2)
            return strength.entrySet().stream()
                    .collect(java.util.stream.Collectors.toMap(Map.Entry::getKey, e -> 50.0));
        Map<String, List<Comparison>> adjacency = new HashMap<>();
        Map<String, Double> wins = new HashMap<>();
        for (String id : entries) {
            adjacency.put(id, new ArrayList<>());
            wins.put(id, 1.0);
        }
        for (Comparison v : votes) {
            if (!strength.containsKey(v.a()) || !strength.containsKey(v.b())) continue;
            adjacency.get(v.a()).add(v);
            adjacency.get(v.b()).add(v);
            if (wins.containsKey(v.winner())) wins.merge(v.winner(), 1.0, Double::sum);
        }
        for (int step = 0; step < 80; step++) {
            Map<String, Double> next = new LinkedHashMap<>();
            for (String id : entries) {
                double denominator = 2 / (strength.get(id) + 1);
                for (Comparison v : adjacency.get(id)) {
                    String other = v.a().equals(id) ? v.b() : v.a();
                    denominator += 1 / (strength.get(id) + strength.get(other));
                }
                next.put(id, wins.get(id) / denominator);
            }
            double mean =
                    next.values().stream().mapToDouble(Double::doubleValue).average().orElse(1);
            next.replaceAll((id, value) -> value / mean);
            strength = next;
        }
        Map<String, Double> result = new LinkedHashMap<>();
        for (String id : entries) {
            double s = 0;
            for (String other : entries)
                if (!id.equals(other))
                    s += strength.get(id) / (strength.get(id) + strength.get(other));
            result.put(id, round(100 * s / (entries.size() - 1)));
        }
        return result;
    }

    public static double round(double n) {
        return Math.round(n * 10) / 10.0;
    }

    private static void fail(String message) {
        throw new IllegalArgumentException(message);
    }
}
