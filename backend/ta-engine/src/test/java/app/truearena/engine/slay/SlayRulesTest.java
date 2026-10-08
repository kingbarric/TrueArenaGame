package app.truearena.engine.slay;

import static org.assertj.core.api.Assertions.*;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.*;

class SlayRulesTest {
    @Test
    void communityRanksWinsWithoutGivingMoreExposureAnAutomaticAdvantage() {
        var votes =
                List.of(
                        new SlayRules.Comparison("a", "b", "a"),
                        new SlayRules.Comparison("a", "c", "a"),
                        new SlayRules.Comparison("b", "c", "b"));
        var score = SlayRules.community(List.of("a", "b", "c"), votes);
        assertThat(score.get("a")).isGreaterThan(score.get("b"));
        assertThat(score.get("b")).isGreaterThan(score.get("c"));
        assertThat(SlayRules.community(List.of("a", "b"), List.of()))
                .containsEntry("a", 50.0)
                .containsEntry("b", 50.0);
    }

    private SlayCompetition battle() {
        var c = new SlayCompetition();
        c.id = "battle";
        c.mode = "battle";
        c.themeId = "first-date";
        c.members.add(new SlayCompetition.Member("a", "contestant", "female"));
        c.members.add(new SlayCompetition.Member("b", "contestant", "male"));
        return c;
    }

    private SlayCompetition.Entry entry(String user, double score) {
        return new SlayCompetition.Entry(
                user,
                user,
                "look-" + user,
                1,
                new SlayRules.Score(score, 100, 100, 100, score, 3, List.of()));
    }

    @Test
    void rejectsLateAndRepeatedSubmissions() {
        var c = battle();
        Instant now = Instant.parse("2026-10-08T12:00:00Z");
        c.start(now);
        c.submit(entry("a", 90), now.plusSeconds(5));
        assertThatThrownBy(() -> c.submit(entry("a", 90), now.plusSeconds(6)))
                .hasMessageContaining("already submitted");
        assertThatThrownBy(() -> c.submit(entry("b", 85), now.plusSeconds(180)))
                .hasMessageContaining("closed");
    }

    @Test
    void notEnoughVotesFallsBackToSystemScoreAndCannotMoveRating() {
        var c = battle();
        c.requestedRanked = true;
        Instant now = Instant.now();
        c.start(now);
        c.submit(entry("a", 90), now);
        c.submit(entry("b", 85), now);
        c.comparisons.add(new SlayRules.Comparison("a", "b", "b"));
        c.tick(now.plusSeconds(301));
        assertThat(c.status).isEqualTo("results");
        assertThat(c.eligibleRating).isFalse();
        assertThat(c.entries.get(0).placement).isEqualTo(1);
    }

    @Test
    void groupRatingRequiresEnoughExposureForEveryLook() {
        var c = new SlayCompetition();
        c.mode = "group";
        c.seats = 4;
        c.requestedRanked = true;
        for (String id : List.of("a", "b", "c", "d"))
            c.members.add(new SlayCompetition.Member(id, "contestant", "female"));
        Instant now = Instant.now();
        c.start(now);
        for (var m : c.members) c.submit(entry(m.userId(), 80), now);
        for (int i = 0; i < 8; i++) c.comparisons.add(new SlayRules.Comparison("a", "b", "a"));
        c.tick(now.plusSeconds(301));
        assertThat(c.eligibleRating).isFalse();
    }

    @Test
    void slayOrPassOnlyLetsJudgesJudgeRevealedLooksOnce() {
        var c = new SlayCompetition();
        c.mode = "slay_or_pass";
        c.seats = 4;
        for (String id : List.of("a", "b", "c", "d"))
            c.members.add(new SlayCompetition.Member(id, "contestant", "male"));
        for (String id : List.of("j1", "j2", "j3"))
            c.members.add(new SlayCompetition.Member(id, "judge", "female"));
        Instant now = Instant.now();
        c.start(now);
        for (var m : c.contestants()) c.submit(entry(m.userId(), 80), now);
        assertThatThrownBy(() -> c.judge("a", "a", true, now))
                .hasMessageContaining("Only room judges");
        assertThatThrownBy(() -> c.judge("j1", "b", true, now))
                .hasMessageContaining("not being revealed");
        c.judge("j1", "a", true, now);
        assertThatThrownBy(() -> c.judge("j1", "a", false, now))
                .hasMessageContaining("already judged");
        c.judge("j2", "a", true, now);
        c.judge("j3", "a", true, now);
        assertThat(c.revealed().id).isEqualTo("b");
        for (String id : List.of("b", "c", "d"))
            for (String judge : List.of("j1", "j2", "j3")) c.judge(judge, id, !id.equals("d"), now);
        assertThat(c.status).isEqualTo("round_result");
        assertThat(c.eliminated).containsExactly("d");
        c.tick(now.plusSeconds(9));
        assertThat(c.round).isEqualTo(2);
        assertThat(c.active()).hasSize(3);
        assertThat(c.status).isEqualTo("styling");
    }

    @Test
    void actualGroupPlacementFeedsExistingGlickoPairwiseMath() {
        assertThat(app.truearena.engine.rating.PairwiseOutcomes.score("rank:2", "rank:3"))
                .isEqualTo(1);
        assertThat(app.truearena.engine.rating.PairwiseOutcomes.score("rank:2", "rank:2"))
                .isEqualTo(.5);
        assertThat(app.truearena.engine.rating.PairwiseOutcomes.score("rank:4", "rank:1")).isZero();
    }

    @Test
    void finalTwoRequiresOneAnonymousChoicePerJudge() {
        var c = new SlayCompetition();
        c.mode = "slay_or_pass";
        c.status = "voting";
        c.round = 3;
        c.deadline = Instant.now().plusSeconds(300);
        for (String id : List.of("a", "b")) {
            c.members.add(new SlayCompetition.Member(id, "contestant", "male"));
            var e = entry(id, 80);
            e.round = 3;
            c.entries.add(e);
        }
        for (String id : List.of("j1", "j2", "j3"))
            c.members.add(new SlayCompetition.Member(id, "judge", "female"));
        Instant now = Instant.now();
        assertThatThrownBy(() -> c.judge("j1", "a", true, now)).hasMessageContaining("final two");
        c.finalVote("j1", "a", now);
        assertThatThrownBy(() -> c.finalVote("j1", "b", now)).hasMessageContaining("already chose");
        assertThatThrownBy(() -> c.finalVote("a", "a", now))
                .hasMessageContaining("Only room judges");
        c.finalVote("j2", "b", now);
        c.finalVote("j3", "a", now);
        assertThat(c.status).isEqualTo("results");
        assertThat(c.entries.get(0).placement).isEqualTo(1);
        assertThat(c.entries.get(1).placement).isEqualTo(2);
        assertThat(c.currentTheme()).isEqualTo("red-carpet");
    }

    @Test
    void everyRequestedGroupSizeCanCompleteWithoutOnlineVoters() {
        for (int size : List.of(4, 6, 8, 10, 16)) {
            var c = new SlayCompetition();
            c.mode = "group";
            c.seats = size;
            Instant now = Instant.now();
            for (int i = 0; i < size; i++)
                c.members.add(new SlayCompetition.Member("p" + i, "contestant", "female"));
            c.start(now);
            for (int i = 0; i < size; i++) c.submit(entry("p" + i, 90 - i), now);
            c.tick(now.plusSeconds(301));
            assertThat(c.status).isEqualTo("results");
            assertThat(c.entries).hasSize(size);
            assertThat(c.entries.get(size - 1).placement).isEqualTo(size);
        }
    }
}
