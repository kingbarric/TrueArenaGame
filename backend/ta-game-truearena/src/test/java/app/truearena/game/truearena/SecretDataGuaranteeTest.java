package app.truearena.game.truearena;

import app.truearena.engine.GameConfig;
import app.truearena.engine.GameEvent;
import app.truearena.engine.GameState;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.RandomSource;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Build Brief §8 — the non-negotiable. Across a full game, no Faithful's per-player
 * view and no broadcast view may carry another player's secret role, and no event
 * a Faithful or the broadcast could receive may leak one, until the game is finished.
 */
class SecretDataGuaranteeTest {

    private final TrueArenaModule module = new TrueArenaModule();

    @Test
    void faithfulAndBroadcastNeverSeeAnotherRoleBeforeResults() {
        for (long seed = 1; seed <= 25; seed++) {
            playAndAudit(Presets.CLASSIC_CONSPIRACY.config(), 8, seed);
            playAndAudit(Presets.THE_LAST_ALIBI.config(), 10, seed);   // alternating reveal policy
            playAndAudit(Presets.BLOOD_MOON.config(), 10, seed);
        }
    }

    /**
     * {@code blackmail}'s intel payload carries another player's true alignment ({@code side})
     * — the one new twist field with a real per-player view exposure ({@code blackmailIntel}
     * in {@link TrueArenaModule#visibleStateFor}). Runs the same simulate-and-audit loop with
     * the twist enabled and checks every viewer, every frame: only the blackmailer ever sees it,
     * and the broadcast view never does.
     */
    @Test
    void blackmailIntelNeverLeaksToAnyoneButTheBlackmailer() {
        GameConfig base = Presets.CLASSIC_CONSPIRACY.config();
        GameConfig withBlackmail = new GameConfig(base.catalogVersion(), base.preset(), base.table(), base.timers(),
                base.nightKill(), base.revealOnElimination(), base.tieBreak(), base.secondTie(), base.suddenDeathSeconds(),
                base.afk(), base.voteReveal(), base.endgameVeil(), Map.of("blackmail", Map.of()));
        for (long seed = 1; seed <= 15; seed++) {
            List<String> ids = java.util.stream.IntStream.rangeClosed(1, 8).mapToObj(i -> "p" + i).toList();
            GameState state = module.initialState(ids, withBlackmail, RandomSource.seeded(seed));
            String blackmailer = ((TruearenaState) state).blackmailer;
            assertThat(blackmailer).as("seed %d", seed).isNotNull();
            for (String viewer : ids) {
                Map<String, Object> pv = module.visibleStateFor(state, viewer).data();
                if (viewer.equals(blackmailer)) {
                    assertThat(pv).as("seed %d: blackmailer should see their own intel", seed).containsKey("blackmailIntel");
                } else {
                    assertThat(pv).as("seed %d: %s should not see the blackmailer's intel", seed, viewer)
                            .doesNotContainKey("blackmailIntel");
                }
            }
            assertThat(module.broadcastState(state).data())
                    .as("seed %d: broadcast should never carry blackmail intel", seed)
                    .doesNotContainKey("blackmailIntel");
        }
    }

    private void playAndAudit(GameConfig config, int n, long seed) {
        List<String> ids = java.util.stream.IntStream.rangeClosed(1, n).mapToObj(i -> "p" + i).toList();
        GameState state = module.initialState(ids, config, RandomSource.seeded(seed));
        RandomSource rng = RandomSource.seeded(seed ^ 0xABCDEFL);

        auditFrame(state, ids);

        int guard = 0;
        while (!state.finished() && guard++ < 400) {
            GameState before = state;
            switch (state.phase()) {
                case "Night" -> {
                    var ts = (TruearenaState) state;
                    if (!ts.aliveFaithful().isEmpty()) {
                        String target = ts.aliveFaithful().get(0);
                        for (String t : ts.aliveTraitors()) {
                            if (!"Night".equals(state.phase())) break;
                            state = module.onPlayerAction(state, PlayerAction.of(t, "NIGHT_TARGET", Map.of("target", target)));
                        }
                    }
                    if ("Night".equals(state.phase())) state = module.onPhaseElapsed(state, "Night");
                }
                case "Vote" -> {
                    var ts = (TruearenaState) state;
                    for (String voter : ts.alive.stream().toList()) {
                        if (!"Vote".equals(state.phase())) break;
                        List<String> opts = new java.util.ArrayList<>(ts.alive.stream().toList());
                        opts.remove(voter);
                        String target = ts.isTraitor(voter) && !ts.aliveFaithful().isEmpty() && !ts.aliveFaithful().get(0).equals(voter)
                                ? ts.aliveFaithful().get(0)
                                : opts.get(rng.nextInt(opts.size()));
                        state = module.onPlayerAction(state, PlayerAction.of(voter, "CAST_VOTE", Map.of("target", target)));
                    }
                    if ("Vote".equals(state.phase())) state = module.onPhaseElapsed(state, "Vote");
                }
                case "Results" -> { }
                default -> state = module.onPhaseElapsed(state, state.phase());
            }

            if (!state.finished()) {
                auditFrame(state, ids);
                auditEvents(module.drainEvents(before, state), (TruearenaState) state, ids);
            }
        }
        assertThat(state.finished()).as("game terminates (seed %d)", seed).isTrue();
    }

    private void auditFrame(GameState state, List<String> ids) {
        var ts = (TruearenaState) state;
        Set<String> faithful = ts.aliveFaithful().stream().collect(java.util.stream.Collectors.toSet());
        // pick a Faithful subscriber if one is alive, else any player
        String viewer = faithful.stream().findFirst().orElse(ids.get(0));

        Map<String, Object> pv = module.visibleStateFor(state, viewer).data();
        assertNoForeignRole(pv, viewer, ts, "visibleStateFor(" + viewer + ")");

        Map<String, Object> bc = module.broadcastState(state).data();
        assertThat(bc).doesNotContainKey("yourRole");
        assertThat(bc).doesNotContainKey("fellowTraitors");
        assertNoForeignRole(bc, null, ts, "broadcastState");
    }

    @SuppressWarnings("unchecked")
    private void assertNoForeignRole(Map<String, Object> view, String self, TruearenaState ts, String where) {
        // only roles legitimately public: eliminated players whose role was shown at elimination
        Set<String> allowedRoleHolders = new java.util.HashSet<>();
        for (String id : ts.eliminatedLog) {
            if (Boolean.TRUE.equals(ts.eliminationRoleShown.get(id))) allowedRoleHolders.add(id);
        }
        if (self != null) allowedRoleHolders.add(self);

        Object revealed = view.get("revealedRoles");
        if (revealed instanceof Map<?, ?> m) {
            for (Object k : m.keySet()) {
                assertThat(allowedRoleHolders).as("%s exposed role of %s via revealedRoles", where, k).contains((String) k);
            }
        }
        // fellowTraitors is IDs only, never roles — and only for a Traitor viewer; a Faithful must not get it
        if (self != null && !ts.isTraitor(self)) {
            assertThat(view).as("%s gave a Faithful the traitor list", where).doesNotContainKey("fellowTraitors");
        }
        assertThat(view).as("%s leaked the night target to a non-traitor", where)
                .satisfies(v -> {
                    if (self != null && !ts.isTraitor(self)) assertThat(v).doesNotContainKey("yourNightTarget");
                });
    }

    private void auditEvents(List<GameEvent> events, TruearenaState ts, List<String> ids) {
        Set<String> shown = new java.util.HashSet<>();
        for (String id : ts.eliminatedLog) {
            if (Boolean.TRUE.equals(ts.eliminationRoleShown.get(id))) shown.add(id);
        }
        for (GameEvent e : events) {
            // events a Faithful or broadcast can receive: PUBLIC or role="faithful" — never role="traitor"/player-scoped-traitor
            boolean faithfulCanSee = e.visibility().isPublic()
                    || "role".equals(e.visibility().scope()) && "faithful".equals(e.visibility().key());
            if (!faithfulCanSee) continue;
            Object role = e.payload().get("role");
            if (role != null) {
                Object id = e.payload().get("id");
                assertThat(shown).as("public event %s leaked role of %s", e.type(), id).contains((String) id);
            }
            assertThat(e.payload()).as("public event %s carried a raw role map", e.type()).doesNotContainKey("roles");
        }
    }
}
