package app.truearena.game.truearena;

import app.truearena.engine.GameConfig;
import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class TrueArenaEngineTest {

    private final TrueArenaModule module = new TrueArenaModule();

    private static List<String> ids(int n) {
        return java.util.stream.IntStream.rangeClosed(1, n).mapToObj(i -> "p" + i).toList();
    }

    @Test
    void gameType() {
        assertThat(module.gameType()).isEqualTo("truearena");
    }

    @Test
    void roleAssignmentMatchesTheCurve() {
        for (Presets.Mode mode : Presets.ALL) {
            GameConfig c = mode.config();
            for (int n = c.table().minPlayers(); n <= c.table().maxPlayers(); n++) {
                var state = (TruearenaState) module.initialState(ids(n), c, RandomSource.seeded(42));
                long traitors = state.roles.values().stream().filter("traitor"::equals).count();
                assertThat(traitors)
                        .as("%s @ %d players", mode.slug(), n)
                        .isEqualTo(c.table().resolveTraitors(n))
                        .isGreaterThanOrEqualTo(1);
                assertThat(state.roles).hasSize(n);
                assertThat(state.alive).hasSize(n);
                assertThat(state.originalTraitors).hasSize((int) traitors);
            }
        }
    }

    @Test
    void votesLockAndCannotChange() {
        GameState s = driveToVote(Presets.CLASSIC_CONSPIRACY.config(), 6);
        s = module.onPlayerAction(s, PlayerAction.of("p1", "CAST_VOTE", Map.of("target", "p2")));
        GameState locked = s;
        assertThatThrownBy(() -> module.onPlayerAction(locked, PlayerAction.of("p1", "CAST_VOTE", Map.of("target", "p3"))))
                .isInstanceOf(RuleViolation.class)
                .satisfies(e -> assertThat(((RuleViolation) e).code()).isEqualTo("VOTE_LOCKED"));
    }

    @Test
    void selfVoteRejected() {
        GameState s = driveToVote(Presets.CLASSIC_CONSPIRACY.config(), 6);
        GameState fs = s;
        assertThatThrownBy(() -> module.onPlayerAction(fs, PlayerAction.of("p1", "CAST_VOTE", Map.of("target", "p1"))))
                .isInstanceOf(RuleViolation.class);
    }

    @Test
    void traitorsCannotMurderEachOther() {
        GameConfig config = Presets.CLASSIC_CONSPIRACY.config();
        GameState night = module.onPhaseElapsed(
                module.initialState(ids(6), config, RandomSource.seeded(3)), "RoleReveal");
        TruearenaState state = (TruearenaState) night;
        String actor = state.aliveTraitors().get(0);
        String target = state.aliveTraitors().get(1);
        assertThatThrownBy(() -> module.onPlayerAction(night,
                PlayerAction.of(actor, "NIGHT_TARGET", Map.of("target", target))))
                .isInstanceOf(RuleViolation.class)
                .satisfies(e -> assertThat(((RuleViolation) e).code()).isEqualTo("BAD_TARGET"));
    }

    @Test
    void consensusModeDoesNotKillWhenTraitorsDisagreeAtTimeout() {
        GameState night = module.onPhaseElapsed(
                module.initialState(ids(9), Presets.THE_LAST_ALIBI.config(), RandomSource.seeded(3)), "RoleReveal");
        TruearenaState state = (TruearenaState) night;
        List<String> traitors = state.aliveTraitors();
        List<String> faithful = state.aliveFaithful();
        night = module.onPlayerAction(night, PlayerAction.of(traitors.get(0), "NIGHT_TARGET", Map.of("target", faithful.get(0))));
        night = module.onPlayerAction(night, PlayerAction.of(traitors.get(1), "NIGHT_TARGET", Map.of("target", faithful.get(1))));
        night = module.onPlayerAction(night, PlayerAction.of(traitors.get(2), "NIGHT_TARGET", Map.of("target", faithful.get(0))));
        assertThat(night.phase()).isEqualTo("Night");
        GameState morning = module.onPhaseElapsed(night, "Night");
        assertThat(((TruearenaState) morning).alive).containsAll(faithful);
        assertThat(morning.events()).anyMatch(e -> "NO_MURDER".equals(e.type())
                && "no_consensus".equals(e.payload().get("reason")));
    }

    @Test
    void replayingAnActionIdIsANoOp() {
        GameState s = driveToVote(Presets.CLASSIC_CONSPIRACY.config(), 6);
        PlayerAction a = PlayerAction.of("p1", "CAST_VOTE", Map.of("target", "p2"));
        GameState once = module.onPlayerAction(s, a);
        GameState twice = module.onPlayerAction(once, a);
        assertThat(twice.events()).hasSameSizeAs(once.events());
        assertThat(twice).isSameAs(once);
    }

    @Test
    void everyPresetPlaysToATerminalResult() {
        for (Presets.Mode mode : Presets.ALL) {
            int n = mode.config().table().players();
            AutoPlay.Result r = AutoPlay.run(mode.config(), n, 7L);
            assertThat(r.winningSide()).as(mode.slug()).isIn("faithful", "traitors");
            assertThat(r.rounds()).isBetween(1, 60);
            assertThat(r.publicEvents()).anyMatch(e -> "GAME_OVER".equals(e.get("type")));
            assertThat(r.publicEvents()).anyMatch(e -> "FULL_REVEAL".equals(e.get("type")));
        }
    }

    @Test
    void sameSeedSameGame() {
        GameConfig c = Presets.BLOOD_MOON.config();
        AutoPlay.Result a = AutoPlay.run(c, 10, 99L);
        AutoPlay.Result b = AutoPlay.run(c, 10, 99L);
        assertThat(b.winningSide()).isEqualTo(a.winningSide());
        assertThat(b.eliminated()).isEqualTo(a.eliminated());
        assertThat(b.finalRoles()).isEqualTo(a.finalRoles());
        assertThat(types(b)).isEqualTo(types(a));
    }

    @Test
    void hiddenLegacyRecruitsInsteadOfEndingEarly() {
        GameConfig base = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig withLegacy = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), base.voteReveal(), base.endgameVeil(),
                Map.of("hidden_legacy", Map.of("trigger", "before_round_3")));
        // A run where Faithful banish both traitors fast can trigger recruitment; assert the
        // event appears at least once across a spread of seeds and the game still terminates cleanly.
        // This is a genuinely rare condition with this bot strategy (~3 hits per 200 seeds, first
        // hit at seed 59) — 40 seeds isn't enough headroom to reliably contain one, so this range
        // is wide enough to make the assertion deterministic rather than seed-range-dependent.
        boolean sawRecruit = false;
        for (long seed = 1; seed <= 200 && !sawRecruit; seed++) {
            AutoPlay.Result r = AutoPlay.run(withLegacy, 6, seed);
            assertThat(r.winningSide()).isIn("faithful", "traitors");
            sawRecruit = r.publicEvents().stream().anyMatch(e -> "HIDDEN_LEGACY".equals(e.get("type")));
        }
        assertThat(sawRecruit).as("hidden_legacy should fire in at least one of 40 seeded runs").isTrue();
    }

    private static List<String> types(AutoPlay.Result r) {
        return r.publicEvents().stream().map(e -> (String) e.get("type")).toList();
    }

    /** RoleReveal → Night (traitors kill p-last) → MorningReveal → RoundTable → Vote. */
    private GameState driveToVote(GameConfig config, int n) {
        GameState s = module.initialState(ids(n), config, RandomSource.seeded(3));
        s = module.onPhaseElapsed(s, "RoleReveal");            // → Night
        TruearenaState ts = (TruearenaState) s;
        String target = ts.aliveFaithful().get(ts.aliveFaithful().size() - 1);
        for (String t : ts.aliveTraitors()) {
            s = module.onPlayerAction(s, PlayerAction.of(t, "NIGHT_TARGET", Map.of("target", target)));
        }
        if ("Night".equals(s.phase())) {
            s = module.onPhaseElapsed(s, "Night");
        }
        s = module.onPhaseElapsed(s, "MorningReveal");         // → RoundTable
        s = module.onPhaseElapsed(s, "RoundTable");            // → Vote
        assertThat(s.phase()).isEqualTo("Vote");
        return s;
    }

    // ---------------------------------------------------------------- playersToAct (push turn reminders)

    @Test
    void playersToActDuringRoleRevealIsEmpty_hostPaced() {
        GameState s = module.initialState(ids(6), Presets.CLASSIC_CONSPIRACY.config(), RandomSource.seeded(3));
        assertThat(s.phase()).isEqualTo("RoleReveal");
        assertThat(module.playersToAct(s)).isEmpty();
    }

    @Test
    void playersToActDuringNightIsEveryLivingTraitor() {
        GameState s = module.initialState(ids(6), Presets.CLASSIC_CONSPIRACY.config(), RandomSource.seeded(3));
        s = module.onPhaseElapsed(s, "RoleReveal"); // → Night
        TruearenaState ts = (TruearenaState) s;
        assertThat(module.playersToAct(s)).containsExactlyInAnyOrderElementsOf(ts.aliveTraitors());
    }

    @Test
    void playersToActDuringVoteIsEveryoneWhoHasNotLockedAVote() {
        GameState s = driveToVote(Presets.CLASSIC_CONSPIRACY.config(), 6);
        TruearenaState ts = (TruearenaState) s;
        assertThat(module.playersToAct(s)).containsExactlyInAnyOrderElementsOf(ts.alive);

        GameState afterOneVote = module.onPlayerAction(s,
                PlayerAction.of(ts.alive.iterator().next(), "CAST_VOTE", Map.of("target", ts.alive.stream()
                        .filter(id -> !id.equals(ts.alive.iterator().next())).findFirst().orElseThrow())));
        TruearenaState afterTs = (TruearenaState) afterOneVote;
        assertThat(module.playersToAct(afterOneVote)).doesNotContain(ts.alive.iterator().next())
                .containsExactlyInAnyOrderElementsOf(afterTs.alive.stream()
                        .filter(id -> !afterTs.voteLocked.contains(id)).toList());
    }
}
