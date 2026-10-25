package app.truearena.api.championship;

import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;

/** A Huud championship started short of a full field: the smallest bracket that fits, the rest byes. */
class HuudChampionshipByesTest {

    static List<UUID> players(int n) {
        return IntStream.range(0, n).mapToObj(i -> UUID.randomUUID()).toList();
    }

    @Test
    void theBracketIsTheSmallestOneThePlayersFit() {
        assertThat(ChampionshipService.fieldFor(4)).isEqualTo(4);
        assertThat(ChampionshipService.fieldFor(5)).isEqualTo(8);
        assertThat(ChampionshipService.fieldFor(8)).isEqualTo(8);
        assertThat(ChampionshipService.fieldFor(9)).isEqualTo(16);
        assertThat(ChampionshipService.fieldFor(17)).isEqualTo(32);
        assertThat(ChampionshipService.fieldFor(33)).isEqualTo(64);
        assertThat(ChampionshipService.fieldFor(64)).isEqualTo(64);
    }

    @Test
    void aFullFieldHasNoByes() {
        List<UUID> eight = players(8);
        assertThat(ChampionshipService.seatWithByes(eight, 8)).isEqualTo(eight);
    }

    @Test
    void everyPlayerGetsASeatAndNoBoardIsTwoByes() {
        for (int n = ChampionshipService.HUUD_MIN_PLAYERS; n <= 64; n++) {
            int field = ChampionshipService.fieldFor(n);
            List<UUID> in = players(n);
            List<UUID> seats = ChampionshipService.seatWithByes(in, field);
            assertThat(seats).hasSize(field);
            assertThat(seats.stream().filter(Objects::nonNull).toList()).isEqualTo(in);
            for (int board = 0; board < field; board += 2)
                assertThat(seats.get(board)).as("%d players, board %d", n, board / 2).isNotNull();
        }
    }

    @Test
    void byesAreSpreadAcrossTheBracket() {
        // 6 players in an 8: one bye in each half, so the two bye players don't meet in round two.
        assertThat(byeBoards(ChampionshipService.seatWithByes(players(6), 8))).containsExactly(0, 2);
        // 12 in a 16: four byes, one in each quarter.
        assertThat(byeBoards(ChampionshipService.seatWithByes(players(12), 16))).containsExactly(0, 2, 4, 6);
        // 10 in a 16: six byes, three in each half.
        assertThat(byeBoards(ChampionshipService.seatWithByes(players(10), 16))).containsExactly(0, 1, 2, 4, 5, 6);
    }

    static List<Integer> byeBoards(List<UUID> seats) {
        List<Integer> boards = new ArrayList<>();
        for (int board = 0; board < seats.size() / 2; board++) if (seats.get(board * 2 + 1) == null) boards.add(board);
        return boards;
    }
}
