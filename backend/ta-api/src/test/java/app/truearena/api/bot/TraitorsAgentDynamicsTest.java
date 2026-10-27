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

    @Test void aFaithfulAgentVotesForWhoeverTheTableKeepsNaming() {
        TrueArenaBotAdapter agent = agent("bot-1", "faithful", List.of(), eager());
        agent.playerNames(Map.of("alice", "Alice", "bob", "Bob", "carol", "Carol", "dan", "Dan", "bot-2", "Rex"));
        sees(agent, "bot-1", table("RoundTable", "faithful", PLAYERS, Map.of()));
        for (String line : List.of("I don't trust Carol at all", "Carol changed her story twice", "Agreed, Carol is shady")) {
            agent.onFrame("EVENT", event("CHAT_MESSAGE", Map.of("from", "alice", "channel", "table", "text", line)), "bot-1", LEVEL);
        }
        PlayerAction vote = sees(agent, "bot-1", table("Vote", "faithful", PLAYERS, Map.of())).orElseThrow();
        assertThat(vote.type()).isEqualTo("CAST_VOTE");
        assertThat(vote.data()).containsEntry("target", "carol");
    }

    // ---------------------------------------------------------------- reading the table like a person

    private static final Map<String, String> NAMES = Map.of("alice", "Alice", "bob", "Bob", "carol", "Carol",
            "dan", "Dan", "bot-1", "Nova", "bot-2", "Rex");

    /** Goes with the table's talk, and takes every chance to speak up. */
    private static Random followsTheTable() {
        return new Random(7) {
            @Override public double nextDouble() { return 0.0; }
            @Override public int nextInt(int bound) { return bound - 1; }
        };
    }

    private static Map<String, Object> chat(String from, String text) {
        return event("CHAT_MESSAGE", Map.of("from", from, "channel", "table", "text", text));
    }

    private static void at(TrueArenaBotAdapter agent, String phase, int round) {
        agent.onFrame("PHASE", Map.of("phase", phase, "round", round), "bot-1", LEVEL);
    }

    private static void ballot(TrueArenaBotAdapter agent, String voter, String target) {
        agent.onFrame("EVENT", event("VOTE_REVEALED", Map.of("voter", voter, "target", target)), "bot-1", LEVEL);
    }

    private static void out(TrueArenaBotAdapter agent, String id, String role) {
        Map<String, Object> data = new HashMap<>();
        data.put("id", id);
        data.put("cause", "banish");
        data.put("roleShown", role != null);
        data.put("role", role);
        agent.onFrame("EVENT", event("PLAYER_ELIMINATED", data), "bot-1", LEVEL);
    }

    @Test void standingUpForSomeoneIsHeard_butNotDistrust() {
        assertThat(TrueArenaBotAdapter.vouchesFor("Leave Carol alone, she's been fine", "Carol")).isTrue();
        assertThat(TrueArenaBotAdapter.vouchesFor("I trust Carol, honestly", "Carol")).isTrue();
        assertThat(TrueArenaBotAdapter.vouchesFor("Carol is solid.", "Carol")).isTrue();
        assertThat(TrueArenaBotAdapter.vouchesFor("I don't trust Carol at all", "Carol")).isFalse();
        assertThat(TrueArenaBotAdapter.vouchesFor("Not saying it's Carol… but it's probably Carol.", "Carol")).isFalse();
    }

    @Test void onceATraitorIsUnmasked_whoeverKeptVotingWithThemIsNext() {
        TrueArenaBotAdapter agent = agent("bot-1", "faithful", List.of(), eager());
        agent.playerNames(NAMES);
        sees(agent, "bot-1", table("RoundTable", "faithful", PLAYERS, Map.of()));
        at(agent, "VoteReview", 1);
        ballot(agent, "carol", "bob");
        ballot(agent, "dan", "bob");
        ballot(agent, "alice", "carol");
        ballot(agent, "bot-2", "dan");
        out(agent, "bob", null);
        at(agent, "VoteReview", 2);
        ballot(agent, "carol", "alice");
        ballot(agent, "dan", "alice");
        ballot(agent, "alice", "carol");
        ballot(agent, "bot-2", "carol");
        out(agent, "carol", "traitor");
        List<String> left = List.of("alice", "bot-1", "bot-2", "dan");
        PlayerAction vote = sees(agent, "bot-1", table("Vote", "faithful", left, Map.of("round", 3))).orElseThrow();
        assertThat(vote.data()).containsEntry("target", "dan");
    }

    @Test void whoeverVouchedForAnUnmaskedTraitorIsRemembered() {
        TrueArenaBotAdapter agent = agent("bot-1", "faithful", List.of(), eager());
        agent.playerNames(NAMES);
        sees(agent, "bot-1", table("RoundTable", "faithful", PLAYERS, Map.of()));
        agent.onFrame("EVENT", chat("dan", "Leave Carol alone, she's been with us all game."), "bot-1", LEVEL);
        at(agent, "VoteReview", 2);
        out(agent, "carol", "traitor");
        List<String> left = List.of("alice", "bob", "bot-1", "bot-2", "dan");
        PlayerAction vote = sees(agent, "bot-1", table("Vote", "faithful", left, Map.of("round", 3))).orElseThrow();
        assertThat(vote.data()).containsEntry("target", "dan");
    }

    @Test void aTraitorAgentSometimesCoversForAFellowTraitor_thatsTheSlip() {
        Map<String, Object> roundTable = table("RoundTable", "traitor", PLAYERS, Map.of("fellowTraitors", List.of("bot-2")));
        TrueArenaBotAdapter slips = agent("bot-1", "traitor", List.of("bot-2"), eager());
        slips.playerNames(NAMES);
        sees(slips, "bot-1", roundTable);
        String said = slips.onFrame("EVENT", chat("alice", "I'm telling you, Rex is the Traitor."), "bot-1", LEVEL)
                .orElseThrow().fallback();
        assertThat(TrueArenaBotAdapter.vouchesFor(said, "Rex")).as(said).isTrue();

        TrueArenaBotAdapter careful = agent("bot-1", "traitor", List.of("bot-2"), reluctant());
        careful.playerNames(NAMES);
        sees(careful, "bot-1", roundTable);
        careful.onFrame("EVENT", chat("alice", "I'm telling you, Rex is the Traitor."), "bot-1", LEVEL)
                .ifPresent(p -> assertThat(TrueArenaBotAdapter.vouchesFor(p.fallback(), "Rex")).as(p.fallback()).isFalse());
    }

    @Test void aFaithfulAgentSpeaksUpForSomeoneItsOwnEvidenceClears() {
        TrueArenaBotAdapter agent = agent("bot-1", "faithful", List.of(), eager());
        agent.playerNames(NAMES);
        sees(agent, "bot-1", table("RoundTable", "faithful", PLAYERS, Map.of()));
        agent.onFrame("EVENT", event("LANTERN_VISION", Map.of("target", "bob", "side", "faithful")), "bot-1", LEVEL);
        String said = agent.onFrame("EVENT", chat("alice", "Bob has been lying all game."), "bot-1", LEVEL)
                .orElseThrow().fallback();
        assertThat(TrueArenaBotAdapter.vouchesFor(said, "Bob")).as(said).isTrue();
    }

    @Test void whenTheTableSettlesOnAName_anAgentCallsEveryoneTogether() {
        TrueArenaBotAdapter agent = agent("bot-1", "faithful", List.of(), followsTheTable());
        agent.playerNames(NAMES);
        sees(agent, "bot-1", table("RoundTable", "faithful", PLAYERS, Map.of()));
        agent.onFrame("EVENT", chat("alice", "Dan dodged my question twice."), "bot-1", LEVEL);
        agent.onFrame("EVENT", chat("bob", "Agreed, Dan is acting strange."), "bot-1", LEVEL);
        String said = agent.onFrame("EVENT", chat("carol", "So what does everyone think?"), "bot-1", LEVEL)
                .orElseThrow().fallback();
        assertThat(said).contains("Dan").containsAnyOf("split the vote", "my vote", "stick together", "scatter our votes");
    }

    @Test void aTraitorAgentMayJoinThePileOnADoomedFellow_toLookClean() {
        Map<String, Object> roundTable = table("RoundTable", "traitor", PLAYERS, Map.of("fellowTraitors", List.of("carol")));
        List<String> lines = List.of("Carol is lying", "Yes, Carol for sure", "It's Carol, obviously");
        TrueArenaBotAdapter bus = agent("bot-1", "traitor", List.of("carol"), eager());
        bus.playerNames(NAMES);
        sees(bus, "bot-1", roundTable);
        for (int i = 0; i < lines.size(); i++) {
            bus.onFrame("EVENT", chat(List.of("alice", "bob", "dan").get(i), lines.get(i)), "bot-1", LEVEL);
        }
        Map<String, Object> vote = table("Vote", "traitor", PLAYERS, Map.of("fellowTraitors", List.of("carol")));
        assertThat(sees(bus, "bot-1", vote).orElseThrow().data()).containsEntry("target", "carol");

        TrueArenaBotAdapter loyal = agent("bot-1", "traitor", List.of("carol"), reluctant());
        loyal.playerNames(NAMES);
        sees(loyal, "bot-1", roundTable);
        for (int i = 0; i < lines.size(); i++) {
            loyal.onFrame("EVENT", chat(List.of("alice", "bob", "dan").get(i), lines.get(i)), "bot-1", LEVEL);
        }
        assertThat(sees(loyal, "bot-1", vote).orElseThrow().data().get("target")).isNotEqualTo("carol");
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
