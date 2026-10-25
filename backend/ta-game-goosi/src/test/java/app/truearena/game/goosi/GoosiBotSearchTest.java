package app.truearena.game.goosi;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class GoosiBotSearchTest {
    @Test void owareSearchFeedsAnEmptyOpponentRow() {
        GoosiState.Draft d = position("oware", new int[]{0,0,0,0,0,0,1,1,1,1,1,6});
        var move = GoosiBotSearch.choose(d.pits, d.owner, d.players, Map.of(), "oware", "b", 3, 100).orElseThrow();
        assertThat(move.data()).containsEntry("pit", 11);
        new GoosiModule().onPlayerAction(d.build(), move);
    }

    @Test void relaySearchPrefersCollectingSeedsRatherThanUsingOwareCaptureRules() {
        GoosiState.Draft d = position("relay", new int[]{1,2,1,2,1,2,1,3,0,0,0,0});
        var move = GoosiBotSearch.choose(d.pits, d.owner, d.players, Map.of(), "relay", "b", 1, 100).orElseThrow();
        assertThat(move.data()).containsEntry("pit", 6); // a single seed completes house 7 to four
        var after = (GoosiState) new GoosiModule().onPlayerAction(d.build(), move);
        assertThat(after.scores[1]).isGreaterThanOrEqualTo(4);
    }

    private GoosiState.Draft position(String mode, int[] pits) {
        var d = new GoosiState.Draft();
        d.players = List.of("a", "b"); d.turnIndex = 1; d.phase = "TurnP1"; d.round = 1;
        d.pits = pits; d.scores = new int[2]; d.config = new GoosiConfig(4, 45, mode);
        for (int i = 0; i < 12; i++) d.owner[i] = i < 6 ? "a" : "b";
        return d;
    }
}
