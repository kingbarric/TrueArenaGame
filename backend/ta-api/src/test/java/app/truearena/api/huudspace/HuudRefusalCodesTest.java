package app.truearena.api.huudspace;

import app.truearena.api.support.ApiExceptions;
import app.truearena.api.support.PublicErrorAdvice;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** The app can't read the server's reasons, so each multiple-Huud refusal must arrive as its own code. */
class HuudRefusalCodesTest {

    private static String codeFor(String reason) {
        return String.valueOf(new PublicErrorAdvice().handle(ApiExceptions.conflict(reason)).getBody().get("code"));
    }

    @Test void eachMultipleHuudRefusalHasItsOwnCode() {
        assertThat(codeFor(HuudSpaceService.finishFirst("Family"))).isEqualTo("FINISH_GAME_FIRST");
        assertThat(codeFor(HuudSpaceService.liveAlready("Family"))).isEqualTo("ONE_LIVE_HUUD");
        assertThat(codeFor(HuudSpaceService.tooMany())).isEqualTo("HUUD_LIMIT");
    }
}
