package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;
import app.truearena.game.truearena.TrueArenaModule;
import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Random;

import static org.assertj.core.api.Assertions.assertThat;

/** Cyber Agents play the dynamics: recruit, bake, mark, give alibis, answer offers, sit on the jury. */
class TraitorsAgentDynamicsTest {

    private static final List<String> PLAYERS = List.of("alice", "bob", "bot-1", "bot-2", "carol", "dan");
    private static final Difficulty LEVEL = Difficulty.MEDIUM;

    /** Takes every chance going. */
    private static Random eager() {
        return new Random(3) {
            @Override public double nextDouble() { return 0.0; }
            @Override public int nextInt(int bound) { return 0; }
            @Override public boolean nextBoolean() { return false; }
        };
    }

    /** Passes on every chance it can. */
    private static Random reluctant() {
        return new Random(5) {
            @Override public double nextDouble() { return 0.99; }
            @Override public int nextInt(int bound) { return bound - 1; }
            @Override public boolean nextBoolean() { return false; }
        };
    }

    private static Map<String, Object> event(String type, Map<String, Object> data) {
        return Map.of("type", type, "data", data);
    }

    private static TrueArenaBotAdapter agent(String me, String role, List<String> fellows, Random random) {
        TrueArenaBotAdapter agent = new TrueArenaBotAdapter(random);
        agent.onFrame("EVENT", event("GAME_STARTED", Map.of("players", PLAYERS)), me, LEVEL);
        agent.onFrame("EVENT", event("ROLE_ASSIGNED", Map.of("role", role)), me, LEVEL);
        agent.onFrame("EVENT", event("FELLOW_TRAITORS", Map.of("ids", fellows)), me, LEVEL);
        return agent;
    }

    private static Map<String, Object> table(String phase, String role, List<String> alive, Map<String, Object> extra) {
        Map<String, Object> s = new HashMap<>();
        s.put("phase", phase);
        s.put("round", 2);
        s.put("yourRole", role);
        s.put("alive", alive);
        s.put("botPlayerIds", List.of("bot-1", "bot-2"));
        s.putAll(extra);
        return s;
    }

    /** What the agent does with this view of the table, if anything. */
    private static Optional<PlayerAction> sees(TrueArenaBotAdapter agent, String me, Map<String, Object> snapshot) {
        var prompt = agent.onFrame("SNAPSHOT", snapshot, me, LEVEL);
        return prompt.isPresent() && !prompt.get().speak() ? agent.decideLocally(me, LEVEL) : Optional.empty();
    }

    @Test void theLeadTraitorAgentRecruitsWhenItCan_theOthersLeaveItToThem() {
        Map<String, Object> night = table("Night", "traitor", PLAYERS,
                Map.of("canRecruit", true, "recruitTargets", List.of("alice", "bob"), "fellowTraitors", List.of("bot-2")));
        PlayerAction lead = sees(agent("bot-1", "traitor", List.of("bot-2"), eager()), "bot-1", night).orElseThrow();
        assertThat(lead.type()).isEqualTo("RECRUIT_OFFER");
        assertThat(lead.data()).containsEntry("target", "alice");

        Map<String, Object> second = table("Night", "traitor", PLAYERS,
                Map.of("canRecruit", true, "recruitTargets", List.of("alice", "bob"), "fellowTraitors", List.of("bot-1")));
        PlayerAction other = sees(agent("bot-2", "traitor", List.of("bot-1"), eager()), "bot-2", second).orElseThrow();
        assertThat(other.type()).isEqualTo("NIGHT_TARGET");
    }

    @Test void onARecruitingNightTheTraitorAgentsDoNotPickAVictim() {
        Map<String, Object> night = table("Night", "traitor", PLAYERS,
                Map.of("recruitingTonight", "alice", "fellowTraitors", List.of("bot-1")));
        assertThat(sees(agent("bot-2", "traitor", List.of("bot-1"), eager()), "bot-2", night)).isEmpty();
    }

    @Test void theLeadTraitorAgentBakesThenMarks_thenPicksTheVictim() {
        TrueArenaBotAdapter agent = agent("bot-1", "traitor", List.of(), eager());
        Map<String, Object> night = table("Night", "traitor", PLAYERS, Map.of("canBakePie", true, "canPlaceSpot", true));
        PlayerAction bake = sees(agent, "bot-1", night).orElseThrow();
        assertThat(bake.type()).isEqualTo("BAKE_PIE");
        assertThat(bake.data()).containsEntry("filling", "poison");
        PlayerAction mark = sees(agent, "bot-1", night).orElseThrow();
        assertThat(mark.type()).isEqualTo("PLACE_SPOT");
        assertThat(mark.data().get("target")).isNotEqualTo("bot-1");
        assertThat(sees(agent, "bot-1", night).orElseThrow().type()).isEqualTo("NIGHT_TARGET");
    }

    @Test void everyAgentGivesAnAlibi_andTheSeerLightsTheLantern() {
        TrueArenaBotAdapter faithful = agent("bot-1", "faithful", List.of(), eager());
        PlayerAction alibi = sees(faithful, "bot-1", table("Night", "faithful", PLAYERS, Map.of("alibiNeeded", true))).orElseThrow();
        assertThat(alibi.type()).isEqualTo("ALIBI");
        assertThat(PLAYERS).contains((String) alibi.data().get("with"));
        assertThat(alibi.data().get("with")).isNotEqualTo("bot-1");

        TrueArenaBotAdapter seer = agent("bot-2", "faithful", List.of(), eager());
        PlayerAction lantern = sees(seer, "bot-2", table("Night", "faithful", PLAYERS,
                Map.of("seer", Map.of("canLight", true, "lanternUsed", false, "visions", Map.of())))).orElseThrow();
        assertThat(lantern.type()).isEqualTo("SEER_LANTERN");
        assertThat(lantern.data()).containsKey("target");
    }

    @Test void anOfferIsAnswered_eagerlyAccepted_orReluctantlyRefused() {
        Map<String, Object> morning = table("MorningReveal", "faithful", PLAYERS, Map.of("recruitOffer", true));
        PlayerAction yes = sees(agent("bot-1", "faithful", List.of(), eager()), "bot-1", morning).orElseThrow();
        assertThat(yes.type()).isEqualTo("RECRUIT_ANSWER");
        assertThat(yes.data()).containsEntry("accept", true);
        PlayerAction no = sees(agent("bot-1", "faithful", List.of(), reluctant()), "bot-1", morning).orElseThrow();
        assertThat(no.data()).containsEntry("accept", false);
    }

    @Test void theBlackSpotIsPassedOnNeverBack_andItsHolderDoesNotVote() {
        TrueArenaBotAdapter holder = agent("bot-1", "faithful", List.of(), eager());
        PlayerAction pass = sees(holder, "bot-1", table("RoundTable", "faithful", PLAYERS,
                Map.of("blackSpot", Map.of("holder", "bot-1", "chain", List.of("alice", "bot-1"))))).orElseThrow();
        assertThat(pass.type()).isEqualTo("PASS_SPOT");
        assertThat(pass.data().get("to")).isNotIn("alice", "bot-1");

        TrueArenaBotAdapter silenced = agent("bot-1", "faithful", List.of(), eager());
        Map<String, Object> spot = new HashMap<>();
        spot.put("holder", "bot-1");
        spot.put("chain", List.of("bot-1"));
        spot.put("silenced", "bot-1");
        assertThat(sees(silenced, "bot-1", table("Vote", "faithful", PLAYERS, Map.of("blackSpot", spot)))).isEmpty();
    }

    @Test void aPieThatLooksHonestTempts_onethatLooksPoisonedDoesNot() {
        Map<String, Object> honest = table("RoundTable", "faithful", PLAYERS,
                Map.of("pie", Map.of("available", true, "clue", TrueArenaModule.SHIELD_CLUES.getFirst())));
        assertThat(sees(agent("bot-1", "faithful", List.of(), eager()), "bot-1", honest).orElseThrow().type()).isEqualTo("TAKE_PIE");
        Map<String, Object> suspect = table("RoundTable", "faithful", PLAYERS,
                Map.of("pie", Map.of("available", true, "clue", TrueArenaModule.POISON_CLUES.getFirst())));
        assertThat(sees(agent("bot-1", "faithful", List.of(), reluctant()), "bot-1", suspect)).isEmpty();
    }

    @Test void agentsWhoAreOutSitOnTheJury_andJoinTheCrowd() {
        List<String> stillIn = PLAYERS.stream().filter(id -> !id.equals("bot-1")).toList();
        PlayerAction verdict = sees(agent("bot-1", "faithful", List.of(), eager()), "bot-1",
                table("GhostJury", "faithful", stillIn, Map.of("ghostJuror", true, "tieCandidates", List.of("alice", "bob")))).orElseThrow();
        assertThat(verdict.type()).isEqualTo("GHOST_VOTE");
        assertThat(verdict.data().get("target")).isIn("alice", "bob");

        PlayerAction hunch = sees(agent("bot-1", "faithful", List.of(), eager()), "bot-1",
                table("RoundTable", "faithful", stillIn, Map.of("canCrowdVote", true))).orElseThrow();
        assertThat(hunch.type()).isEqualTo("CROWD_VOTE");
        assertThat(stillIn).contains((String) hunch.data().get("target"));
    }
}
