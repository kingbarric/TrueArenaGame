package app.truearena.api.slay;

import static org.assertj.core.api.Assertions.*;
import app.truearena.engine.slay.SlayRules;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.Test;
import java.nio.file.*;

class SlayScoringContractTest {
    @Test void previewFixturesMatchAuthoritativeScoresForTheActualWardrobe() throws Exception {
        var mapper = new ObjectMapper();
        var catalog = new SlayCatalog(mapper);
        var path = Path.of(System.getProperty("basedir"), "../../docs/fixtures/slay-scoring.json");
        var fixtures = mapper.readTree(path.toFile());
        boolean update = Boolean.getBoolean("slay.updateScoreFixtures");
        for (var fixture : fixtures) {
            var look = mapper.treeToValue(fixture.get("look"), SlayRules.Look.class);
            var score = SlayRules.score(look, catalog.theme(fixture.get("theme").asText()), catalog.items());
            var actual = mapper.valueToTree(score);
            if (update) ((ObjectNode) fixture).set("expected", actual);
            else assertThat(actual).as(fixture.get("name").asText()).isEqualTo(fixture.get("expected"));
        }
        if (update) mapper.writerWithDefaultPrettyPrinter().writeValue(path.toFile(), fixtures);
    }
    @Test void savedLooksKeepColoursAndLegacyLooksStillLoad() throws Exception {
        var mapper = new ObjectMapper();
        var catalog = new SlayCatalog(mapper);
        assertThat(catalog.manifest().itemColourPalette()).isEqualTo(SlayRules.ITEM_COLOURS);
        var legacy = mapper.readValue("{\"body\":\"female\",\"skinTone\":\"skin\",\"facePreset\":\"classic\",\"items\":{\"shoes\":\"shoe-0\"},\"pose\":\"signature\",\"background\":\"studio\"}", SlayRules.Look.class);
        assertThat(legacy.itemColours()).isEmpty();
        var dyed = new SlayRules.Look(legacy.body(), legacy.skinTone(), legacy.facePreset(), legacy.items(), legacy.pose(), legacy.background(), java.util.Map.of("shoes","red"));
        assertThat(mapper.readValue(mapper.writeValueAsString(dyed), SlayRules.Look.class)).isEqualTo(dyed);
    }
    @Test void catalogueExposesDuplicateAliasesWithoutRemovingSavedLookItems() throws Exception {
        var catalog = new SlayCatalog(new ObjectMapper());
        var presentation = catalog.manifest().wardrobePresentation();
        assertThat(presentation.get("female-dress-collection-9").get("duplicateOf")).isEqualTo("female-essential");
        assertThat(presentation.get("female-essential").get("category")).isEqualTo("dress");
        assertThat(catalog.items()).containsKeys("female-dress-collection-9", "female-essential");
    }
}
