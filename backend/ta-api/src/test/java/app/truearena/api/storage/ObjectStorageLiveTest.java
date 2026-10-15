package app.truearena.api.storage;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import java.nio.charset.StandardCharsets;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Round trip against the real bucket. Runs only with the R2 keys in the
 * environment: {@code set -a; . infra/keys/cloudflare-r2.env.local; set +a}.
 */
@EnabledIfEnvironmentVariable(named = "R2_ENDPOINT", matches = "https://.+")
class ObjectStorageLiveTest {

    private final ObjectStorage storage = new ObjectStorage(System.getenv("R2_ENDPOINT"), "playhuud-assets",
            System.getenv("R2_ACCESS_KEY_ID"), System.getenv("R2_SECRET_ACCESS_KEY"));

    @Test
    void writesAndReadsBackAnObject() {
        String prefix = System.getProperty("test.r2.prefix", "selftest/");
        String key = prefix + UUID.randomUUID() + ".txt";
        byte[] body = ("hello from PlayHuud " + key).getBytes(StandardCharsets.UTF_8);
        storage.put(key, body, "text/plain").block();
        assertThat(storage.get(key).block()).isEqualTo(body);
        assertThat(storage.get(prefix + "missing-" + UUID.randomUUID()).blockOptional()).isEmpty();
    }
}
