package app.truearena.api.huudspace;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Draughts in a Huud: casual, seizure or official rules, picked before anyone sits down. */
class HuudSpaceDraughtsModeTest {

    @Test
    void eachModeSetsItsCaptureRules() {
        assertThat(HuudSpaceService.gameConfigFor("draughts", "casual"))
                .containsEntry("mandatoryCapture", false).containsEntry("seizure", false);
        assertThat(HuudSpaceService.gameConfigFor("draughts", "Seizure"))
                .containsEntry("mandatoryCapture", false).containsEntry("seizure", true);
        assertThat(HuudSpaceService.gameConfigFor("draughts", "official"))
                .containsEntry("mandatoryCapture", true).containsEntry("seizure", false);
        assertThat(HuudSpaceService.gameConfigFor("draughts", null)).isNull();
        assertThatThrownBy(() -> HuudSpaceService.gameConfigFor("draughts", "blitz"))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void theModeIsReadBackFromTheRoomsRules() {
        assertThat(HuudSpaceService.modeOf("draughts", "{\"mandatoryCapture\":false,\"seizure\":true}")).isEqualTo("seizure");
        assertThat(HuudSpaceService.modeOf("draughts", "{\"mandatoryCapture\":true}")).isEqualTo("official");
        assertThat(HuudSpaceService.modeOf("draughts", null)).isEqualTo("casual");
        assertThat(HuudSpaceService.seatsFor("draughts", "seizure")).isEqualTo(2);
    }
}
