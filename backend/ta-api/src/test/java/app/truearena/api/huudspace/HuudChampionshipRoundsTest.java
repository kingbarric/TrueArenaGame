package app.truearena.api.huudspace;

import app.truearena.api.championship.ChampionshipService;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;

/** A Huud championship is 4 to 64 players; its rounds are named from the Final back. */
class HuudChampionshipRoundsTest {

    static List<String> rounds(int size) {
        int rounds = Integer.numberOfTrailingZeros(size);
        return IntStream.rangeClosed(1, rounds).mapToObj(r -> HuudChampionshipService.roundName(r, rounds)).toList();
    }

    @Test
    void everySizeIsAFullBracket() {
        assertThat(ChampionshipService.HUUD_SIZES).containsExactly(4, 8, 16, 32, 64);
    }

    @Test
    void roundsAreNamedFromTheFinalBack() {
        assertThat(rounds(4)).containsExactly("Semi Finals", "Final");
        assertThat(rounds(8)).containsExactly("Quarter Finals", "Semi Finals", "Final");
        assertThat(rounds(16)).containsExactly("Round of 16", "Quarter Finals", "Semi Finals", "Final");
        assertThat(rounds(32)).containsExactly("Round of 32", "Round of 16", "Quarter Finals", "Semi Finals", "Final");
        assertThat(rounds(64)).containsExactly("Round of 64", "Round of 32", "Round of 16",
                "Quarter Finals", "Semi Finals", "Final");
    }
}
