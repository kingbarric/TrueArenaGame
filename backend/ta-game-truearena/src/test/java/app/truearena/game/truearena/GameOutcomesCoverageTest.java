package app.truearena.game.truearena;

import app.truearena.engine.GameConfig;
import app.truearena.engine.GameEvent;
import app.truearena.engine.GameRunner;
import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Deliberately drives the engine through every <em>reachable</em> outcome and branch,
 * one scenario per test, with hand-picked actions rather than random bots — so each
 * test documents exactly which mechanic it proves and fails on the specific mechanic
 * that broke, not on "some seed somewhere stopped working".
 *
 * <p><b>Coverage map (what's here vs. what's config-only):</b> this suite exercises
 * everything {@link TrueArenaModule} actually implements: both win conditions, the
 * {@code hidden_legacy} recruit, all three {@code revealOnElimination} policies, the
 * veiled endgame, the {@code no_elimination} tie rule vs. every other tie rule (which
 * all collapse to one seeded random pick — see the note on {@link #tieBreak_nonNoElimination_resolvesRandomlyAmongTied()}),
 * AFK auto-abstain, and the full set of {@code RuleViolation}s a client can trigger.
 * It deliberately does <b>not</b> cover the 11 twists beyond {@code hidden_legacy}
 * (Poisoned Gift, Secret Accusation, Blackmail, Double Agent, Last Will, Confessional,
 * Immunity Coin, Silent Witness, False Reveal, Trial of Two, Survivors' Choice), Blood
 * Moon's double-kill-after-round, or a distinct {@code host_assigns} AFK behavior —
 * none of those have engine code to exercise yet. See docs/DEV_REFERENCE.md §7 for the
 * full audit this test file was written alongside.
 */
class GameOutcomesCoverageTest {

    private final TrueArenaModule module = new TrueArenaModule();
    private final GameRunner runner = new GameRunner(module);

    private static List<String> ids(int n) {
        return java.util.stream.IntStream.rangeClosed(1, n).mapToObj(i -> "p" + i).toList();
    }

    private GameState apply(GameState s, String actor, String type, Map<String, Object> data) {
        return runner.apply(s, PlayerAction.of(actor, type, data)).state();
    }

    private GameState elapse(GameState s, String phase) {
        return runner.elapse(s, phase).state();
    }

    // ---------------------------------------------------------------- win conditions

    /**
     * 6 players, 2 traitors. Faithful play smart: they always vote off a living
     * original traitor. Round 1 removes one traitor, round 2 removes the other —
     * two rounds is exactly enough, since the night kill only removes one Faithful
     * per round and 4 Faithful can absorb two losses before running out.
     */
    @Test
    void faithfulWinByBanishingBothTraitors() {
        GameConfig config = Presets.CLASSIC_CONSPIRACY.config();
        GameState s = module.initialState(ids(6), config, RandomSource.seeded(1));
        TruearenaState ts0 = (TruearenaState) s;
        List<String> traitors = new ArrayList<>(ts0.originalTraitors);
        assertThat(traitors).hasSize(2);

        s = elapse(s, "RoleReveal"); // -> Night
        s = killOneFaithfulAtNight(s);
        s = elapse(s, "MorningReveal");
        s = elapse(s, "RoundTable");
        assertThat(s.phase()).isEqualTo("Vote");
        s = unanimousVoteFor(s, traitors.get(0)); // banish traitor #1
        assertThat(s.phase()).isEqualTo("Night").as("WinCheck should loop back into round 2");

        s = killOneFaithfulAtNight(s);
        s = elapse(s, "MorningReveal");
        s = elapse(s, "RoundTable");
        s = unanimousVoteFor(s, traitors.get(1)); // banish traitor #2 -> zero traitors left

        assertThat(s.finished()).isTrue();
        TruearenaState fin = (TruearenaState) s;
        assertThat(fin.win.winningSide()).isEqualTo("faithful");
        assertThat(fin.aliveTraitors()).isEmpty();
    }

    /**
     * Same setup, but Faithful vote each other off instead — one round of Faithful
     * banishing a Faithful reaches traitor/faithful parity (2 vs 2) immediately, so
     * the Traitors win on the very first {@code WinCheck}.
     */
    @Test
    void traitorsWinByReachingParity() {
        GameConfig config = Presets.CLASSIC_CONSPIRACY.config();
        GameState s = module.initialState(ids(6), config, RandomSource.seeded(2));
        TruearenaState ts0 = (TruearenaState) s;
        String targetFaithful = ts0.aliveFaithful().get(0);

        s = elapse(s, "RoleReveal");
        s = killOneFaithfulAtNight(s); // 4 alive faithful -> 3
        s = elapse(s, "MorningReveal");
        s = elapse(s, "RoundTable");
        s = unanimousVoteFor(s, targetFaithful); // banish a faithful -> 2 faithful, 2 traitors: parity

        assertThat(s.finished()).isTrue();
        TruearenaState fin = (TruearenaState) s;
        assertThat(fin.win.winningSide()).isEqualTo("traitors");
    }

    /**
     * Every shipped preset, played by simple bots (see {@link AutoPlay}), always
     * reaches one of the two valid outcomes and always emits the terminal events.
     * ({@code TrueArenaEngineTest.everyPresetPlaysToATerminalResult} covers the same
     * ground with a single seed; this widens it to catch a seed-dependent crash.)
     */
    @Test
    void everyPresetTerminatesCleanlyAcrossManySeeds() {
        for (Presets.Mode mode : Presets.ALL) {
            int n = mode.config().table().players();
            for (long seed = 1; seed <= 15; seed++) {
                AutoPlay.Result r = AutoPlay.run(mode.config(), n, seed);
                assertThat(r.winningSide()).as("%s seed %d", mode.slug(), seed).isIn("faithful", "traitors");
            }
        }
    }

    // ---------------------------------------------------------------- hidden_legacy

    /**
     * With {@code hidden_legacy} enabled and both original traitors banished before
     * round 3, the game recruits a living Faithful instead of ending — deterministic,
     * not seed-searched (contrast {@code TrueArenaEngineTest.hiddenLegacyRecruitsInsteadOfEndingEarly}).
     * Note: none of the 5 shipped presets actually enable this twist (see
     * docs/DEV_REFERENCE.md §7) — it only fires on a custom/admin config like this one.
     */
    @Test
    void hiddenLegacyRecruitsAndTheGameContinues() {
        GameConfig base = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig withLegacy = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), base.voteReveal(), base.endgameVeil(),
                Map.of("hidden_legacy", Map.of("trigger", "before_round_3")));

        GameState s = module.initialState(ids(6), withLegacy, RandomSource.seeded(3));
        TruearenaState ts0 = (TruearenaState) s;
        List<String> traitors = new ArrayList<>(ts0.originalTraitors);

        s = elapse(s, "RoleReveal");
        s = killOneFaithfulAtNight(s);
        s = elapse(s, "MorningReveal");
        s = elapse(s, "RoundTable");
        s = unanimousVoteFor(s, traitors.get(0)); // round 1: banish traitor #1, round -> 2 still

        s = killOneFaithfulAtNight(s);
        s = elapse(s, "MorningReveal");
        s = elapse(s, "RoundTable");
        s = unanimousVoteFor(s, traitors.get(1)); // round 2 (< 3): banish last original traitor -> recruit fires

        assertThat(s.finished()).as("recruit should keep the game running, not end it").isFalse();
        assertThat(s.phase()).isEqualTo("Night");
        assertThat(s.round()).isEqualTo(3);
        TruearenaState afterRecruit = (TruearenaState) s;
        assertThat(afterRecruit.roles.values()).contains(TruearenaState.RECRUITED);
        assertThat(afterRecruit.aliveTraitors()).as("the recruited player counts as a traitor again").hasSize(1);
    }

    // ---------------------------------------------------------------- reveal-on-elimination policies

    @Test
    void revealOnElimination_always_showsRoleImmediately() {
        GameState s = eliminateOnePlayerViaVote(withReveal(Presets.CLASSIC_CONSPIRACY.config(), "always"));
        TruearenaState ts = (TruearenaState) s;
        String banished = ts.eliminatedLog.get(0);
        assertThat(ts.eliminationRoleShown.get(banished)).isTrue();
    }

    @Test
    void revealOnElimination_never_hidesRoleForever() {
        GameState s = eliminateOnePlayerViaVote(withReveal(Presets.CLASSIC_CONSPIRACY.config(), "never"));
        TruearenaState ts = (TruearenaState) s;
        String banished = ts.eliminatedLog.get(0);
        assertThat(ts.eliminationRoleShown.get(banished)).isFalse();
    }

    @Test
    void revealOnElimination_alternating_startsPublic() {
        // eliminationIndex is 0 for the very first elimination of the game -> public.
        GameState s = eliminateOnePlayerViaVote(withReveal(Presets.CLASSIC_CONSPIRACY.config(), "alternating"));
        TruearenaState ts = (TruearenaState) s;
        String banished = ts.eliminatedLog.get(0);
        assertThat(ts.eliminationRoleShown.get(banished)).isTrue();
    }

    // ---------------------------------------------------------------- tie handling

    @Test
    void tieBreak_noElimination_skipsBanishmentAndContinues() {
        GameConfig config = withTieBreak(Presets.CLASSIC_CONSPIRACY.config(), "no_elimination");
        GameState s = module.initialState(ids(6), config, RandomSource.seeded(4));
        s = elapse(s, "RoleReveal");
        s = killOneFaithfulAtNight(s); // 5 alive
        s = elapse(s, "MorningReveal");
        s = elapse(s, "RoundTable");

        List<GameEvent> before = new ArrayList<>(s.events());
        s = tiedVote(s); // a genuine 2-2-1 tie among the 5 alive
        List<GameEvent> newEvents = eventsSince(before, s);

        assertThat(newEvents).anyMatch(e -> "TIE_NO_ELIMINATION".equals(e.type()));
        assertThat(newEvents).noneMatch(e -> "PLAYER_ELIMINATED".equals(e.type()));
        assertThat(((TruearenaState) s).eliminatedLog).hasSize(1); // only the earlier night kill
        assertThat(s.phase()).isEqualTo("Night").as("no elimination -> straight to the next round");
    }

    /**
     * {@code random} (or any tieBreak string that isn't one of the other recognized values)
     * is the only one with no dedicated replay/decision phase — it resolves immediately via
     * a seeded random pick among the tied players.
     */
    @Test
    void tieBreak_random_resolvesImmediatelyAndDeterministically() {
        GameConfig config = withTieBreak(Presets.CLASSIC_CONSPIRACY.config(), "random");
        GameState s1 = playToTiedVote(config, 5);
        GameState s2 = playToTiedVote(config, 5);

        List<GameEvent> new1 = eventsSince(List.of(), s1);
        assertThat(new1).anyMatch(e -> "TIE_RESOLVED".equals(e.type()) && "random".equals(e.payload().get("method")));
        assertThat(((TruearenaState) s1).eliminatedLog).hasSize(2); // night kill + the resolved banish

        // same seed both times -> same tied-player chosen both times
        assertThat(((TruearenaState) s1).eliminatedLog).isEqualTo(((TruearenaState) s2).eliminatedLog);
    }

    /**
     * {@code revote}, {@code sudden_death}, and the bare {@code trial_of_two} tieBreak
     * string each open their own replay phase instead of resolving immediately; none of
     * them fall through to the random-pick branch. {@code trial_of_two} as the plain tie
     * rule now gets the same Defense the twist does (it used to run SuddenDeath, with no
     * defense at all — see TraitorsAuditTest.trialOfTwoAsTieRule).
     */
    @Test
    void tieBreak_replayRules_openADedicatedPhaseInsteadOfResolvingImmediately() {
        record Case(String rule, String expectedPhase) {
        }
        for (Case c : List.of(new Case("revote", "Revote"), new Case("sudden_death", "SuddenDeath"),
                new Case("trial_of_two", "Defense"))) {
            GameConfig config = withTieBreak(Presets.CLASSIC_CONSPIRACY.config(), c.rule());
            GameState s = playToTiedVote(config, 5);
            assertThat(s.phase()).as(c.rule()).isEqualTo(c.expectedPhase());
            assertThat(((TruearenaState) s).tieCandidates).as(c.rule()).containsExactlyInAnyOrder("p1", "p2");
            List<GameEvent> events = eventsSince(List.of(), s);
            assertThat(events).as(c.rule())
                    .anyMatch(e -> "TIE_REPLAY".equals(e.type()) && c.rule().equals(e.payload().get("method")));
        }
    }

    @Test
    void tieBreak_hostDecides_opensAHostDecisionInsteadOfResolvingImmediately() {
        GameConfig config = withTieBreak(Presets.CLASSIC_CONSPIRACY.config(), "host_decides");
        GameState s = playToTiedVote(config, 5);
        assertThat(s.phase()).isEqualTo("HostDecision");
        assertThat(((TruearenaState) s).tieCandidates).containsExactlyInAnyOrder("p1", "p2");
        List<GameEvent> events = eventsSince(List.of(), s);
        assertThat(events).anyMatch(e -> "TIE_HOST_DECISION".equals(e.type()));
    }

    /**
     * With the {@code trial_of_two} twist actually enabled (not just the bare tieBreak
     * string above), it takes precedence over whatever {@code tieBreak} is configured
     * (docs/GAME_CONFIG.md's compatibility rule: "the twist wins") and opens the shared
     * Defense phase, then a final vote restricted to just the two tied candidates.
     */
    @Test
    void trialOfTwoTwist_opensDefenseThenARestrictedFinalVote() {
        GameConfig base = withTieBreak(Presets.CLASSIC_CONSPIRACY.config(), "random"); // twist must override this
        GameConfig withTwist = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), base.voteReveal(), base.endgameVeil(), Map.of("trial_of_two", Map.of()));

        GameState s = playToTiedVote(withTwist, 5);
        assertThat(s.phase()).isEqualTo("Defense");
        assertThat(((TruearenaState) s).tieCandidates).containsExactlyInAnyOrder("p1", "p2");
        List<GameEvent> events = eventsSince(List.of(), s);
        assertThat(events).anyMatch(e -> "TIE_REPLAY".equals(e.type()) && "trial_of_two".equals(e.payload().get("method")));

        s = elapse(s, "Defense"); // -> Vote, restricted to the two tied candidates
        assertThat(s.phase()).isEqualTo("Vote");
        assertThat(((TruearenaState) s).tieCandidates).containsExactlyInAnyOrder("p1", "p2");
        List<GameEvent> afterDefense = eventsSince(events, s);
        assertThat(afterDefense).anyMatch(e -> "FINAL_VOTE_OPEN".equals(e.type()));

        // Every alive player must vote for one of the two tied candidates — a third
        // candidate is rejected by the same tie-restriction CAST_VOTE already enforces.
        TruearenaState ts = (TruearenaState) s;
        String other = ts.alive.stream().filter(id -> !id.equals("p1") && !id.equals("p2")).findFirst().orElseThrow();
        GameState voteState = s;
        assertThatThrownBy(() -> module.onPlayerAction(voteState, PlayerAction.of(other, "CAST_VOTE", Map.of("target", "p3".equals(other) ? "p4" : "p3"))))
                .isInstanceOf(RuleViolation.class);

        s = unanimousVoteFor(s, "p1"); // everyone (except p1, who votes p2) votes p1 -> p1 banished
        assertThat(((TruearenaState) s).eliminatedLog).contains("p1");
    }

    // ---------------------------------------------------------------- AFK

    @Test
    void afkPlayersAreAutoAbstainedWhenTheVoteTimerElapses() {
        GameConfig config = Presets.CLASSIC_CONSPIRACY.config(); // afk = "abstain" on every shipped preset
        GameState s = module.initialState(ids(6), config, RandomSource.seeded(5));
        s = elapse(s, "RoleReveal");
        s = killOneFaithfulAtNight(s); // 5 alive
        s = elapse(s, "MorningReveal");
        s = elapse(s, "RoundTable");
        TruearenaState ts = (TruearenaState) s;
        List<String> alive = ts.alive.stream().toList();

        // Everyone except the last player votes for the first; the last never votes —
        // the vote timer elapsing (not everyone locking in) is what closes the ballot.
        for (int i = 0; i < alive.size() - 1; i++) {
            if (!alive.get(i).equals(alive.get(0))) {
                s = apply(s, alive.get(i), "CAST_VOTE", Map.of("target", alive.get(0)));
            }
        }
        String afkVoter = alive.get(alive.size() - 1);
        List<GameEvent> before = new ArrayList<>(s.events());
        s = elapse(s, "Vote"); // ballot closes here — AFK_ABSTAINED fires during this exact transition
        List<GameEvent> newEvents = eventsSince(before, s);
        assertThat(newEvents).anyMatch(e -> "AFK_ABSTAINED".equals(e.type())
                && ((List<?>) e.payload().get("ids")).contains(afkVoter));

        s = resolveVoteReviewElimination(s);
        assertThat(((TruearenaState) s).eliminatedLog).hasSize(2); // night kill + the banish that followed
    }

    @Test
    void hostAssignVotes_letsAfkVotersBeAssignedInsteadOfAutoAbstaining() {
        GameConfig base = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig hostAssigns = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                "host_assigns", base.voteReveal(), base.endgameVeil(), base.twists());
        GameState s = driveToVote(hostAssigns, 6);
        TruearenaState ts = (TruearenaState) s;
        List<String> alive = ts.alive.stream().toList();
        String missingVoter = alive.get(alive.size() - 1);
        for (String voter : alive) {
            if (voter.equals(missingVoter)) continue;
            List<String> others = alive.stream().filter(id -> !id.equals(voter)).toList();
            s = apply(s, voter, "CAST_VOTE", Map.of("target", others.get(0)));
        }
        s = elapse(s, "Vote"); // ballot closes with one voter missing
        assertThat(s.phase()).isEqualTo("HostAssignVotes");
        List<GameEvent> pending = s.events().stream().filter(e -> "AFK_PENDING".equals(e.type())).toList();
        assertThat(pending).hasSize(1);
        List<?> pendingIds = (List<?>) pending.get(0).payload().get("ids");
        assertThat(pendingIds.size()).isEqualTo(1);
        assertThat(pendingIds.get(0)).isEqualTo(missingVoter);

        String assignedTarget = alive.get(0);
        s = apply(s, "host", "HOST_ASSIGN_VOTE", Map.of("voterId", missingVoter, "target", assignedTarget));
        assertThat(s.phase()).isEqualTo("VoteReview");
        assertThat(((TruearenaState) s).votes.get(missingVoter)).isEqualTo(assignedTarget);
    }

    @Test
    void hostAssignVotes_autoAbstainsIfTheHostNeverActsBeforeTheTimerElapses() {
        GameConfig base = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig hostAssigns = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                "host_assigns", base.voteReveal(), base.endgameVeil(), base.twists());
        GameState s = driveToVote(hostAssigns, 6);
        TruearenaState ts = (TruearenaState) s;
        List<String> alive = ts.alive.stream().toList();
        String missingVoter = alive.get(alive.size() - 1);
        for (String voter : alive) {
            if (voter.equals(missingVoter)) continue;
            List<String> others = alive.stream().filter(id -> !id.equals(voter)).toList();
            s = apply(s, voter, "CAST_VOTE", Map.of("target", others.get(0)));
        }
        s = elapse(s, "Vote"); // -> HostAssignVotes
        s = elapse(s, "HostAssignVotes"); // host never acted -> auto-abstain fallback
        assertThat(s.phase()).isEqualTo("VoteReview");
        List<GameEvent> abstained = s.events().stream().filter(e -> "AFK_ABSTAINED".equals(e.type())).toList();
        assertThat(abstained).hasSize(1);
        List<?> abstainedIds = (List<?>) abstained.get(0).payload().get("ids");
        assertThat(abstainedIds.size()).isEqualTo(1);
        assertThat(abstainedIds.get(0)).isEqualTo(missingVoter);
    }

    // ---------------------------------------------------------------- voteReveal

    @Test
    void voteReveal_allAtOnce_revealsImmediatelyWithoutHostAdvance() {
        GameConfig base = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig allAtOnce = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), "all_at_once", base.endgameVeil(), base.twists());
        GameState s = driveToVote(allAtOnce, 6); // 5 alive, unveiled (threshold 4)
        TruearenaState ts = (TruearenaState) s;
        List<String> alive = ts.alive.stream().toList();
        String target = alive.get(0);
        for (String voter : alive) {
            if (!voter.equals(target)) {
                s = apply(s, voter, "CAST_VOTE", Map.of("target", target));
            }
        }
        s = apply(s, target, "CAST_VOTE", Map.of("target", alive.get(1)));

        assertThat(s.phase()).isEqualTo("Elimination");
        assertThat(s.events().stream().filter(e -> "VOTE_REVEALED".equals(e.type())).count()).isEqualTo(alive.size());
    }

    @Test
    void voteReveal_sequential_revealsOneAtATimeViaRevealNext() {
        GameState s = driveToVote(Presets.CLASSIC_CONSPIRACY.config(), 6); // sequential on every shipped preset
        TruearenaState ts = (TruearenaState) s;
        List<String> alive = ts.alive.stream().toList();
        String target = alive.get(0);
        for (String voter : alive) {
            if (!voter.equals(target)) {
                s = apply(s, voter, "CAST_VOTE", Map.of("target", target));
            }
        }
        s = apply(s, target, "CAST_VOTE", Map.of("target", alive.get(1)));

        assertThat(s.phase()).isEqualTo("VoteReview");
        assertThat(s.events().stream().filter(e -> "VOTE_REVEALED".equals(e.type())).count()).isZero();

        for (int i = 0; i < alive.size(); i++) {
            assertThat(s.phase()).as("iteration %d", i).isEqualTo("VoteReview");
            s = apply(s, alive.get(0), "REVEAL_NEXT", Map.of());
        }
        assertThat(s.phase()).isEqualTo("Elimination");
        assertThat(s.events().stream().filter(e -> "VOTE_REVEALED".equals(e.type())).count()).isEqualTo(alive.size());
    }

    // ---------------------------------------------------------------- new twists

    /**
     * False Reveal can no longer rewrite a role that has already been announced —
     * every client got it in PLAYER_ELIMINATED, so hiding it afterwards hid nothing.
     * It is armed during the day and applies to the next banished Faithful instead
     * (see TraitorsAuditTest.falseRevealHidesTheRoleAsItIsAnnounced).
     */
    @Test
    void falseReveal_cannotRewriteARoleAlreadyAnnounced() {
        GameConfig base = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig withTwist = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), base.voteReveal(), base.endgameVeil(), Map.of("false_reveal", Map.of("uses", 1)));
        GameState s = module.initialState(ids(6), withTwist, RandomSource.seeded(3));
        assertThat(((TruearenaState) s).falseRevealUses).isEqualTo(1);

        s = elapse(s, "RoleReveal");
        s = killOneFaithfulAtNight(s);
        assertThat(s.phase()).isEqualTo("MorningReveal");
        TruearenaState ts = (TruearenaState) s;
        String victim = ts.eliminatedLog.get(0);
        assertThat(ts.eliminationRoleShown.get(victim)).isTrue(); // "always" reveal by default

        String traitor = ts.originalTraitors.iterator().next();
        s = apply(s, traitor, "FALSE_REVEAL", Map.of());
        TruearenaState after = (TruearenaState) s;
        assertThat(after.eliminationRoleShown.get(victim)).as("the past is not rewritten").isTrue();
        assertThat(after.falseRevealArmed).isTrue();
        assertThat(after.falseRevealUses).as("spent only when it fires").isEqualTo(1);

        GameState finalState = s;
        assertThatThrownBy(() -> module.onPlayerAction(finalState, PlayerAction.of(traitor, "FALSE_REVEAL", Map.of())))
                .isInstanceOf(RuleViolation.class); // already armed
    }

    @Test
    void silentWitness_learnsAMurderVictimWasFaithful() {
        GameConfig base = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig withTwist = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), base.voteReveal(), base.endgameVeil(), Map.of("silent_witness", Map.of()));
        GameState s = module.initialState(ids(6), withTwist, RandomSource.seeded(11));
        TruearenaState ts0 = (TruearenaState) s;
        String witness = ts0.silentWitness;
        assertThat(witness).isNotNull();
        String traitor = ts0.originalTraitors.iterator().next();
        String victim = ts0.aliveFaithful().stream().filter(id -> !id.equals(witness)).findFirst().orElseThrow();

        s = elapse(s, "RoleReveal");
        for (String t : ts0.originalTraitors) {
            s = apply(s, t, "NIGHT_TARGET", Map.of("target", victim));
        }
        if ("Night".equals(s.phase())) {
            s = elapse(s, "Night");
        }

        List<GameEvent> witnessEvents = s.events().stream().filter(e -> "SILENT_WITNESS_INTEL".equals(e.type())).toList();
        assertThat(witnessEvents).hasSize(1);
        assertThat(witnessEvents.get(0).payload().get("victim")).isEqualTo(victim);
        assertThat(witnessEvents.get(0).visibility().scope()).isEqualTo("player");
        assertThat(witnessEvents.get(0).visibility().key()).isEqualTo(witness);
    }

    @Test
    void blackmail_privatelyRevealsOnePlayersTrueSide() {
        GameConfig base = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig withTwist = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), base.voteReveal(), base.endgameVeil(), Map.of("blackmail", Map.of()));
        GameState s = module.initialState(ids(6), withTwist, RandomSource.seeded(13));
        TruearenaState ts = (TruearenaState) s;
        assertThat(ts.blackmailer).isNotNull();
        assertThat(ts.blackmailTarget).isNotNull().isNotEqualTo(ts.blackmailer);

        List<GameEvent> intel = s.events().stream().filter(e -> "BLACKMAIL_INTEL".equals(e.type())).toList();
        assertThat(intel).hasSize(1);
        assertThat(intel.get(0).payload().get("target")).isEqualTo(ts.blackmailTarget);
        assertThat(intel.get(0).payload().get("side")).isEqualTo(ts.roles.get(ts.blackmailTarget));

        Map<String, Object> blackmailerView = module.visibleStateFor(s, ts.blackmailer).data();
        assertThat(blackmailerView).containsKey("blackmailIntel");
        String someoneElse = ts.players.stream().filter(id -> !id.equals(ts.blackmailer)).findFirst().orElseThrow();
        assertThat(module.visibleStateFor(s, someoneElse).data()).doesNotContainKey("blackmailIntel");
    }

    @Test
    void confessional_revealsAnonymouslyDuringRoundTableOncePerRound() {
        GameConfig base = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig withTwist = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), base.voteReveal(), base.endgameVeil(), Map.of("confessional", Map.of()));
        GameState s = module.initialState(ids(6), withTwist, RandomSource.seeded(3));
        s = elapse(s, "RoleReveal");
        s = killOneFaithfulAtNight(s);
        s = elapse(s, "MorningReveal");
        assertThat(s.phase()).isEqualTo("RoundTable");

        TruearenaState ts = (TruearenaState) s;
        String author = ts.alive.iterator().next();
        s = apply(s, author, "SUBMIT_CONFESSIONAL", Map.of("text", "it wasn't me"));
        List<GameEvent> revealed = s.events().stream().filter(e -> "CONFESSIONAL_REVEALED".equals(e.type())).toList();
        assertThat(revealed).hasSize(1);
        assertThat(revealed.get(0).payload()).containsEntry("text", "it wasn't me");
        assertThat(revealed.get(0).payload()).doesNotContainKey("by"); // anonymous — no author field

        GameState afterFirst = s;
        assertThatThrownBy(() -> module.onPlayerAction(afterFirst, PlayerAction.of(author, "SUBMIT_CONFESSIONAL", Map.of("text", "again"))))
                .isInstanceOf(RuleViolation.class); // one per round
    }

    @Test
    void survivorsChoice_endsTheGameEarlyAtFinalFourOnUnanimousCall() {
        GameConfig base = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig withTwist = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), base.voteReveal(), base.endgameVeil(), Map.of("survivors_choice", Map.of()));
        GameState s = module.initialState(ids(5), withTwist, RandomSource.seeded(21));
        s = elapse(s, "RoleReveal");
        s = killOneFaithfulAtNight(s); // 5 -> 4 alive
        s = elapse(s, "MorningReveal");
        assertThat(s.phase()).isEqualTo("RoundTable");
        TruearenaState ts = (TruearenaState) s;
        assertThat(ts.alive).hasSize(4);

        List<String> alive = ts.alive.stream().toList();
        for (int i = 0; i < alive.size() - 1; i++) {
            s = apply(s, alive.get(i), "CALL_SURVIVORS_CHOICE", Map.of());
            assertThat(s.finished()).as("not all survivors have called it yet").isFalse();
        }
        s = apply(s, alive.get(alive.size() - 1), "CALL_SURVIVORS_CHOICE", Map.of());
        assertThat(s.finished()).isTrue();
        // No banish happened, so a Traitor is still alive -> traitors win under this twist's rule.
        assertThat(((TruearenaState) s).win.winningSide()).isEqualTo("traitors");
    }

    @Test
    void doubleAgent_recruitsTheFlaggedCandidateOnTraitorAction() {
        GameConfig base = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig withTwist = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), base.voteReveal(), base.endgameVeil(), Map.of("double_agent", Map.of()));
        GameState s = module.initialState(ids(6), withTwist, RandomSource.seeded(17));
        TruearenaState ts0 = (TruearenaState) s;
        String candidate = ts0.doubleAgentCandidate;
        assertThat(candidate).isNotNull();
        assertThat(ts0.isTraitor(candidate)).isFalse();

        s = elapse(s, "RoleReveal");
        String traitor = ts0.originalTraitors.iterator().next();
        s = apply(s, traitor, "RECRUIT_DOUBLE_AGENT", Map.of());
        TruearenaState after = (TruearenaState) s;
        assertThat(after.isTraitor(candidate)).isTrue();
        assertThat(after.doubleAgentRecruited).isTrue();

        GameState finalState = s;
        assertThatThrownBy(() -> module.onPlayerAction(finalState, PlayerAction.of(traitor, "RECRUIT_DOUBLE_AGENT", Map.of())))
                .isInstanceOf(RuleViolation.class); // already recruited
    }

    @Test
    void lastWill_letsAnEliminatedPlayerPostATruncatedPublicMessage() {
        GameConfig base = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig withTwist = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), base.voteReveal(), base.endgameVeil(), Map.of("last_will", Map.of("maxChars", 10)));
        GameState s = module.initialState(ids(6), withTwist, RandomSource.seeded(3));
        s = elapse(s, "RoleReveal");
        s = killOneFaithfulAtNight(s);
        assertThat(s.phase()).isEqualTo("MorningReveal");
        TruearenaState ts = (TruearenaState) s;
        String victim = ts.eliminatedLog.get(0);

        s = apply(s, victim, "LAST_WILL", Map.of("text", "this is way more than ten characters"));
        TruearenaState after = (TruearenaState) s;
        assertThat(after.lastWills.get(victim)).isEqualTo("this is wa"); // truncated to maxChars=10

        String alivePlayer = after.alive.iterator().next();
        GameState finalState = s;
        assertThatThrownBy(() -> module.onPlayerAction(finalState, PlayerAction.of(alivePlayer, "LAST_WILL", Map.of("text", "nope"))))
                .isInstanceOf(RuleViolation.class); // only an eliminated player may leave one
    }

    // ---------------------------------------------------------------- veiled endgame

    @Test
    void veiledEndgameSuppressesVoteDetailNearTheEnd() {
        // final_4: veil turns on once 4 or fewer players are alive.
        GameConfig base = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig veiled4 = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), base.voteReveal(), "final_4", base.twists());

        GameState s = module.initialState(ids(6), veiled4, RandomSource.seeded(6));
        // One night kill (6 -> 5) + one banish (5 -> 4) crosses the final_4 threshold.
        TruearenaState ts0 = (TruearenaState) s;
        String firstVictim = ts0.aliveFaithful().get(0);
        s = elapse(s, "RoleReveal");
        s = killOneFaithfulAtNight(s); // 5 alive
        s = elapse(s, "MorningReveal");
        s = elapse(s, "RoundTable");
        s = unanimousVoteFor(s, firstVictim.equals(((TruearenaState) s).alive.stream().toList().get(0))
                ? ((TruearenaState) s).alive.stream().toList().get(1)
                : ((TruearenaState) s).alive.stream().toList().get(0)); // 4 alive now

        Map<String, Object> snapshot = module.broadcastState(s).data();
        assertThat(snapshot.get("veiled")).isEqualTo(true);
    }

    // ---------------------------------------------------------------- rule violations a client can trigger

    @Test
    void cannotActOutsideYourTurnOrPhase() {
        GameState s = module.initialState(ids(6), Presets.CLASSIC_CONSPIRACY.config(), RandomSource.seeded(7));
        GameState roleReveal = s;
        assertThatThrownBy(() -> module.onPlayerAction(roleReveal, PlayerAction.of("p1", "CAST_VOTE", Map.of("target", "p2"))))
                .isInstanceOf(RuleViolation.class)
                .satisfies(e -> assertThat(((RuleViolation) e).code()).isEqualTo("WRONG_PHASE"));
    }

    @Test
    void onlyLivingTraitorsCanTargetAtNight() {
        GameState s = elapse(module.initialState(ids(6), Presets.CLASSIC_CONSPIRACY.config(), RandomSource.seeded(8)), "RoleReveal");
        TruearenaState ts = (TruearenaState) s;
        String faithful = ts.aliveFaithful().get(0);
        GameState night = s;
        assertThatThrownBy(() -> module.onPlayerAction(night, PlayerAction.of(faithful, "NIGHT_TARGET", Map.of("target", ts.aliveFaithful().get(1)))))
                .isInstanceOf(RuleViolation.class)
                .satisfies(e -> assertThat(((RuleViolation) e).code()).isEqualTo("NOT_TRAITOR"));
    }

    @Test
    void cannotVoteForADeadPlayer() {
        GameState s = driveToVote(Presets.CLASSIC_CONSPIRACY.config(), 6);
        GameState vote = s;
        assertThatThrownBy(() -> module.onPlayerAction(vote, PlayerAction.of("p1", "CAST_VOTE", Map.of("target", "not-a-real-player"))))
                .isInstanceOf(RuleViolation.class)
                .satisfies(e -> assertThat(((RuleViolation) e).code()).isEqualTo("BAD_TARGET"));
    }

    @Test
    void badTraitorCountForPlayerCountIsRejectedAtSetup() {
        // resolveTraitors defaults to 1 below the curve's first breakpoint (6), and a
        // single player with 1 traitor means traitorCount >= n — invalid either way.
        GameConfig config = Presets.CLASSIC_CONSPIRACY.config();
        assertThatThrownBy(() -> module.initialState(ids(1), config, RandomSource.seeded(9)))
                .isInstanceOf(RuleViolation.class)
                .satisfies(e -> assertThat(((RuleViolation) e).code()).isEqualTo("BAD_TRAITOR_COUNT"));
    }

    // ---------------------------------------------------------------- shared drivers

    /** Every living traitor targets the last living faithful; resolves once all traitors are in (or none). */
    private GameState killOneFaithfulAtNight(GameState s) {
        TruearenaState ts = (TruearenaState) s;
        List<String> faithful = ts.aliveFaithful();
        if (faithful.isEmpty()) {
            return elapse(s, "Night");
        }
        String target = faithful.get(faithful.size() - 1);
        for (String traitor : ts.aliveTraitors()) {
            if (!"Night".equals(s.phase())) {
                break;
            }
            s = apply(s, traitor, "NIGHT_TARGET", Map.of("target", target));
        }
        if ("Night".equals(s.phase())) {
            s = elapse(s, "Night");
        }
        return s;
    }

    /**
     * Every living player votes for the same target (voting for yourself is impossible,
     * so skip self), then drives VoteReview → Elimination → (if unfinished) WinCheck —
     * casting the last vote only closes the ballot; it doesn't resolve it on its own.
     */
    private GameState unanimousVoteFor(GameState s, String target) {
        TruearenaState ts = (TruearenaState) s;
        for (String voter : ts.alive.stream().toList()) {
            if (!"Vote".equals(s.phase())) {
                break;
            }
            if (voter.equals(target)) {
                List<String> others = ts.alive.stream().filter(id -> !id.equals(voter)).toList();
                s = apply(s, voter, "CAST_VOTE", Map.of("target", others.get(0)));
            } else {
                s = apply(s, voter, "CAST_VOTE", Map.of("target", target));
            }
        }
        return resolveVoteReviewElimination(s);
    }

    /**
     * A genuine tie between the first two living players: everyone else splits evenly
     * between voting for one or the other, and the two of them vote for each other
     * (self-votes are impossible) — so each ends up with the same tally. Any one
     * leftover voter (only when the remaining group is odd-sized) is left unvoted,
     * which just means the ballot has to close on the vote timer instead of everyone
     * locking in — harmless here, and it's the same AFK path exercised on its own by
     * {@link #afkPlayersAreAutoAbstainedWhenTheVoteTimerElapses()}. Drives all the way
     * through VoteReview → Elimination → (if unfinished) WinCheck before returning.
     */
    private GameState tiedVote(GameState s) {
        TruearenaState ts = (TruearenaState) s;
        List<String> alive = ts.alive.stream().toList();
        String t1 = alive.get(0), t2 = alive.get(1);
        List<String> remaining = alive.stream().filter(id -> !id.equals(t1) && !id.equals(t2)).toList();
        int half = remaining.size() / 2;
        for (int i = 0; i < half; i++) {
            s = apply(s, remaining.get(i), "CAST_VOTE", Map.of("target", t1));
        }
        for (int i = half; i < half * 2; i++) {
            s = apply(s, remaining.get(i), "CAST_VOTE", Map.of("target", t2));
        }
        if ("Vote".equals(s.phase())) {
            s = apply(s, t1, "CAST_VOTE", Map.of("target", t2));
        }
        if ("Vote".equals(s.phase())) {
            s = apply(s, t2, "CAST_VOTE", Map.of("target", t1));
        }
        if ("Vote".equals(s.phase())) {
            s = elapse(s, "Vote"); // an odd-sized remaining group leaves one voter unvoted — close on timeout
        }
        return resolveVoteReviewElimination(s);
    }

    /**
     * Once the ballot is closed (phase == VoteReview, reached either by everyone
     * locking in or by the vote timer elapsing), untimed phases don't advance on
     * their own — something (host action or, here, the test) has to move VoteReview
     * → Elimination → WinCheck explicitly.
     */
    private GameState resolveVoteReviewElimination(GameState s) {
        assertThat(s.phase()).isEqualTo("VoteReview");
        s = elapse(s, "VoteReview"); // -> Elimination
        s = elapse(s, "Elimination"); // -> WinCheck (tally + banish), or a tie-replay/decision phase
        // Only force WinCheck when tallyAndBanish actually reached it — a genuine tie routes
        // into Revote/SuddenDeath/HostDecision/Defense instead, and forcing WinCheck's case
        // there (advance() dispatches on the literal string passed, not the real d.phase)
        // would silently skip the replay/decision the tie is supposed to require.
        if (!s.finished() && "WinCheck".equals(s.phase())) {
            s = elapse(s, "WinCheck"); // -> Night (next round) or Results
        }
        return s;
    }

    private GameState playToTiedVote(GameConfig config, int players) {
        GameState s = module.initialState(ids(players), config, RandomSource.seeded(42));
        s = elapse(s, "RoleReveal");
        s = killOneFaithfulAtNight(s);
        s = elapse(s, "MorningReveal");
        s = elapse(s, "RoundTable");
        return tiedVote(s);
    }

    private GameState eliminateOnePlayerViaVote(GameConfig config) {
        GameState s = driveToVote(config, 6);
        TruearenaState ts = (TruearenaState) s;
        return unanimousVoteFor(s, ts.aliveFaithful().get(0));
    }

    private static List<GameEvent> eventsSince(List<GameEvent> before, GameState after) {
        List<GameEvent> all = after.events();
        return all.subList(Math.min(before.size(), all.size()), all.size());
    }

    private static GameConfig withReveal(GameConfig base, String policy) {
        return new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), policy, base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), base.voteReveal(), base.endgameVeil(), base.twists());
    }

    private static GameConfig withTieBreak(GameConfig base, String rule) {
        return new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), rule, base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), base.voteReveal(), base.endgameVeil(), base.twists());
    }

    /** RoleReveal → Night (traitors kill the last living faithful) → MorningReveal → RoundTable → Vote. */
    private GameState driveToVote(GameConfig config, int n) {
        GameState s = module.initialState(ids(n), config, RandomSource.seeded(3));
        s = elapse(s, "RoleReveal");
        s = killOneFaithfulAtNight(s);
        s = elapse(s, "MorningReveal");
        s = elapse(s, "RoundTable");
        assertThat(s.phase()).isEqualTo("Vote");
        return s;
    }
}
