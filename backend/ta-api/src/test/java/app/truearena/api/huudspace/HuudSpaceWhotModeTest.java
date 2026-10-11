package app.truearena.api.huudspace;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Whot in a Huud: the host picks Classic or The Tell before anyone sits down. */
class HuudSpaceWhotModeTest {

    @Test
    void whotGetsTheChosenModeAndClassicWhenNoneIsGiven() {
        assertThat(HuudSpaceService.gameConfigFor("whot", "tell")).containsEntry("mode", "tell");
        assertThat(HuudSpaceService.gameConfigFor("whot", " Classic ")).containsEntry("mode", "classic");
        assertThat(HuudSpaceService.gameConfigFor("whot", null)).containsEntry("mode", "classic");
    }

    @Test
    void otherGamesHaveNoModeAndWhotRejectsUnknownOnes() {
        assertThat(HuudSpaceService.gameConfigFor("chess", "tell")).isNull();
        assertThatThrownBy(() -> HuudSpaceService.gameConfigFor("whot", "bluff"))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void theModeIsReadBackFromTheRoomsRules() {
        assertThat(HuudSpaceService.modeOf("whot", "{\"mode\":\"tell\"}")).isEqualTo("tell");
        assertThat(HuudSpaceService.modeOf("whot", "{\"startingHand\":5}")).isEqualTo("classic");
        assertThat(HuudSpaceService.modeOf("whot", null)).isEqualTo("classic");
        assertThat(HuudSpaceService.modeOf("whot", "not json")).isEqualTo("classic");
        assertThat(HuudSpaceService.modeOf("chess", "{\"mode\":\"tell\"}")).isNull();
    }

    @Test
    void theTellSeatsFourPairsAndClassicKeepsItsTable() {
        assertThat(HuudSpaceService.seatsFor("whot", "tell")).isEqualTo(8);
        assertThat(HuudSpaceService.seatsFor("whot", "classic")).isEqualTo(4);
        assertThat(HuudSpaceService.seatsFor("draughts", null)).isEqualTo(2);
    }
}
