package app.truearena.api.huudspace;

import app.truearena.engine.GameConfig;
import app.truearena.game.truearena.Presets;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Traitors in a Huud: the host picks one of the five modes before anyone sits down. */
class HuudSpaceTraitorsModeTest {

    @Test
    void eachModeBringsItsOwnRulesUnchanged() throws Exception {
        ObjectMapper json = new ObjectMapper();
        for (Presets.Mode mode : Presets.ALL) {
            Map<String, Object> config = HuudSpaceService.traitorsConfigFor(mode.slug());
            GameConfig back = json.readValue(json.writeValueAsString(config), GameConfig.class);
            assertThat(back).isEqualTo(mode.config());
        }
    }

    @Test
    void theTableSeatsTheModesMostPlayers() {
        assertThat(HuudSpaceService.seatsFor("truearena", "the_last_alibi")).isEqualTo(16);
        assertThat(HuudSpaceService.seatsFor("truearena", "final_gambit")).isEqualTo(8);
        assertThat(HuudSpaceService.seatsFor("truearena", null)).isEqualTo(6);
    }

    @Test
    void theModeIsReadBackFromTheRoomsRules() throws Exception {
        String stored = new ObjectMapper().writeValueAsString(HuudSpaceService.traitorsConfigFor("blood_moon"));
        assertThat(HuudSpaceService.modeOf("truearena", stored)).isEqualTo("blood_moon");
        assertThat(HuudSpaceService.modeOf("truearena", null)).isNull();
        assertThat(HuudSpaceService.modeOf("truearena", "{\"preset\":\"custom\"}")).isNull();
    }

    @Test
    void noModeKeepsTheDefaultAndUnknownOnesAreRefused() {
        assertThat(HuudSpaceService.traitorsConfigFor(null)).isNull();
        assertThatThrownBy(() -> HuudSpaceService.traitorsConfigFor("nope"))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
