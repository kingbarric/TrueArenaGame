package app.truearena.game.truearena;

import app.truearena.engine.ConfigVocab;
import app.truearena.engine.GameConfig;
import app.truearena.engine.GameEvent;
import app.truearena.engine.GameRunner;
import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * One test per bug found in the October 2026 Traitors audit. Each drives the
 * real engine through the phases a table would, and fails on the old code.
 */
class TraitorsAuditTest {

    private final TrueArenaModule module = new TrueArenaModule();
    private final GameRunner runner = new GameRunner(module);

    // ---------------------------------------------------------------- fixtures

    private static List<String> ids(int n) {
        return java.util.stream.IntStream.rangeClosed(1, n).mapToObj(i -> "p" + i).toList();
    }

    /** A config with the knobs these tests turn; everything else is Classic. */
    private static GameConfig cfg(int traitors, GameConfig.NightKill nk, String reveal, String tieBreak,
                                  String afk, String voteReveal, String veil,
                                  Map<String, Map<String, Object>> twists) {
        return new GameConfig(ConfigVocab.CATALOG_VERSION, "custom",
                new GameConfig.Table(8, 4, 20, true, List.of(List.of(4, traitors))),
                new GameConfig.Timers(60, 300, 60, 60),
                nk, reveal, tieBreak, "no_elimination", 30, afk, voteReveal, veil, twists);
    }

    private static GameConfig.NightKill nightKill() {
        return new GameConfig.NightKill("on", null, false, false);
    }

    private static GameConfig plain(String tieBreak) {
        return cfg(2, nightKill(), "always", tieBreak, "abstain", "sequential", "off", Map.of());
    }

    private GameState apply(GameState s, String actor, String type, Map<String, Object> data) {
        return runner.apply(s, PlayerAction.of(actor, type, data)).state();
    }

    private GameState elapse(GameState s) {
        return runner.elapse(s, s.phase()).state();
    }

    /** RoleReveal → a quiet Night (nobody picks) → Morning → RoundTable. */
    private GameState toRoundTable(GameState s) {
        while (!"RoundTable".equals(s.phase())) {
            s = elapse(s);
        }
        return s;
    }

    private GameState toVote(GameState s) {
        return elapse(toRoundTable(s));
    }

    private GameState votes(GameState s, Map<String, String> ballots) {
        for (Map.Entry<String, String> b : ballots.entrySet()) {
            s = apply(s, b.getKey(), "CAST_VOTE", Map.of("target", b.getValue()));
        }
        return s;
    }

    private static TruearenaState ts(GameState s) {
        return (TruearenaState) s;
    }

    private static List<String> alive(GameState s) {
        return List.copyOf(ts(s).alive);
    }

    private static List<GameEvent> eventsOfType(GameState s, String type) {
        return s.events().stream().filter(e -> e.type().equals(type)).toList();
    }

    /** A 2-2 tie between the first two living players (6 alive, nobody voting for themselves). */
    private static Map<String, String> tieBallots(List<String> a) {
        Map<String, String> b = new LinkedHashMap<>();
        b.put(a.get(2), a.get(0));
        b.put(a.get(3), a.get(0));
        b.put(a.get(4), a.get(1));
        b.put(a.get(5), a.get(1));
        b.put(a.get(0), a.get(2));
        b.put(a.get(1), a.get(3));
        return b;
    }

    // ---------------------------------------------------------------- ties

    @Test
    @DisplayName("'Trial of two' picked as the tie rule gives the tied players their defense (it skipped straight to sudden death)")
    void trialOfTwoAsTieRule() {
        GameState s = toVote(module.initialState(ids(6), plain("trial_of_two"), RandomSource.seeded(3)));
        List<String> a = alive(s);
        s = votes(s, tieBallots(a));
        s = elapse(s); // VoteReview → Elimination
        s = elapse(s); // tally → tie

        assertThat(s.phase()).isEqualTo("Defense");
        assertThat(ts(s).tieCandidates).containsExactlyInAnyOrder(a.get(0), a.get(1));
        assertThat(module.playersToAct(s)).containsExactlyInAnyOrder(a.get(0), a.get(1));

        s = elapse(s); // defense over → the final vote between the two
        assertThat(s.phase()).isEqualTo("Vote");
        assertThat(eventsOfType(s, "FINAL_VOTE_OPEN")).hasSize(1);
    }

    // ---------------------------------------------------------------- AFK + all-at-once

    @Test
    @DisplayName("With 'host assigns' AFK and all-at-once reveal, an AFK timeout no longer stalls in VoteReview")
    void hostAssignsThenAllAtOnceDoesNotStall() {
        GameConfig c = cfg(2, nightKill(), "always", "revote", "host_assigns", "all_at_once", "off", Map.of());
        GameState s = toVote(module.initialState(ids(6), c, RandomSource.seeded(4)));
        List<String> a = alive(s);
        for (int i = 1; i < a.size(); i++) {
            s = apply(s, a.get(i), "CAST_VOTE", Map.of("target", a.get(0)));
        }
        s = elapse(s); // vote timer: one missing → host gets to assign
        assertThat(s.phase()).isEqualTo("HostAssignVotes");

        GameState timedOut = elapse(s);
        assertThat(timedOut.phase()).isEqualTo("Elimination");
        assertThat(eventsOfType(timedOut, "VOTE_REVEALED")).hasSize(5);

        GameState assigned = apply(s, "host", "HOST_ASSIGN_VOTE", Map.of("voterId", a.get(0), "target", a.get(1)));
        assertThat(assigned.phase()).isEqualTo("Elimination");
    }

    // ---------------------------------------------------------------- immunity coin

    private GameState immunityGame(long seed) {
        GameConfig c = cfg(1, nightKill(), "always", "revote", "abstain", "sequential", "off",
                Map.of("immunity_coin", Map.of()));
        return toRoundTable(module.initialState(ids(6), c, RandomSource.seeded(seed)));
    }

    /** Everyone (except the target) votes for {@code target}; the target votes for {@code other}. */
    private GameState banishVote(GameState s, String target, String other) {
        for (String voter : alive(s)) {
            s = apply(s, voter, "CAST_VOTE", Map.of("target", voter.equals(target) ? other : target));
        }
        return s;
    }

    @Test
    @DisplayName("A spent immunity coin covers that one elimination, and the game's coin can't be awarded twice")
    void immunityIsOneUse() {
        GameState s = immunityGame(5);
        List<String> a = alive(s);
        String holder = a.get(0);
        s = apply(s, "host", "AWARD_IMMUNITY", Map.of("target", holder));
        s = elapse(s); // → Vote

        // Banish someone else while the holder has spent the coin.
        String other = ts(s).aliveFaithful().stream().filter(id -> !id.equals(holder)).findFirst().orElseThrow();
        s = banishVote(s, other, holder);
        s = apply(s, holder, "USE_IMMUNITY", Map.of());
        s = elapse(s); // VoteReview → Elimination
        s = elapse(s); // tally → banish `other`
        assertThat(ts(s).alive).doesNotContain(other);
        assertThat(ts(s).immunityHolder).as("spent coin expires with that elimination").isNull();
        assertThat(ts(s).immunityConsumed).isTrue();

        if (!s.finished()) {
            GameState next = toRoundTable(elapse(s));
            assertThatThrownBy(() -> apply(next, "host", "AWARD_IMMUNITY", Map.of("target", holder)))
                    .isInstanceOf(RuleViolation.class).hasMessageContaining("already been awarded");
        }
    }

    @Test
    @DisplayName("After the coin blocks a banishment it is gone for good — it used to reset and could be re-awarded")
    void blockedBanishConsumesTheCoin() {
        GameState s = immunityGame(6);
        String holder = ts(s).aliveFaithful().getFirst();
        s = apply(s, "host", "AWARD_IMMUNITY", Map.of("target", holder));
        s = elapse(s);
        String other = alive(s).stream().filter(id -> !id.equals(holder)).findFirst().orElseThrow();
        s = banishVote(s, holder, other);
        s = apply(s, holder, "USE_IMMUNITY", Map.of());
        s = elapse(s);
        s = elapse(s);

        assertThat(eventsOfType(s, "IMMUNITY_BLOCKED_BANISH")).hasSize(1);
        assertThat(ts(s).alive).contains(holder);
        assertThat(ts(s).immunityConsumed).isTrue();
        assertThat(module.broadcastState(s).data()).containsEntry("immunityAvailable", false);
    }

    // ---------------------------------------------------------------- hidden legacy

    @Test
    @DisplayName("Hidden Legacy recruits when the last Traitor dies to poison overnight (the game used to just end)")
    void hiddenLegacyAppliesToNightDeaths() {
        GameConfig c = cfg(1, nightKill(), "always", "revote", "abstain", "sequential", "off",
                Map.of("hidden_legacy", Map.of(), "poisoned_gift", Map.of("uses", 1)));
        GameState start = null;
        String traitor = null;
        // Find a seed whose round-1 shield comes up poisoned. Seeds are spread out the
        // way production's random 64-bit seeds are: java.util.Random's first output is
        // correlated across neighbouring seeds (1, 2, 3…), which would make this search
        // see the same coin flip every time.
        for (long i = 1; i < 200 && start == null; i++) {
            long seed = i * 0x9E3779B97F4A7C15L;
            GameState s = elapse(module.initialState(ids(6), c, RandomSource.seeded(seed))); // → Night
            String t = ts(s).aliveTraitors().getFirst();
            GameState gifted = apply(s, t, "NIGHT_GIFT", Map.of("choice", "shield"));
            if (ts(gifted).shieldPoisoned) {
                start = gifted;
                traitor = t;
            }
        }
        assertThat(start).as("some seed yields a poisoned shield").isNotNull();

        GameState s = toRoundTable(start);
        s = apply(s, traitor, "CLAIM_SHIELD", Map.of()); // the Traitor poisons themself
        s = elapse(s); // → Vote
        s = elapse(s); // nobody votes → abstain → VoteReview
        while (!"Night".equals(s.phase())) {
            s = elapse(s);
        }
        assertThat(s.round()).isEqualTo(2);
        s = elapse(s); // night 2: the poison lands

        assertThat(ts(s).alive).doesNotContain(traitor);
        assertThat(s.finished()).as("before round 3 the legacy recruits instead of ending").isFalse();
        assertThat(ts(s).roles).containsValue(TruearenaState.RECRUITED);
        assertThat(s.phase()).isEqualTo("MorningReveal");
    }

    // ---------------------------------------------------------------- poison

    @Test
    @DisplayName("Two pending poisons both land — a second one used to overwrite the first")
    void twoPoisonsBothLand() {
        GameConfig c = cfg(2, nightKill(), "always", "revote", "abstain", "sequential", "off",
                Map.of("poisoned_gift", Map.of("uses", 2)));
        GameState s = elapse(module.initialState(ids(8), c, RandomSource.seeded(7)));
        String traitor = ts(s).aliveTraitors().getFirst();
        List<String> faithful = ts(s).aliveFaithful();
        s = apply(s, traitor, "NIGHT_GIFT", Map.of("choice", "direct_poison", "target", faithful.get(0)));
        s = apply(s, traitor, "NIGHT_GIFT", Map.of("choice", "direct_poison", "target", faithful.get(1)));
        while (!("Night".equals(s.phase()) && s.round() == 2)) {
            s = elapse(s);
        }
        s = elapse(s);

        assertThat(ts(s).alive).doesNotContain(faithful.get(0), faithful.get(1));
        assertThat(ts(s).eliminationCause).containsEntry(faithful.get(0), "poison").containsEntry(faithful.get(1), "poison");
    }

    // ---------------------------------------------------------------- false reveal

    @Test
    @DisplayName("False Reveal, armed during the day, hides the banished Faithful's role at the moment it is announced")
    void falseRevealHidesTheRoleAsItIsAnnounced() {
        GameConfig c = cfg(2, nightKill(), "always", "revote", "abstain", "sequential", "off",
                Map.of("false_reveal", Map.of("uses", 1)));
        GameState s = toVote(module.initialState(ids(6), c, RandomSource.seeded(8)));
        String traitor = ts(s).aliveTraitors().getFirst();
        String victim = ts(s).aliveFaithful().getFirst();

        s = apply(s, traitor, "FALSE_REVEAL", Map.of());
        GameEvent armed = eventsOfType(s, "FALSE_REVEAL_ARMED").getFirst();
        assertThat(armed.visibility().isPublic()).as("only the Traitors know").isFalse();

        s = banishVote(s, victim, traitor);
        s = elapse(s);
        s = elapse(s);

        GameEvent eliminated = eventsOfType(s, "PLAYER_ELIMINATED").getLast();
        assertThat(eliminated.payload()).containsEntry("id", victim).containsEntry("roleShown", false);
        assertThat(eliminated.payload().get("role")).isNull();
        assertThat(ts(s).falseRevealUses).isZero();
        assertThat(ts(s).falseRevealArmed).isFalse();
    }

    // ---------------------------------------------------------------- veiled ballots

    @Test
    @DisplayName("Ballots hidden by the veiled endgame are released at Results")
    void veiledBallotsAreReleasedAtTheEnd() {
        GameConfig c = cfg(1, nightKill(), "always", "revote", "abstain", "sequential", "final_6", Map.of());
        GameState s = toVote(module.initialState(ids(6), c, RandomSource.seeded(9)));
        String traitor = ts(s).aliveTraitors().getFirst();
        String someone = ts(s).aliveFaithful().getFirst();
        s = banishVote(s, traitor, someone);
        while (!s.finished()) {
            s = elapse(s);
        }

        assertThat(eventsOfType(s, "VOTE_REVEALED")).as("veiled at the time").isEmpty();
        Map<String, Object> reveal = eventsOfType(s, "FULL_REVEAL").getFirst().payload();
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> ballots = (List<Map<String, Object>>) reveal.get("ballots");
        assertThat(ballots).hasSize(1);
        assertThat(ballots.getFirst()).containsEntry("round", 1).containsEntry("veiled", true);
        @SuppressWarnings("unchecked")
        Map<String, String> cast = (Map<String, String>) ballots.getFirst().get("votes");
        assertThat(cast).hasSize(6).containsEntry(someone, traitor);
    }

    // ---------------------------------------------------------------- night: skip, picks, flags

    @Test
    @DisplayName("Traitors can see each other's picks at night; nobody else can")
    void traitorsSeeEachOthersPicks() {
        GameConfig c = cfg(2, new GameConfig.NightKill("on", null, false, true), "always", "revote",
                "abstain", "sequential", "off", Map.of());
        GameState s = elapse(module.initialState(ids(8), c, RandomSource.seeded(10)));
        List<String> traitors = ts(s).aliveTraitors();
        String target = ts(s).aliveFaithful().getFirst();
        s = apply(s, traitors.get(0), "NIGHT_TARGET", Map.of("target", target));

        Map<String, Object> partner = module.visibleStateFor(s, traitors.get(1)).data();
        assertThat(partner.get("nightPicks")).isEqualTo(Map.of(traitors.get(0), target));
        assertThat(module.visibleStateFor(s, target).data()).doesNotContainKey("nightPicks");
        assertThat(module.broadcastState(s).data()).doesNotContainKey("nightPicks");
    }

    @Test
    @DisplayName("A used skip only reports 'skipped' on the night it was used")
    void skipReasonIsPerNight() {
        GameConfig c = cfg(2, new GameConfig.NightKill("on", 2, true, false), "always", "revote",
                "abstain", "sequential", "off", Map.of());
        GameState s = elapse(module.initialState(ids(8), c, RandomSource.seeded(11)));
        String traitor = ts(s).aliveTraitors().getFirst();
        assertThat(module.visibleStateFor(s, traitor).data())
                .containsEntry("canSkipNight", true)
                .containsEntry("doubleMurderAvailable", false);
        s = apply(s, traitor, "NIGHT_SKIP", Map.of());
        assertThat(eventsOfType(s, "NO_MURDER").getLast().payload()).containsEntry("reason", "skipped");

        while (!("Night".equals(s.phase()) && s.round() == 2)) {
            s = elapse(s);
        }
        assertThat(module.visibleStateFor(s, traitor).data()).containsEntry("canSkipNight", false);
        s = elapse(s); // nobody picks on night 2
        assertThat(eventsOfType(s, "NO_MURDER").getLast().payload()).containsEntry("reason", "no_target");
    }

    @Test
    @DisplayName("The table's rules are public, so the app stops guessing from the preset name")
    void rulesArePublic() {
        GameConfig c = cfg(2, new GameConfig.NightKill("on", 2, true, false), "always", "trial_of_two",
                "host_assigns", "all_at_once", "off", Map.of("immunity_coin", Map.of()));
        GameState s = module.initialState(ids(8), c, RandomSource.seeded(12));
        @SuppressWarnings("unchecked")
        Map<String, Object> rules = (Map<String, Object>) module.broadcastState(s).data().get("rules");
        assertThat(rules)
                .containsEntry("twists", List.of("immunity_coin"))
                .containsEntry("allowSkip", true)
                .containsEntry("doubleAfterRound", 2)
                .containsEntry("afk", "host_assigns")
                .containsEntry("voteReveal", "all_at_once")
                .containsEntry("tieBreak", "trial_of_two");
        assertThat(module.broadcastState(s).data()).containsEntry("immunityAvailable", true);
    }

    // ---------------------------------------------------------------- accusation

    @Test
    @DisplayName("The accused is the one asked to act in Defense, and the accusation clears with nightfall")
    void accusationLifecycle() {
        GameConfig c = Presets.FINAL_GAMBIT.config();
        GameState s = toRoundTable(module.initialState(ids(6), c, RandomSource.seeded(13)));
        String accuser = ts(s).accuser;
        String accused = alive(s).stream().filter(id -> !id.equals(accuser)).findFirst().orElseThrow();
        s = apply(s, accuser, "ACCUSE", Map.of("target", accused));
        assertThat(s.phase()).isEqualTo("Defense");
        assertThat(module.playersToAct(s)).containsExactly(accused);

        s = elapse(s); // → Vote
        assertThat(s.phase()).isEqualTo("Vote");
        while (!s.finished() && !"Night".equals(s.phase())) {
            s = elapse(s);
        }
        if (!s.finished()) {
            assertThat(ts(s).accused).isNull();
        }
    }

    // ---------------------------------------------------------------- validation

    @Test
    @DisplayName("Silent Witness counts toward the special-Faithful budget the validator warns about")
    void silentWitnessUsesASpecialSlot() {
        GameConfig c = new GameConfig(ConfigVocab.CATALOG_VERSION, "custom",
                new GameConfig.Table(5, 5, 8, false, List.of(List.of(5, 1))),
                new GameConfig.Timers(60, 300, 60, 60), nightKill(), "always", "revote", "no_elimination",
                30, "abstain", "sequential", "off",
                Map.of("secret_accusation", Map.of(), "blackmail", Map.of(), "double_agent", Map.of(),
                        "silent_witness", Map.of()));
        // 5 players, 1 traitor → 3 special Faithful available; four twists want one each.
        assertThat(ConfigValidator.validate(c).warnings()).anyMatch(w -> w.contains("need 4 special Faithful"));
    }

    @Test
    @DisplayName("Every preset still plays to a clean result under the fixes")
    void presetsStillTerminate() {
        for (Presets.Mode mode : Presets.ALL) {
            for (long seed = 1; seed <= 25; seed++) {
                AutoPlay.Result r = AutoPlay.run(mode.config(), mode.config().table().minPlayers(), seed);
                assertThat(r.winningSide()).as(mode.slug() + " seed " + seed).isIn("faithful", "traitors");
            }
        }
    }
}
