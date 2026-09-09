package app.truearena.game.truearena;

import app.truearena.engine.GameConfig;
import app.truearena.engine.GameEvent;
import app.truearena.engine.GameModule;
import app.truearena.engine.GameState;
import app.truearena.engine.Phase;
import app.truearena.engine.PlayerAction;
import app.truearena.engine.PlayerVisibleState;
import app.truearena.engine.PublicBroadcastState;
import app.truearena.engine.RandomSource;
import app.truearena.engine.RuleViolation;
import app.truearena.engine.WinResult;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * The flagship module — Traitors and Faithful. Config-driven (docs/GAME_CONFIG.md).
 *
 * <p>Phase loop: RoleReveal → (Night → MorningReveal → RoundTable → Vote → VoteReview →
 * Elimination → WinCheck)* → Results. Twist effects are consulted through
 * {@link TwistRegistry}; {@code hidden_legacy} is wired end-to-end, the rest are
 * registered and validated with effects landing incrementally.
 */
public final class TrueArenaModule implements GameModule {

    public static final String GAME_TYPE = "truearena";

    @Override
    public String gameType() {
        return GAME_TYPE;
    }

    @Override
    public List<Phase> definePhases(GameConfig config) {
        return List.of(
                Phase.untimed("RoleReveal"),
                new Phase("Night", config.timers().night()),
                Phase.untimed("MorningReveal"),
                new Phase("RoundTable", config.timers().roundTable()),
                new Phase("Vote", config.timers().vote()),
                Phase.untimed("VoteReview"),
                Phase.untimed("Elimination"),
                Phase.untimed("WinCheck"),
                Phase.untimed("Results")
        );
    }

    // ---------------------------------------------------------------- setup

    @Override
    public GameState initialState(List<String> playerIds, GameConfig config, RandomSource rng) {
        int n = playerIds.size();
        int traitorCount = config.table().resolveTraitors(n);
        if (traitorCount < 1 || traitorCount >= n) {
            throw new RuleViolation("BAD_TRAITOR_COUNT", "resolved traitor count " + traitorCount + " invalid for " + n + " players");
        }

        List<String> shuffled = new ArrayList<>(playerIds);
        rng.shuffle(shuffled);

        TruearenaState.Draft d = new TruearenaState.Draft();
        d.phase = "RoleReveal";
        d.round = 1;
        d.players = new ArrayList<>(playerIds);
        d.config = config;
        d.seed = rng.seed();
        d.alive.addAll(playerIds);

        for (int i = 0; i < n; i++) {
            String id = shuffled.get(i);
            boolean traitor = i < traitorCount;
            d.roles.put(id, traitor ? TruearenaState.TRAITOR : TruearenaState.FAITHFUL);
            if (traitor) {
                d.originalTraitors.add(id);
            }
        }

        d.emit("GAME_STARTED", Map.of(
                "players", List.copyOf(playerIds),
                "traitors", traitorCount,
                "preset", str(config.preset())));

        List<String> traitorIds = d.originalTraitors.stream().toList();
        for (String id : playerIds) {
            String role = d.roles.get(id);
            d.emitToPlayer("ROLE_ASSIGNED", Map.of("role", role), id);
            if (TruearenaState.TRAITOR.equals(role)) {
                d.emitToPlayer("FELLOW_TRAITORS",
                        Map.of("ids", traitorIds.stream().filter(x -> !x.equals(id)).toList()), id);
            }
        }
        return d.build();
    }

    // ---------------------------------------------------------------- actions

    @Override
    public GameState onPlayerAction(GameState state, PlayerAction action) {
        TruearenaState s = (TruearenaState) state;
        if (s.finished() || s.appliedActionIds.contains(action.actionId())) {
            return s;
        }
        TruearenaState.Draft d = new TruearenaState.Draft(s);
        d.appliedActionIds.add(action.actionId());

        switch (action.type()) {
            case "NIGHT_TARGET" -> nightTarget(d, s, action);
            case "NIGHT_SKIP" -> nightSkip(d, s, action);
            case "CAST_VOTE" -> castVote(d, s, action);
            case "REVEAL_NEXT" -> revealNext(d, s);
            case "ADVANCE_PHASE" -> advance(d, d.phase);
            default -> throw new RuleViolation("UNKNOWN_ACTION", "no handler for " + action.type());
        }
        return d.build();
    }

    @Override
    public GameState onPhaseElapsed(GameState state, String endedPhase) {
        TruearenaState s = (TruearenaState) state;
        if (s.finished()) {
            return s;
        }
        TruearenaState.Draft d = new TruearenaState.Draft(s);
        advance(d, endedPhase);
        return d.build();
    }

    private void nightTarget(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require(d.phase.equals("Night"), "WRONG_PHASE", "night targeting is Night-only");
        require(s.alive.contains(a.actor()) && s.isTraitor(a.actor()), "NOT_TRAITOR", "only living Traitors pick a target");
        String target = a.str("target");
        require(target != null && s.alive.contains(target), "BAD_TARGET", "target must be a living player");
        d.nightSubmissions.put(a.actor(), target);
        d.nightTarget = target;
        d.emitToRole("NIGHT_TARGET_SET", Map.of("by", a.actor(), "target", target), TruearenaState.TRAITOR);

        List<String> livingTraitors = s.aliveTraitors();
        boolean allIn = d.nightSubmissions.keySet().containsAll(livingTraitors);
        boolean agreed = !s.config.nightKill().requireTraitorConsensus()
                || d.nightSubmissions.values().stream().distinct().count() == 1;
        if (allIn && agreed) {
            resolveNight(d);
        }
    }

    private void nightSkip(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require(d.phase.equals("Night"), "WRONG_PHASE", "skip is Night-only");
        require(s.isTraitor(a.actor()) && s.alive.contains(a.actor()), "NOT_TRAITOR", "only living Traitors may skip");
        require(s.config.nightKill().allowSkip() && !s.nightSkipUsed, "SKIP_UNAVAILABLE", "no skip left");
        d.nightSkipUsed = true;
        d.nightTarget = null;
        resolveNight(d);
    }

    private void castVote(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require(d.phase.equals("Vote"), "WRONG_PHASE", "voting is Vote-only");
        require(s.alive.contains(a.actor()), "DEAD", "eliminated players cannot vote");
        require(!s.voteLocked.contains(a.actor()), "VOTE_LOCKED", "your vote is already locked");
        String target = a.str("target");
        require(target != null && s.alive.contains(target), "BAD_TARGET", "target must be a living player");
        require(!target.equals(a.actor()), "SELF_VOTE", "you cannot vote for yourself");
        d.votes.put(a.actor(), target);
        d.voteLocked.add(a.actor());
        d.emit("VOTE_PROGRESS", Map.of("locked", d.voteLocked.size(), "total", s.alive.size()));
        if (d.voteLocked.containsAll(s.alive)) {
            closeVoting(d);
        }
    }

    private void revealNext(TruearenaState.Draft d, TruearenaState s) {
        require(d.phase.equals("VoteReview"), "WRONG_PHASE", "nothing to reveal now");
        int revealable = veiled(s) ? 0 : d.votes.size();
        if (d.votesRevealed < revealable) {
            String voter = new ArrayList<>(d.votes.keySet()).get(d.votesRevealed);
            d.votesRevealed++;
            d.emit("VOTE_REVEALED", Map.of("voter", voter, "target", d.votes.get(voter)));
        }
        if (d.votesRevealed >= revealable) {
            d.phase = "Elimination";
        }
    }

    // ---------------------------------------------------------------- phase machine

    private void advance(TruearenaState.Draft d, String from) {
        switch (from) {
            case "RoleReveal" -> goNight(d);
            case "Night" -> resolveNight(d);
            case "MorningReveal" -> {
                d.phase = "RoundTable";
                d.emit("ROUND_TABLE_OPEN", Map.of("round", d.round));
            }
            case "RoundTable" -> {
                d.phase = "Vote";
                d.votes.clear();
                d.voteLocked.clear();
                d.votesRevealed = 0;
                d.emit("MICS_FORCE_MUTED", Map.of());
            }
            case "Vote" -> closeVoting(d);
            case "VoteReview" -> {
                if (!veiled(build(d))) {
                    while (d.votesRevealed < d.votes.size()) {
                        String voter = new ArrayList<>(d.votes.keySet()).get(d.votesRevealed++);
                        d.emit("VOTE_REVEALED", Map.of("voter", voter, "target", d.votes.get(voter)));
                    }
                }
                d.phase = "Elimination";
            }
            case "Elimination" -> tallyAndBanish(d);
            case "WinCheck" -> winCheckStep(d);
            case "Results" -> { /* terminal */ }
            default -> throw new RuleViolation("BAD_PHASE", "cannot advance from " + from);
        }
    }

    private void goNight(TruearenaState.Draft d) {
        d.phase = "Night";
        d.nightSubmissions.clear();
        d.nightTarget = null;
        d.emit("NIGHT_FALLS", Map.of("round", d.round));
    }

    private void resolveNight(TruearenaState.Draft d) {
        boolean opensDry = d.round == 1 && !d.config.nightKill().opensWithKill();
        String eliminated = null;
        if (opensDry || d.nightSkipUsed && d.nightTarget == null) {
            d.emit("NO_MURDER", Map.of("round", d.round, "reason", opensDry ? "opening_night" : "skipped"));
        } else if (d.nightTarget != null && d.alive.contains(d.nightTarget)) {
            eliminate(d, d.nightTarget, "murder");
            eliminated = d.nightTarget;
        } else {
            d.emit("NO_MURDER", Map.of("round", d.round, "reason", "no_target"));
        }
        d.nightSubmissions.clear();
        d.nightTarget = null;
        d.phase = "MorningReveal";
        Map<String, Object> p = new LinkedHashMap<>();
        p.put("round", d.round);
        p.put("eliminated", eliminated);
        d.emit("MORNING_REVEAL", p);
        settleWin(d); // "after each murder ... check the win conditions" (rules doc)
    }

    /** Immediate terminal check after a mid-round elimination. Returns true if the game ended. */
    private boolean settleWin(TruearenaState.Draft d) {
        TruearenaState now = build(d);
        if (now.aliveTraitors().isEmpty()) {
            finish(d, "faithful");
            return true;
        }
        if (now.aliveTraitors().size() >= now.aliveFaithful().size()) {
            finish(d, "traitors");
            return true;
        }
        return false;
    }

    private void closeVoting(TruearenaState.Draft d) {
        List<String> missing = d.alive.stream().filter(id -> !d.voteLocked.contains(id)).toList();
        if (!missing.isEmpty()) {
            d.voteLocked.addAll(missing);
            if ("host_assigns".equals(d.config.afk())) {
                d.emit("AFK_PENDING", Map.of("ids", missing));
            } else {
                d.emit("AFK_ABSTAINED", Map.of("ids", missing));
            }
        }
        d.phase = "VoteReview";
        d.votesRevealed = 0;
        d.emit("ALL_VOTES_IN", Map.of("count", d.votes.size(), "veiled", veiled(build(d))));
    }

    private void tallyAndBanish(TruearenaState.Draft d) {
        if (d.votes.isEmpty()) {
            d.emit("NO_BANISH", Map.of("reason", "no_votes"));
            d.phase = "WinCheck";
            return;
        }
        Map<String, Integer> tally = new LinkedHashMap<>();
        for (String t : d.votes.values()) {
            tally.merge(t, 1, Integer::sum);
        }
        int max = tally.values().stream().mapToInt(Integer::intValue).max().orElse(0);
        List<String> tied = tally.entrySet().stream().filter(e -> e.getValue() == max).map(Map.Entry::getKey).sorted().toList();

        String banished;
        if (tied.size() == 1) {
            banished = tied.get(0);
        } else {
            String rule = d.config.tieBreak();
            if ("no_elimination".equals(rule)) {
                d.emit("TIE_NO_ELIMINATION", Map.of("tied", tied));
                d.phase = "WinCheck";
                clearBallot(d);
                return;
            }
            // revote / random / sudden_death / host_decides / trial_of_two:
            // v1 resolves deterministically among the tied players; the sub-phases
            // (sudden death, trial of two) are UI beats layered on later.
            RandomSource rng = RandomSource.seeded(d.seed + d.round * 131L + d.eliminationIndex);
            banished = tied.get(rng.nextInt(tied.size()));
            d.emit("TIE_RESOLVED", Map.of("method", rule, "tied", tied, "chosen", banished));
        }
        eliminate(d, banished, "banish");
        d.emit("BANISHED", Map.of("id", banished, "votes", max));
        clearBallot(d);
        d.phase = "WinCheck";
    }

    private void clearBallot(TruearenaState.Draft d) {
        d.votes.clear();
        d.voteLocked.clear();
        d.votesRevealed = 0;
    }

    private void winCheckStep(TruearenaState.Draft d) {
        TruearenaState now = build(d);
        if (now.aliveTraitors().isEmpty()) {
            if (TwistRegistry.recruitEligible(d)) {
                recruit(d);
                d.round++;
                goNight(d);
                return;
            }
            finish(d, "faithful");
            return;
        }
        if (now.aliveTraitors().size() >= now.aliveFaithful().size()) {
            finish(d, "traitors");
            return;
        }
        d.round++;
        goNight(d);
    }

    private void recruit(TruearenaState.Draft d) {
        TruearenaState now = build(d);
        List<String> pool = now.aliveFaithful();
        RandomSource rng = RandomSource.seeded(d.seed + 977L + d.round);
        String chosen = pool.get(rng.nextInt(pool.size()));
        d.roles.put(chosen, TruearenaState.RECRUITED);
        d.recruitDone = true;
        d.emitToPlayer("RECRUITED_AS_TRAITOR", Map.of("reason", "hidden_legacy"), chosen);
        d.emit("HIDDEN_LEGACY", Map.of("triggered", true)); // no identity in the public payload
    }

    private void finish(TruearenaState.Draft d, String side) {
        Map<String, String> outcome = new LinkedHashMap<>();
        for (String id : d.players) {
            boolean traitorish = TruearenaState.TRAITOR.equals(d.roles.get(id)) || TruearenaState.RECRUITED.equals(d.roles.get(id));
            String won = (traitorish ? "traitors" : "faithful").equals(side) ? "won" : "lost";
            outcome.put(id, won);
        }
        d.win = new WinResult(side, outcome);
        d.phase = "Results";
        d.emit("GAME_OVER", Map.of("winningSide", side, "rounds", d.round));
        d.emit("FULL_REVEAL", Map.of(
                "roles", new LinkedHashMap<>(d.roles),
                "eliminated", List.copyOf(d.eliminatedLog),
                "causes", new LinkedHashMap<>(d.eliminationCause)));
    }

    private void eliminate(TruearenaState.Draft d, String id, String cause) {
        d.alive.remove(id);
        d.eliminatedLog.add(id);
        d.eliminationCause.put(id, cause);
        boolean shown = roleShownAt(d.config.revealOnElimination(), d.eliminationIndex);
        d.eliminationRoleShown.put(id, shown);
        d.eliminationIndex++;
        Map<String, Object> p = new LinkedHashMap<>();
        p.put("id", id);
        p.put("cause", cause);
        p.put("roleShown", shown);
        p.put("role", shown ? d.roles.get(id) : null);
        d.emit("PLAYER_ELIMINATED", p);
    }

    private static boolean roleShownAt(String policy, int eliminationIndex) {
        return switch (policy == null ? "always" : policy) {
            case "never" -> false;
            case "alternating" -> eliminationIndex % 2 == 0; // starts public
            default -> true;
        };
    }

    private boolean veiled(TruearenaState s) {
        int threshold = s.config.veilThreshold();
        return threshold > 0 && s.alive.size() <= threshold;
    }

    private static TruearenaState build(TruearenaState.Draft d) {
        return d.build();
    }

    // ---------------------------------------------------------------- win + views

    @Override
    public Optional<WinResult> checkWinCondition(GameState state) {
        return Optional.ofNullable(((TruearenaState) state).win);
    }

    @Override
    public PlayerVisibleState visibleStateFor(GameState state, String playerId) {
        TruearenaState s = (TruearenaState) state;
        Map<String, Object> m = commonView(s);
        m.put("yourRole", s.roles.get(playerId));
        if (!s.finished() && s.isTraitor(playerId)) {
            m.put("fellowTraitors", s.roles.entrySet().stream()
                    .filter(e -> (TruearenaState.TRAITOR.equals(e.getValue()) || TruearenaState.RECRUITED.equals(e.getValue()))
                            && !e.getKey().equals(playerId))
                    .map(Map.Entry::getKey).toList());
            if ("Night".equals(s.phase)) {
                m.put("yourNightTarget", s.nightTarget);
            }
        }
        if (s.finished()) {
            m.put("allRoles", s.roles);
        }
        return new PlayerVisibleState(m);
    }

    @Override
    public PublicBroadcastState broadcastState(GameState state) {
        TruearenaState s = (TruearenaState) state;
        Map<String, Object> m = commonView(s);
        if (s.finished()) {
            m.put("allRoles", s.roles);
        }
        return new PublicBroadcastState(m);
    }

    /** Fields safe for anyone. Only roles of players whose role was <em>publicly revealed</em> at elimination. */
    private Map<String, Object> commonView(TruearenaState s) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("phase", s.phase);
        m.put("round", s.round);
        m.put("players", s.players);
        m.put("alive", s.alive.stream().toList());
        m.put("eliminated", s.eliminatedLog);
        m.put("causes", s.eliminationCause);
        Map<String, String> revealed = new LinkedHashMap<>();
        for (String id : s.eliminatedLog) {
            if (Boolean.TRUE.equals(s.eliminationRoleShown.get(id))) {
                revealed.put(id, s.roles.get(id));
            }
        }
        m.put("revealedRoles", revealed);
        m.put("voteProgress", Map.of("locked", s.voteLocked.size(), "total", s.alive.size()));
        m.put("veiled", s.config.veilThreshold() > 0 && s.alive.size() <= s.config.veilThreshold());
        return m;
    }

    @Override
    public List<GameEvent> drainEvents(GameState prev, GameState next) {
        List<GameEvent> a = ((TruearenaState) prev).events();
        List<GameEvent> b = ((TruearenaState) next).events();
        return new ArrayList<>(b.subList(a.size(), b.size()));
    }

    // ---------------------------------------------------------------- helpers

    private static void require(boolean ok, String code, String message) {
        if (!ok) {
            throw new RuleViolation(code, message);
        }
    }

    private static String str(String s) {
        return s == null ? "" : s;
    }
}
