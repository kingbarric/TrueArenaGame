package app.truearena.api.huudspace;

import app.truearena.engine.GameEvent;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class HuudMomentTextTest {

    private static final String AMA = "11111111-1111-1111-1111-111111111111";
    private static final String KOFI = "22222222-2222-2222-2222-222222222222";

    @Test
    void whotTellsTheBigPlaysAndTheLastCard() {
        assertThat(line("whot", "GENERAL_MARKET", Map.of("by", AMA)).text()).isEqualTo("called General Market. Everyone picks one");
        assertThat(line("whot", "CARD_PLAYED", Map.of("by", AMA, "card", "star-7", "calledShape", "",
                "handSizes", Map.of(AMA, 1, KOFI, 4))).text()).isEqualTo("is on last card!");
        assertThat(line("whot", "CARD_PLAYED", Map.of("by", AMA, "card", "whot-20", "calledShape", "cross",
                "handSizes", Map.of(AMA, 3))).text()).isEqualTo("played Whot and asked for crosses");
        var ordinary = line("whot", "CARD_PLAYED", Map.of("by", AMA, "card", "circle-5", "calledShape", "", "handSizes", Map.of(AMA, 4)));
        assertThat(ordinary.text()).isEqualTo("played Circle 5");
        assertThat(ordinary.notable()).isFalse();
        assertThat(line("whot", "CARD_DRAWN", Map.of("by", KOFI, "count", 2, "penalty", true)).text()).isEqualTo("picked 2 cards");
    }

    @Test
    void chessNamesTheMoverFromTheOpeningSides() {
        var sides = HuudMomentText.sides("chess", GameEvent.pub(1, "GAME_STARTED", Map.of("white", AMA, "black", KOFI)));
        var capture = HuudMomentText.describe("chess", "MOVE_PLAYED",
                Map.of("side", "black", "san", "Qxd5", "captured", "wQ", "check", false), sides).orElseThrow();
        assertThat(capture.actor()).isEqualTo(KOFI);
        assertThat(capture.text()).isEqualTo("took a queen (Qxd5)");
        var mate = HuudMomentText.describe("chess", "GAME_OVER", Map.of("winningSide", "white", "reason", "checkmate"), sides).orElseThrow();
        assertThat(mate.actor()).isEqualTo(AMA);
        assertThat(mate.text()).isEqualTo("won by checkmate");
    }

    @Test
    void mentionsCarryTheOtherPlayer() {
        var accusation = HuudMomentText.describe("truearena", "PUBLIC_ACCUSATION", Map.of("by", AMA, "accused", KOFI), Map.of()).orElseThrow();
        assertThat(accusation.text()).isEqualTo("accused {0}");
        assertThat(accusation.mentions()).containsExactly(KOFI);
        var knock = HuudMomentText.describe("ludo", "PIECE_MOVED",
                Map.of("player", AMA, "from", 10, "to", 56, "captured", List.of(KOFI + ":2")), Map.of()).orElseThrow();
        assertThat(knock.text()).isEqualTo("sent {0} back home");
        assertThat(knock.mentions()).containsExactly(KOFI);
    }

    @Test
    void pickPrefersNotableLinesAndNeverReadsPrivateEvents() {
        List<GameEvent> log = List.of(
                GameEvent.pub(1, "GENERAL_MARKET", Map.of("by", KOFI)),
                GameEvent.toPlayer(2, "YOUR_HAND", Map.of("cards", List.of("star-7")), AMA),
                GameEvent.pub(3, "CARD_PLAYED", Map.of("by", AMA, "card", "circle-5", "calledShape", "", "handSizes", Map.of(AMA, 4))));
        var picked = HuudMomentText.pick("whot", log, Map.of(), 2);
        assertThat(picked).extracting(HuudMomentText.Line::text).containsExactly("called General Market. Everyone picks one");

        var quiet = HuudMomentText.pick("whot", List.of(log.get(1), log.get(2)), Map.of(), 2);
        assertThat(quiet).extracting(HuudMomentText.Line::text).containsExactly("played Circle 5");
    }

    @Test
    void unknownGamesAndEventsSayNothing() {
        assertThat(HuudMomentText.describe("slayhuud", "ANYTHING", Map.of(), Map.of())).isEmpty();
        assertThat(HuudMomentText.describe("whot", "TURN_STARTED", Map.of(), Map.of())).isEmpty();
    }

    private static HuudMomentText.Line line(String game, String type, Map<String, Object> payload) {
        return HuudMomentText.describe(game, type, payload, Map.of()).orElseThrow();
    }
}
