package app.truearena.engine.slay;

import static org.assertj.core.api.Assertions.*;
import org.junit.jupiter.api.Test;
import java.util.*;
import app.truearena.engine.slay.SlayRules.*;

class SlayStyleScoringTest {
    private Item item(String id, String category, List<String> tags, String... colours) {
        return new Item(id, id, category, "female", tags, List.of(colours), List.of(), List.of(),
                "common", "assets/" + id, null, List.of(), null, true, 0, 0, null);
    }
    private final Theme theme = new Theme("office", "Office", "Formal styling",
            List.of("corporate", "formal", "elegant"), List.of("outfit", "shoes", "watches"),
            List.of(), List.of("female", "male"), .35, 180, 300, 6, null);
    private final Map<String, Item> items = Map.of(
            "suit", item("suit", "outfit", theme.styleTags(), "black"),
            "casual", item("casual", "outfit", List.of("casual"), "white"),
            "top", item("top", "tops", theme.styleTags(), "red"),
            "pants", item("pants", "trousers", theme.styleTags(), "purple"),
            "casual-pants", item("casual-pants", "trousers", List.of("casual"), "purple"),
            "shoes", item("shoes", "shoes", List.of("formal"), "blue"),
            "watch", item("watch", "watches", List.of("corporate"), "green"),
            "hair", item("hair", "hair", theme.styleTags(), "pink"),
            "bag", item("bag", "bags", theme.styleTags(), "yellow"));
    private Score score(Map<String,String> equipped) {
        return SlayRules.score(new Look("female", "skin", "face", equipped, "signature", "studio"), theme, items);
    }
    @Test void matchingOutfitBeatsAnUnrelatedOutfitWithMatchingDetails() {
        var right = score(Map.of("outfit","suit","shoes","shoes","watches","watch"));
        var wrong = score(Map.of("outfit","casual","shoes","shoes","watches","watch","bags","bag"));
        assertThat(right.overall()).isGreaterThanOrEqualTo(85);
        assertThat(wrong.themeFit()).isEqualTo(15);
        assertThat(wrong.overall()).isLessThan(65);
        assertThat(wrong.feedback()).anyMatch(f -> f.contains("casual matches 0%"));
    }
    @Test void everyMissingRequirementLimitsTheFinalScore() {
        var full = Map.of("outfit","suit","shoes","shoes","watches","watch");
        for (String category : theme.requiredCategories()) {
            var partial = new HashMap<>(full); partial.remove(category);
            var score = score(partial);
            assertThat(score.missing()).contains(category);
            assertThat(score.overall()).isLessThanOrEqualTo(75);
            assertThat(score.stars()).isLessThan(3);
            assertThat(score.feedback()).anyMatch(f -> f.contains("Score limited to 75"));
        }
        assertThat(score(Map.of("outfit","suit")).overall()).isLessThanOrEqualTo(50);
    }
    @Test void themeFitEvaluatesEachSeparateGarmentAndIgnoresHairTags() {
        var coordinated = score(Map.of("tops","top","trousers","pants","shoes","shoes","watches","watch"));
        var mixed = Map.of("tops","top","trousers","casual-pants","shoes","shoes","watches","watch");
        var mismatch = score(mixed);
        assertThat(mismatch.themeFit()).isLessThan(coordinated.themeFit());
        var withHair = new HashMap<>(mixed); withHair.put("hair","hair");
        assertThat(score(withHair).overall()).isEqualTo(mismatch.overall());
        assertThat(coordinated.missing()).isEmpty();
        assertThat(mismatch.feedback()).anyMatch(f -> f.contains("casual-pants matches 0%"));
    }
    @Test void paletteOverloadHasAVisibleDeduction() {
        var palette = score(Map.of("tops","top","trousers","pants","shoes","shoes","watches","watch","bags","bag"));
        assertThat(palette.colour()).isEqualTo(40);
        assertThat(palette.feedback()).anyMatch(f -> f.contains("5 accent colours"));
    }
    @Test void skinFacePoseAndSceneDoNotChangeTheStylingScore() {
        var equipped = Map.of("outfit","suit","shoes","shoes","watches","watch");
        var changed = SlayRules.score(new Look("female","different-skin","other-face",equipped,"celebrate","royal"),theme,items);
        assertThat(changed).isEqualTo(score(equipped));
    }
    @Test void selectedColoursAffectPaletteAndInvalidSelectionsCannotBeSubmitted() {
        var equipped = Map.of("tops","top","trousers","pants","shoes","shoes","watches","watch");
        var original = score(equipped);
        var dyed = new Look("female","skin","face",equipped,"signature","studio", Map.of("tops","black","shoes","black"));
        assertThat(SlayRules.score(dyed,theme,items).colour()).isGreaterThan(original.colour());
        var tones=Set.of("skin"); var faces=Set.of("face"); var poses=Set.of("signature"); var scenes=Set.of("studio");
        assertThatCode(() -> SlayRules.validate(dyed,items,Set.of(),tones,faces,poses,scenes)).doesNotThrowAnyException();
        for (var invalid : List.of(Map.of("tops","unknown"), Map.of("bags","black"), Map.of("watches","red"))) {
            var bad=new Look("female","skin","face",equipped,"signature","studio",invalid);
            assertThatThrownBy(() -> SlayRules.validate(bad,items,Set.of(),tones,faces,poses,scenes)).hasMessageContaining("available colour");
        }
    }
}
