package app.truearena.ws.contract;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Phase 0.5: every golden frame in shared/contract/testdata/ decodes into {@link Envelope}
 * and re-encodes to a semantically identical tree. Guards Java-side drift from the schema.
 */
class EnvelopeRoundTripTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private static Path testdataDir() {
        for (Path candidate : List.of(
                Path.of("../../shared/contract/testdata"),
                Path.of("../shared/contract/testdata"),
                Path.of("shared/contract/testdata"))) {
            if (Files.isDirectory(candidate)) {
                return candidate;
            }
        }
        throw new IllegalStateException("cannot locate shared/contract/testdata from " + Path.of("").toAbsolutePath());
    }

    @Test
    void goldenFramesRoundTrip() throws IOException {
        Path dir = testdataDir();
        try (Stream<Path> files = Files.list(dir)) {
            List<Path> jsons = files.filter(p -> p.toString().endsWith(".json")).sorted().toList();
            assertTrue(jsons.size() >= 2, "expected golden frames in " + dir.toAbsolutePath());

            for (Path f : jsons) {
                JsonNode original = MAPPER.readTree(f.toFile());
                Envelope env = MAPPER.treeToValue(original, Envelope.class);
                JsonNode reencoded = MAPPER.valueToTree(env);

                assertEquals(original.get("v"), reencoded.get("v"), f + " v");
                assertEquals(original.get("type"), reencoded.get("type"), f + " type");
                assertEquals(original.get("ts"), reencoded.get("ts"), f + " ts");
                assertEquals(original.path("seq").asLong(0), reencoded.path("seq").asLong(0), f + " seq");
            }
        }
    }
}
