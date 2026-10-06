package app.truearena.api.competitive;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class LocationCatalogTest {

    @Test
    @DisplayName("every ISO country is available, by stable code")
    void countries() {
        assertThat(LocationCatalog.countries()).hasSizeGreaterThan(200);
        assertThat(LocationCatalog.country("ng")).get()
                .satisfies(c -> {
                    assertThat(c.code()).isEqualTo("NG");
                    assertThat(c.name()).isEqualTo("Nigeria");
                    assertThat(c.catalogued()).isTrue();
                });
        assertThat(LocationCatalog.country("XX")).isEmpty();
    }

    @Test
    @DisplayName("Nigeria has all 36 states plus the FCT")
    void nigeria() {
        assertThat(LocationCatalog.regions("NG")).hasSize(37);
        assertThat(LocationCatalog.resolveRegion("NG", "ng-ri", null)).get()
                .extracting(LocationCatalog.Region::name).isEqualTo("Rivers");
    }

    @Test
    @DisplayName("a catalogued country rejects an invented region — no boards of one")
    void cataloguedIsStrict() {
        assertThat(LocationCatalog.resolveRegion("NG", null, "Lagos Island")).isEmpty();
        assertThat(LocationCatalog.resolveRegion("NG", "NG-XX", null)).isEmpty();
    }

    @Test
    @DisplayName("elsewhere a free-text region is normalised so spelling can't fork the board")
    void freeTextRegionsAreSlugged() {
        var a = LocationCatalog.resolveRegion("KE", null, "  Nairobi  ").orElseThrow();
        var b = LocationCatalog.resolveRegion("KE", null, "nairobi").orElseThrow();
        assertThat(a.code()).isEqualTo("KE-NAIROBI").isEqualTo(b.code());
        assertThat(LocationCatalog.resolveRegion("CI", null, "Côte Lagunes").orElseThrow().code())
                .isEqualTo("CI-COTE-LAGUNES");
    }
}
