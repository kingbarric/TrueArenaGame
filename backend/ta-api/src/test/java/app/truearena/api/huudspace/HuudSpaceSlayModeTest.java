package app.truearena.api.huudspace;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** SlayHuud in a Huud: the host picks a Style Battle or a Group Show before anyone sits down. */
class HuudSpaceSlayModeTest {

    @Test
    void aBattleSeatsTwoAndAShowSeatsEight() {
        assertThat(HuudSpaceService.gameConfigFor("slayhuud", "battle"))
                .containsEntry("mode", "battle").containsEntry("seats", 2);
        assertThat(HuudSpaceService.gameConfigFor("slayhuud", " Group "))
                .containsEntry("mode", "group").containsEntry("seats", 8);
        assertThat(HuudSpaceService.gameConfigFor("slayhuud", null)).containsEntry("mode", "battle");
    }

    @Test
    void theThemeIsLeftToSlayHuudAndUnknownModesAreRefused() {
        assertThat(HuudSpaceService.gameConfigFor("slayhuud", "group")).doesNotContainKey("themeId");
        assertThatThrownBy(() -> HuudSpaceService.gameConfigFor("slayhuud", "slay_or_pass"))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void theModeIsReadBackFromTheRoomsRules() {
        assertThat(HuudSpaceService.modeOf("slayhuud", "{\"mode\":\"group\",\"seats\":8}")).isEqualTo("group");
        assertThat(HuudSpaceService.modeOf("slayhuud", "{\"mode\":\"battle\"}")).isEqualTo("battle");
        assertThat(HuudSpaceService.modeOf("slayhuud", null)).isEqualTo("battle");
        assertThat(HuudSpaceService.modeOf("slayhuud", "not json")).isEqualTo("battle");
    }

    @Test
    void theHuudTableMatchesTheMode() {
        assertThat(HuudSpaceService.seatsFor("slayhuud", "group")).isEqualTo(8);
        assertThat(HuudSpaceService.seatsFor("slayhuud", "battle")).isEqualTo(2);
    }
}
