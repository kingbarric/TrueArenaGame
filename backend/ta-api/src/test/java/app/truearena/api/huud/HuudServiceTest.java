package app.truearena.api.huud;

import app.truearena.api.huud.HuudDtos.FeedItem;
import app.truearena.api.huud.HuudDtos.OpenGame;
import app.truearena.api.huud.HuudDtos.PersonView;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class HuudServiceTest {

    @Test
    void streakCountsOnlyTheWinsAtTheFront() {
        assertThat(HuudService.streakOf(List.of("won", "won", "won", "lost", "won"))).isEqualTo(3);
        assertThat(HuudService.streakOf(List.of("lost", "won"))).isZero();
        assertThat(HuudService.streakOf(List.of("won", "tied", "won"))).isEqualTo(1);
        assertThat(HuudService.streakOf(List.of())).isZero();
    }

    @Test
    void headToHeadGamesAlwaysSeatTwo() {
        assertThat(HuudService.seatsFor("draughts", 6)).isEqualTo(2);
        assertThat(HuudService.seatsFor("chess", null)).isEqualTo(2);
        assertThat(HuudService.seatsFor("goosi", 3)).isEqualTo(2);
    }

    @Test
    void tableGamesDefaultToTheirNaturalSizeAndClamp() {
        assertThat(HuudService.seatsFor("whot", null)).isEqualTo(4);
        assertThat(HuudService.seatsFor("whot", 9)).isEqualTo(9);
        assertThat(HuudService.seatsFor("whot", 40)).isEqualTo(16);
        assertThat(HuudService.seatsFor("whot", 1)).isEqualTo(2);
        assertThat(HuudService.seatsFor("ludo", 6)).isEqualTo(4);
        assertThat(HuudService.seatsFor("truearena", null)).isEqualTo(6);
    }

    @Test
    void wordBluffAcceptsTheAppsShortName() {
        assertThat(HuudService.gameTypeOf("bluff")).isEqualTo("wordbluff");
        assertThat(HuudService.gameTypeOf(" Draughts ")).isEqualTo("draughts");
        assertThatThrownBy(() -> HuudService.gameTypeOf("poker")).isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(() -> HuudService.gameTypeOf(null)).isInstanceOf(ResponseStatusException.class);
    }

    @Test
    void blankMessagesBecomeNoMessage() {
        assertThat(HuudService.cleanMessage("   ")).isNull();
        assertThat(HuudService.cleanMessage(null)).isNull();
        assertThat(HuudService.cleanMessage("  Winner stays on.  ")).isEqualTo("Winner stays on.");
        assertThat(HuudService.cleanMessage("x".repeat(400))).hasSize(280);
    }

    @Test
    void aChallengeWaitingOnTheViewerSortsAboveNewerCards() {
        UUID me = UUID.randomUUID();
        UUID tobi = UUID.randomUUID();
        Instant t0 = Instant.parse("2026-10-07T10:00:00Z");
        FeedItem olderChallenge = challenge(tobi, me, t0);
        FeedItem newerWin = new FeedItem("win", "w", t0.plusSeconds(600), person(tobi), "whot", null, null, null, null, null);
        FeedItem myOwnChallenge = challenge(me, tobi, t0.plusSeconds(900));

        List<FeedItem> items = new ArrayList<>(List.of(newerWin, myOwnChallenge, olderChallenge));
        items.sort(HuudService.feedOrder(me));

        assertThat(items).containsExactly(olderChallenge, myOwnChallenge, newerWin);
    }

    private static FeedItem challenge(UUID from, UUID to, Instant at) {
        OpenGame game = new OpenGame(UUID.randomUUID(), UUID.randomUUID(), "ABCDEF", false, 1, 2,
                List.of(person(from)), at.plusSeconds(600), false, false, person(to), null, false);
        return new FeedItem("challenge", "c" + at, at, person(from), "whot", null, game, null, null, null);
    }

    private static PersonView person(UUID id) {
        return new PersonView(id, "Name", "name", null, true);
    }
}
