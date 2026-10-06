package app.truearena.api.competitive;

import app.truearena.api.competitive.RatedMatchPolicy.Seat;
import app.truearena.api.competitive.RatedMatchPolicy.UnrankedReason;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class RatedMatchPolicyTest {

    private final RatedMatchPolicy policy = new RatedMatchPolicy(CompetitiveSettings.defaults());

    private static final Seat ADA = new Seat("a", false, false);
    private static final Seat BOLA = new Seat("b", false, false);

    @Test
    @DisplayName("two verified people in a ranked Draughts room: rated")
    void rankedHumanMatch() {
        assertThat(policy.decide("draughts", true, false, List.of(ADA, BOLA), 0)).isEmpty();
    }

    @Test
    @DisplayName("a championship game is rated even if the room predates the ranked flag")
    void championshipCounts() {
        assertThat(policy.decide("draughts", false, true, List.of(ADA, BOLA), 0)).isEmpty();
    }

    @Test
    @DisplayName("casual is the default — nothing becomes rated unless asked for")
    void casualRoom() {
        assertThat(policy.decide("draughts", false, false, List.of(ADA, BOLA), 0))
                .contains(UnrankedReason.CASUAL_ROOM);
    }

    @Test
    @DisplayName("a game with no skill rating is never rated, however the room was set up")
    void unratedGameType() {
        assertThat(policy.decide("truearena", true, false, List.of(ADA, BOLA), 0))
                .contains(UnrankedReason.UNRATED_GAME_TYPE);
    }

    @Test
    @DisplayName("a Cyber Agent in the match makes it unrated — agents are a free farm")
    void agentPresent() {
        assertThat(policy.decide("draughts", true, false, List.of(ADA, new Seat("bot", true, false)), 0))
                .contains(UnrankedReason.VS_AGENT);
    }

    @Test
    @DisplayName("a guest in the match makes it unrated — a device isn't a verified person")
    void guestPresent() {
        assertThat(policy.decide("draughts", true, false, List.of(ADA, new Seat("g", false, true)), 0))
                .contains(UnrankedReason.GUEST_PLAYER);
    }

    @Test
    @DisplayName("one human alone can't produce a rating")
    void singleHuman() {
        assertThat(policy.decide("draughts", true, false, List.of(ADA), 0))
                .contains(UnrankedReason.TOO_FEW_HUMANS);
    }

    @Test
    @DisplayName("the same pair stops gaining rating after the daily cap — the alt-account farm guard")
    void repeatOpponentCap() {
        assertThat(policy.decide("draughts", true, false, List.of(ADA, BOLA), 4)).isEmpty();
        assertThat(policy.decide("draughts", true, false, List.of(ADA, BOLA), 5))
                .contains(UnrankedReason.REPEAT_OPPONENT);
    }

    @Test
    @DisplayName("rated games are configurable, so Chess is a config change once its module exists")
    void ratedGamesAreConfigurable() {
        RatedMatchPolicy withChess = new RatedMatchPolicy(new CompetitiveSettings("draughts, chess", 10, 5, 30, 3));
        assertThat(withChess.decide("chess", true, false, List.of(ADA, BOLA), 0)).isEmpty();
    }
}
