package app.truearena.api.storage;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class ObjectStorageTest {

    @Test
    void offWithoutKeys() {
        assertThat(new ObjectStorage("", "playhuud-assets", "", "").enabled()).isFalse();
        assertThat(new ObjectStorage("https://x.r2.cloudflarestorage.com", "b", "k", "s").enabled()).isTrue();
    }

    @Test
    void keysAreEncodedPerSegmentForSigning() {
        assertThat(ObjectStorage.encodePath("slay/looks/a b+c.jpg")).isEqualTo("slay/looks/a%20b%2Bc.jpg");
        assertThat(ObjectStorage.encode("~ok-_.")).isEqualTo("~ok-_.");
    }
}
