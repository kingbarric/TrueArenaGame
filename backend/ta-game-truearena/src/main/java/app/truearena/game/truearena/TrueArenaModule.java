package app.truearena.game.truearena;

import app.truearena.engine.GameConfig;
import app.truearena.engine.GameEvent;
import app.truearena.engine.GameModule;
import app.truearena.engine.GameSettings;
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
    public boolean hasPrivatePlayerState() {
        return true;
    }

    @Override
    public List<Phase> definePhases(GameSettings settings) {
        GameConfig config = (GameConfig) settings;
        return List.of(
                Phase.untimed("RoleReveal"),
                new Phase("Night", config.timers().night()),
                Phase.untimed("MorningReveal"),
                new Phase("RoundTable", config.timers().roundTable()),
                new Phase("Vote", config.timers().vote()),
                new Phase("Revote", config.timers().vote()),
                new Phase("SuddenDeath", config.suddenDeathSeconds()),
                new Phase("Defense", config.timers().defense()),
                Phase.untimed("HostDecision"),
                // Real duration (not untimed) so an unresponsive host can't stall the game —
                // see closeVoting()/advance()'s "HostAssignVotes" case for the auto-abstain fallback.
                new Phase("HostAssignVotes", config.timers().vote()),
                Phase.untimed("VoteReview"),
                Phase.untimed("Elimination"),
                Phase.untimed("WinCheck"),
                Phase.untimed("Results")
        );
    }

    // ---------------------------------------------------------------- setup

    @Override
    public GameState initialState(List<String> playerIds, GameSettings settings, RandomSource rng) {
        GameConfig config = (GameConfig) settings;
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
        // Special-Faithful twists (secret_accusation, blackmail, silent_witness, double_agent)
        // share one running index into `shuffled` so two enabled at once never collide on
        // the same player. ConfigValidator only warns, not errors, if there aren't enough
        // Faithful for all of them — the `specialIdx < n` guard just skips assignment rather
        // than throwing in that case.
        int specialIdx = traitorCount;
        if (config.twistEnabled("secret_accusation") && specialIdx < n) {
            d.accuser = shuffled.get(specialIdx++);
            d.emitToPlayer("ACCUSATION_GRANTED", Map.of("defenseSeconds",
                    config.twistParams("secret_accusation").getOrDefault("defenseSeconds", 60)), d.accuser);
        }
        if (config.twistEnabled("blackmail") && specialIdx < n) {
            d.blackmailer = shuffled.get(specialIdx++);
            List<String> blackmailTargets = playerIds.stream().filter(id -> !id.equals(d.blackmailer)).toList();
            if (!blackmailTargets.isEmpty()) {
                d.blackmailTarget = blackmailTargets.get(rng.nextInt(blackmailTargets.size()));
                d.emitToPlayer("BLACKMAIL_INTEL",
                        Map.of("target", d.blackmailTarget, "side", d.roles.get(d.blackmailTarget)), d.blackmailer);
            }
        }
        if (config.twistEnabled("silent_witness") && specialIdx < n) {
            d.silentWitness = shuffled.get(specialIdx++);
        }
        if (config.twistEnabled("double_agent") && specialIdx < n) {
            d.doubleAgentCandidate = shuffled.get(specialIdx++);
            d.emitToRole("DOUBLE_AGENT_CANDIDATE", Map.of("id", d.doubleAgentCandidate), TruearenaState.TRAITOR);
        }
        if (config.twistEnabled("poisoned_gift")) {
            Object uses = config.twistParams("poisoned_gift").getOrDefault("uses", 1);
            d.giftUses = uses instanceof Number number ? Math.max(0, number.intValue()) : 1;
        }
        if (config.twistEnabled("false_reveal")) {
            Object uses = config.twistParams("false_reveal").getOrDefault("uses", 1);
            d.falseRevealUses = uses instanceof Number number ? Math.max(0, number.intValue()) : 1;
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
            case "NIGHT_GIFT" -> nightGift(d, s, action);
            case "CLAIM_SHIELD" -> claimShield(d, s, action);
            case "AWARD_IMMUNITY" -> awardImmunity(d, s, action);
            case "USE_IMMUNITY" -> useImmunity(d, s, action);
            case "ACCUSE" -> accuse(d, s, action);
            case "CHOOSE_TIE" -> chooseTie(d, s, action);
            case "CAST_VOTE" -> castVote(d, s, action);
            case "REVEAL_NEXT" -> revealNext(d, s);
            case "FALSE_REVEAL" -> falseReveal(d, s, action);
            case "SUBMIT_CONFESSIONAL" -> submitConfessional(d, s, action);
            case "CALL_SURVIVORS_CHOICE" -> callSurvivorsChoice(d, s, action);
            case "RECRUIT_DOUBLE_AGENT" -> recruitDoubleAgent(d, s, action);
            case "LAST_WILL" -> submitLastWill(d, s, action);
            case "HOST_ASSIGN_VOTE" -> hostAssignVote(d, s, action);
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
        require(!s.isTraitor(target), "BAD_TARGET", "night target must be a living Faithful");
        String second = a.str("secondTarget");
        if (second != null) {
            Integer after = s.config.nightKill().doubleAfterRound();
            require(after != null && after > 0 && s.round > after,
                    "DOUBLE_UNAVAILABLE", "a second murder is not available yet");
            require(!second.equals(target) && s.alive.contains(second) && !s.isTraitor(second),
                    "BAD_TARGET", "second target must be another living Faithful");
            d.secondNightSubmissions.put(a.actor(), second);
        } else {
            d.secondNightSubmissions.remove(a.actor());
        }
        d.nightSubmissions.put(a.actor(), target);
        d.nightTarget = target;
        d.emitToRole("NIGHT_TARGET_SET", Map.of("by", a.actor(), "target", target), TruearenaState.TRAITOR);

        List<String> livingTraitors = s.aliveTraitors();
        boolean allIn = d.nightSubmissions.keySet().containsAll(livingTraitors);
        boolean agreed = !s.config.nightKill().requireTraitorConsensus()
                || d.nightSubmissions.values().stream().distinct().count() == 1
                    && d.secondNightSubmissions.values().stream().distinct().count() <= 1;
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

    private void nightGift(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("Night".equals(d.phase), "WRONG_PHASE", "the gift is a night action");
        require(s.alive.contains(a.actor()) && s.isTraitor(a.actor()), "NOT_TRAITOR", "only a living Traitor can use the gift");
        require(s.config.twistEnabled("poisoned_gift") && d.giftUses > 0,
                "GIFT_UNAVAILABLE", "no poisoned gifts remain");
        String choice = a.str("choice");
        if ("direct_poison".equals(choice)) {
            String target = a.str("target");
            require(target != null && s.alive.contains(target) && !s.isTraitor(target),
                    "BAD_TARGET", "poison must target a living Faithful");
            d.poisonedPlayer = target;
            d.poisonDueRound = d.round + 1;
            d.emitToPlayer("POISONED", Map.of("dueRound", d.poisonDueRound), target);
            d.emit("DIRECT_POISON_USED", Map.of("dueRound", d.poisonDueRound));
        } else if ("shield".equals(choice)) {
            d.shieldAvailable = true;
            d.shieldPoisoned = RandomSource.seeded(d.seed + 991L + d.round).nextInt(2) == 0;
            d.emit("MYSTERY_SHIELD_OFFERED", Map.of());
        } else {
            throw new RuleViolation("BAD_GIFT", "choose direct_poison or shield");
        }
        d.giftUses--;
    }

    private void claimShield(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("RoundTable".equals(d.phase), "WRONG_PHASE", "claim the shield during discussion");
        require(d.shieldAvailable && s.alive.contains(a.actor()), "SHIELD_UNAVAILABLE", "no shield is available");
        d.shieldAvailable = false;
        d.shieldHolder = a.actor();
        d.emit("SHIELD_CLAIMED", Map.of("holder", a.actor()));
        if (d.shieldPoisoned) {
            d.poisonedPlayer = a.actor();
            d.poisonDueRound = d.round + 1;
            d.emitToPlayer("POISONED", Map.of("dueRound", d.poisonDueRound), a.actor());
        }
    }

    private void awardImmunity(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("RoundTable".equals(d.phase), "WRONG_PHASE", "award immunity during discussion");
        require(s.config.twistEnabled("immunity_coin") && d.immunityHolder == null,
                "IMMUNITY_UNAVAILABLE", "immunity has already been awarded");
        String target = a.str("target");
        require(target != null && s.alive.contains(target), "BAD_TARGET", "winner must be alive");
        d.immunityHolder = target;
        d.emit("IMMUNITY_AWARDED", Map.of("holder", target));
    }

    private void useImmunity(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("VoteReview".equals(d.phase) || "Elimination".equals(d.phase),
                "WRONG_PHASE", "use immunity before elimination");
        require(a.actor().equals(d.immunityHolder) && !d.immunitySpent,
                "IMMUNITY_UNAVAILABLE", "you do not hold an unused immunity coin");
        d.immunitySpent = true;
        d.emit("IMMUNITY_SPENT", Map.of("holder", a.actor()));
    }

    private void accuse(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("RoundTable".equals(d.phase), "WRONG_PHASE", "accuse during discussion");
        require(a.actor().equals(d.accuser) && !d.accusationUsed && s.alive.contains(a.actor()),
                "ACCUSATION_UNAVAILABLE", "you do not hold the accusation");
        String target = a.str("target");
        require(target != null && s.alive.contains(target) && !target.equals(a.actor()),
                "BAD_TARGET", "accuse another living player");
        d.accusationUsed = true;
        d.accused = target;
        d.phase = "Defense";
        d.emit("PUBLIC_ACCUSATION", Map.of("by", a.actor(), "accused", target));
    }

    private void chooseTie(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("HostDecision".equals(d.phase), "WRONG_PHASE", "there is no host decision now");
        String target = a.str("target");
        require(d.tieCandidates.contains(target), "BAD_TARGET", "choose one of the tied players");
        banish(d, target, 0);
    }

    private void castVote(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require(d.phase.equals("Vote") || d.phase.equals("Revote") || d.phase.equals("SuddenDeath"),
                "WRONG_PHASE", "voting is not open");
        require(s.alive.contains(a.actor()), "DEAD", "eliminated players cannot vote");
        require(!s.voteLocked.contains(a.actor()), "VOTE_LOCKED", "your vote is already locked");
        String target = a.str("target");
        require(target != null && s.alive.contains(target), "BAD_TARGET", "target must be a living player");
        require(!target.equals(a.actor()), "SELF_VOTE", "you cannot vote for yourself");
        if (!d.tieCandidates.isEmpty()) {
            require(d.tieCandidates.contains(target), "BAD_TARGET", "vote for a tied candidate");
        }
        d.votes.put(a.actor(), target);
        d.voteLocked.add(a.actor());
        d.emit("VOTE_PROGRESS", Map.of("locked", d.voteLocked.size(), "total", s.alive.size()));
        if (d.voteLocked.containsAll(s.alive)) {
            if ("Vote".equals(d.phase)) closeVoting(d);
            else tallyAndBanish(d);
        }
    }

    private void revealNext(TruearenaState.Draft d, TruearenaState s) {
        require(d.phase.equals("VoteReview"), "WRONG_PHASE", "nothing to reveal now");
        require(!"all_at_once".equals(s.config.voteReveal()),
                "SEQUENTIAL_ONLY", "voteReveal is all_at_once; nothing to step through");
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

    private void falseReveal(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("MorningReveal".equals(d.phase), "WRONG_PHASE", "false reveal is a morning action");
        require(s.isTraitor(a.actor()) && s.alive.contains(a.actor()), "NOT_TRAITOR", "only a living Traitor can force a false reveal");
        require(s.config.twistEnabled("false_reveal") && d.falseRevealUses > 0,
                "FALSE_REVEAL_UNAVAILABLE", "no false reveals remain");
        String target = a.str("target");
        require(target != null && s.eliminatedLog.contains(target), "BAD_TARGET", "target must be an eliminated player");
        require(TruearenaState.FAITHFUL.equals(s.roles.get(target)), "BAD_TARGET", "false reveal only works on an eliminated Faithful");
        require(Boolean.TRUE.equals(s.eliminationRoleShown.get(target)), "BAD_TARGET", "that role isn't currently shown");
        d.eliminationRoleShown.put(target, false);
        d.falseRevealUses--;
        d.emit("FALSE_REVEAL_USED", Map.of("id", target));
    }

    private void submitConfessional(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("RoundTable".equals(d.phase), "WRONG_PHASE", "confessionals are submitted during discussion");
        require(s.config.twistEnabled("confessional"), "CONFESSIONAL_UNAVAILABLE", "confessional is not enabled");
        require(s.alive.contains(a.actor()), "DEAD", "eliminated players cannot submit a confessional");
        require(!d.confessionals.containsKey(a.actor()), "CONFESSIONAL_USED", "you already submitted this round");
        String text = a.str("text");
        require(text != null && !text.isBlank(), "BAD_TEXT", "confessional text cannot be empty");
        d.confessionals.put(a.actor(), text);
        // No author field in the emitted event — that's what keeps this anonymous.
        d.emit("CONFESSIONAL_REVEALED", Map.of("text", text));
    }

    private void callSurvivorsChoice(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("RoundTable".equals(d.phase) || "Vote".equals(d.phase),
                "WRONG_PHASE", "survivors' choice is called during the round table or vote");
        require(s.config.twistEnabled("survivors_choice"), "SURVIVORS_CHOICE_UNAVAILABLE", "survivors' choice is not enabled");
        require(s.alive.size() <= 4, "SURVIVORS_CHOICE_UNAVAILABLE", "only available at the final four or fewer");
        require(s.alive.contains(a.actor()), "DEAD", "eliminated players cannot call it");
        d.survivorsChoiceVotes.add(a.actor());
        d.emit("SURVIVORS_CHOICE_PROGRESS", Map.of("votes", d.survivorsChoiceVotes.size(), "needed", s.alive.size()));
        if (d.survivorsChoiceVotes.containsAll(s.alive)) {
            TruearenaState now = build(d);
            String side = now.aliveTraitors().isEmpty() ? "faithful" : "traitors";
            d.emit("SURVIVORS_CHOICE_CALLED", Map.of("side", side));
            finish(d, side);
        }
    }

    private void recruitDoubleAgent(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("Night".equals(d.phase), "WRONG_PHASE", "recruiting is a night action");
        require(s.isTraitor(a.actor()) && s.alive.contains(a.actor()), "NOT_TRAITOR", "only a living Traitor can recruit");
        require(s.config.twistEnabled("double_agent") && !d.doubleAgentRecruited
                        && d.doubleAgentCandidate != null && s.alive.contains(d.doubleAgentCandidate),
                "DOUBLE_AGENT_UNAVAILABLE", "no double agent is available to recruit");
        d.roles.put(d.doubleAgentCandidate, TruearenaState.RECRUITED);
        d.doubleAgentRecruited = true;
        d.emitToPlayer("RECRUITED_AS_TRAITOR", Map.of("reason", "double_agent"), d.doubleAgentCandidate);
        d.emitToRole("DOUBLE_AGENT_RECRUITED", Map.of("id", d.doubleAgentCandidate), TruearenaState.TRAITOR);
    }

    private void submitLastWill(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("MorningReveal".equals(d.phase), "WRONG_PHASE", "a last will is left the morning after elimination");
        require(s.config.twistEnabled("last_will"), "LAST_WILL_UNAVAILABLE", "last will is not enabled");
        require(!s.alive.contains(a.actor()) && s.eliminatedLog.contains(a.actor()),
                "NOT_ELIMINATED", "only an eliminated player may leave a last will");
        require(!d.lastWills.containsKey(a.actor()), "LAST_WILL_USED", "you already left a last will");
        String text = a.str("text");
        require(text != null && !text.isBlank(), "BAD_TEXT", "last will text cannot be empty");
        int maxChars = 140;
        Object cfgMax = s.config.twistParams("last_will").get("maxChars");
        if (cfgMax instanceof Number number) {
            maxChars = Math.max(1, number.intValue());
        }
        String truncated = text.length() > maxChars ? text.substring(0, maxChars) : text;
        d.lastWills.put(a.actor(), truncated);
        d.emit("LAST_WILL_POSTED", Map.of("id", a.actor(), "text", truncated));
    }

    private void hostAssignVote(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("HostAssignVotes".equals(d.phase), "WRONG_PHASE", "no missing votes to assign right now");
        String voter = a.str("voterId");
        require(voter != null && s.alive.contains(voter) && !d.voteLocked.contains(voter),
                "BAD_TARGET", "that player already voted or is not in this game");
        String target = a.str("target");
        require(target != null && s.alive.contains(target) && !target.equals(voter),
                "BAD_TARGET", "target must be a living player other than the voter");
        d.votes.put(voter, target);
        d.voteLocked.add(voter);
        d.emit("VOTE_PROGRESS", Map.of("locked", d.voteLocked.size(), "total", s.alive.size()));
        List<String> stillMissing = d.alive.stream().filter(id -> !d.voteLocked.contains(id)).toList();
        if (stillMissing.isEmpty()) {
            d.phase = "VoteReview";
            d.votesRevealed = 0;
            d.emit("ALL_VOTES_IN", Map.of("count", d.votes.size(), "veiled", veiled(d)));
        }
    }

    // ---------------------------------------------------------------- phase machine

    private void advance(TruearenaState.Draft d, String from) {
        switch (from) {
            case "RoleReveal" -> goNight(d);
            case "Night" -> resolveNight(d);
            case "MorningReveal" -> {
                d.confessionals.clear();
                d.phase = "RoundTable";
                d.emit("ROUND_TABLE_OPEN", Map.of("round", d.round));
            }
            case "RoundTable" -> {
                openVote(d);
            }
            case "Defense" -> {
                if (d.tieDefensePending) {
                    openFinalVote(d);
                } else {
                    openVote(d);
                }
            }
            case "Vote" -> closeVoting(d);
            case "Revote", "SuddenDeath" -> tallyAndBanish(d);
            case "HostDecision" -> {
                if (d.tieCandidates.isEmpty()) throw new RuleViolation("BAD_PHASE", "no tied players");
                RandomSource rng = RandomSource.seeded(d.seed + d.round * 311L + d.eliminationIndex);
                banish(d, d.tieCandidates.get(rng.nextInt(d.tieCandidates.size())), 0);
            }
            case "HostAssignVotes" -> {
                List<String> stillMissing = d.alive.stream().filter(id -> !d.voteLocked.contains(id)).toList();
                if (!stillMissing.isEmpty()) {
                    d.voteLocked.addAll(stillMissing);
                    d.emit("AFK_ABSTAINED", Map.of("ids", stillMissing));
                }
                d.phase = "VoteReview";
                d.votesRevealed = 0;
                d.emit("ALL_VOTES_IN", Map.of("count", d.votes.size(), "veiled", veiled(d)));
            }
            case "VoteReview" -> {
                // Unconditional bulk-reveal-then-advance regardless of voteReveal — this is the
                // host's ADVANCE_PHASE escape hatch and stays available in every mode; a
                // `sequential` game normally gets here one REVEAL_NEXT at a time instead (see
                // closeVoting()'s `all_at_once` branch for that mode's own auto-reveal path).
                if (!veiled(d)) {
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

    private void openVote(TruearenaState.Draft d) {
        d.phase = "Vote";
        d.votes.clear();
        d.voteLocked.clear();
        d.votesRevealed = 0;
        d.tieCandidates.clear();
        d.tieStage = 0;
        d.emit("MICS_FORCE_MUTED", Map.of());
    }

    /**
     * trial_of_two's final vote: reuses the Vote phase but, unlike {@link #openVote},
     * deliberately keeps {@code tieCandidates} set (so {@link #castVote}'s existing
     * tie-restriction scopes this vote to just the two defended players) and leaves
     * {@code tieStage} at 1 (so a repeat tie falls to {@code secondTie}, not another
     * trial_of_two loop).
     */
    private void openFinalVote(TruearenaState.Draft d) {
        d.phase = "Vote";
        d.votes.clear();
        d.voteLocked.clear();
        d.votesRevealed = 0;
        d.tieDefensePending = false;
        d.emit("MICS_FORCE_MUTED", Map.of());
        d.emit("FINAL_VOTE_OPEN", Map.of("candidates", d.tieCandidates));
    }

    private void goNight(TruearenaState.Draft d) {
        d.phase = "Night";
        d.nightSubmissions.clear();
        d.secondNightSubmissions.clear();
        d.nightTarget = null;
        d.survivorsChoiceVotes.clear();
        d.emit("NIGHT_FALLS", Map.of("round", d.round));
    }

    private void resolveNight(TruearenaState.Draft d) {
        boolean opensDry = d.round == 1 && !d.config.nightKill().opensWithKill();
        List<String> eliminated = new ArrayList<>();
        if (d.poisonedPlayer != null && d.poisonDueRound <= d.round) {
            if (d.alive.contains(d.poisonedPlayer)) {
                eliminate(d, d.poisonedPlayer, "poison");
                eliminated.add(d.poisonedPlayer);
            }
            d.poisonedPlayer = null;
            d.poisonDueRound = 0;
        }
        if (opensDry || d.nightSkipUsed && d.nightTarget == null) {
            d.emit("NO_MURDER", Map.of("round", d.round, "reason", opensDry ? "opening_night" : "skipped"));
        } else if (d.config.nightKill().requireTraitorConsensus()
                && d.nightSubmissions.values().stream().distinct().count() > 1) {
            d.emit("NO_MURDER", Map.of("round", d.round, "reason", "no_consensus"));
        } else if (d.nightTarget != null && d.alive.contains(d.nightTarget)) {
            if (d.nightTarget.equals(d.shieldHolder) && !d.shieldPoisoned) {
                d.emit("SHIELD_BLOCKED_MURDER", Map.of("holder", d.shieldHolder));
                d.shieldHolder = null;
            } else {
                eliminate(d, d.nightTarget, "murder");
                eliminated.add(d.nightTarget);
                notifySilentWitness(d, d.nightTarget);
            }
            String second = d.secondNightSubmissions.values().stream().findFirst().orElse(null);
            if (second != null && d.alive.contains(second)) {
                if (second.equals(d.shieldHolder) && !d.shieldPoisoned) {
                    d.emit("SHIELD_BLOCKED_MURDER", Map.of("holder", d.shieldHolder));
                    d.shieldHolder = null;
                } else {
                    eliminate(d, second, "murder");
                    eliminated.add(second);
                    notifySilentWitness(d, second);
                }
            }
        } else {
            d.emit("NO_MURDER", Map.of("round", d.round, "reason", "no_target"));
        }
        d.nightSubmissions.clear();
        d.secondNightSubmissions.clear();
        d.nightTarget = null;
        d.phase = "MorningReveal";
        Map<String, Object> p = new LinkedHashMap<>();
        p.put("round", d.round);
        p.put("eliminated", eliminated.isEmpty() ? null : eliminated.getFirst());
        p.put("eliminatedIds", eliminated);
        d.emit("MORNING_REVEAL", p);
        settleWin(d); // "after each murder ... check the win conditions" (rules doc)
    }

    /** Only living Traitors can ever be night-targeted, so any murder victim is Faithful by construction. */
    private void notifySilentWitness(TruearenaState.Draft d, String victimId) {
        if (d.config.twistEnabled("silent_witness") && d.silentWitness != null && d.alive.contains(d.silentWitness)) {
            d.emitToPlayer("SILENT_WITNESS_INTEL", Map.of("victim", victimId), d.silentWitness);
        }
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
        if (!missing.isEmpty() && "host_assigns".equals(d.config.afk())) {
            // Ballot stays genuinely open for these ids — HOST_ASSIGN_VOTE fills them in,
            // or the HostAssignVotes phase timer auto-abstains whoever's still missing.
            d.phase = "HostAssignVotes";
            d.emit("AFK_PENDING", Map.of("ids", missing));
            return;
        }
        if (!missing.isEmpty()) {
            d.voteLocked.addAll(missing);
            d.emit("AFK_ABSTAINED", Map.of("ids", missing));
        }
        d.phase = "VoteReview";
        d.votesRevealed = 0;
        d.emit("ALL_VOTES_IN", Map.of("count", d.votes.size(), "veiled", veiled(d)));
        // all_at_once: reveal immediately, no waiting on REVEAL_NEXT or a host force-advance —
        // that's the one real behavioral difference from `sequential` (see revealNext()'s guard).
        if ("all_at_once".equals(d.config.voteReveal()) && !veiled(d)) {
            while (d.votesRevealed < d.votes.size()) {
                String voter = new ArrayList<>(d.votes.keySet()).get(d.votesRevealed++);
                d.emit("VOTE_REVEALED", Map.of("voter", voter, "target", d.votes.get(voter)));
            }
            d.phase = "Elimination";
        }
    }

    private void tallyAndBanish(TruearenaState.Draft d) {
        if (d.votes.isEmpty()) {
            d.emit("NO_BANISH", Map.of("reason", "no_votes"));
            d.phase = "WinCheck";
            d.tieCandidates.clear();
            clearBallot(d);
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
        } else if (d.tieStage == 0 && d.config.twistEnabled("trial_of_two")) {
            // Twist takes precedence over whatever `tieBreak` is configured (docs/GAME_CONFIG.md
            // compatibility rule: "the twist wins"). Reuses the existing Defense phase/timer;
            // advance()'s Defense case routes here via tieDefensePending instead of the normal
            // accusation-reply openVote().
            d.tieCandidates = new ArrayList<>(tied);
            d.tieStage = 1;
            d.tieDefensePending = true;
            d.phase = "Defense";
            clearBallot(d);
            d.emit("TIE_REPLAY", Map.of("method", "trial_of_two", "tied", tied));
            return;
        } else {
            String rule = d.tieStage == 0 ? d.config.tieBreak() : d.config.secondTie();
            if ("no_elimination".equals(rule)) {
                d.emit("TIE_NO_ELIMINATION", Map.of("tied", tied));
                d.phase = "WinCheck";
                d.tieCandidates.clear();
                clearBallot(d);
                return;
            }
            if (d.tieStage == 0 && ("revote".equals(rule) || "sudden_death".equals(rule)
                    || "trial_of_two".equals(rule))) {
                d.tieCandidates = new ArrayList<>(tied);
                d.tieStage = 1;
                d.phase = "revote".equals(rule) ? "Revote" : "SuddenDeath";
                clearBallot(d);
                d.emit("TIE_REPLAY", Map.of("method", rule, "tied", tied));
                return;
            }
            if ("host_decides".equals(rule)) {
                d.tieCandidates = new ArrayList<>(tied);
                d.phase = "HostDecision";
                clearBallot(d);
                d.emit("TIE_HOST_DECISION", Map.of("tied", tied));
                return;
            }
            RandomSource rng = RandomSource.seeded(d.seed + d.round * 131L + d.eliminationIndex);
            banished = tied.get(rng.nextInt(tied.size()));
            d.emit("TIE_RESOLVED", Map.of("method", rule, "tied", tied, "chosen", banished));
        }
        banish(d, banished, max);
    }

    private void banish(TruearenaState.Draft d, String banished, int votes) {
        if (banished.equals(d.immunityHolder) && d.immunitySpent) {
            d.emit("IMMUNITY_BLOCKED_BANISH", Map.of("holder", banished));
            d.immunityHolder = null;
            d.immunitySpent = false;
        } else {
        eliminate(d, banished, "banish");
            d.emit("BANISHED", Map.of("id", banished, "votes", votes));
        }
        clearBallot(d);
        d.tieCandidates.clear();
        d.tieStage = 0;
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

    private static boolean veiled(TruearenaState s) {
        return veiled(s.config, s.alive.size());
    }

    private static boolean veiled(TruearenaState.Draft d) {
        return veiled(d.config, d.alive.size());
    }

    private static boolean veiled(GameConfig config, int livingPlayers) {
        int threshold = config.veilThreshold();
        return threshold > 0 && livingPlayers <= threshold;
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
        if (playerId.equals(s.accuser) && !s.accusationUsed) {
            m.put("canAccuse", true);
        }
        if (playerId.equals(s.blackmailer) && s.blackmailTarget != null) {
            m.put("blackmailIntel", Map.of("target", s.blackmailTarget, "side", s.roles.get(s.blackmailTarget)));
        }
        if (!s.finished() && s.isTraitor(playerId)) {
            m.put("giftUses", s.giftUses);
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
        m.put("preset", s.config.preset());
        m.put("round", s.round);
        m.put("tieCandidates", s.tieCandidates);
        m.put("accused", s.accused);
        m.put("shieldAvailable", s.shieldAvailable);
        m.put("shieldHolder", s.shieldHolder);
        m.put("immunityHolder", s.immunityHolder);
        m.put("immunitySpent", s.immunitySpent);
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
        m.put("lastWills", s.lastWills);
        m.put("voteProgress", Map.of("locked", s.voteLocked.size(), "total", s.alive.size()));
        m.put("veiled", s.config.veilThreshold() > 0 && s.alive.size() <= s.config.veilThreshold());
        if (s.finished()) m.put("winningSide", s.win.winningSide());
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
