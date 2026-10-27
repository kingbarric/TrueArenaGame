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
import java.util.Comparator;
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

    /**
     * The beats between the timed phases — role cards, the morning news, the
     * ballot, the banishment — run on short clocks of their own. They used to
     * be untimed, so the whole table waited for the host to tap on, and a host
     * who looked away left the game frozen on a reveal screen. The host can
     * still tap on early ({@code ADVANCE_PHASE}), pause the clock, or add time.
     */
    static final int REVEAL_SECONDS = 20;
    /** The morning news, and the time an eliminated player has to leave a last will. */
    static final int MORNING_SECONDS = 30;
    static final int MORNING_LAST_WILL_SECONDS = 45;
    /** Long enough for the host to step through a sequential reveal one ballot at a time. */
    static final int VOTE_REVIEW_SECONDS = 60;
    /** The Ghost Jury's deliberation over a tie. */
    static final int JURY_SECONDS = 30;

    /** What a pie can look like — honest, or not (the clue is true about two times in three). */
    static final List<String> SHIELD_CLUES = List.of(
            "A golden crust that smells of honey",
            "Still warm, wrapped in a clean white cloth",
            "Dusted with sugar — someone took care over this one",
            "It smells of apples and cinnamon");
    static final List<String> POISON_CLUES = List.of(
            "A faint smell of bitter almonds",
            "The crust is cracked and oddly dark",
            "A thin green stain under the crust",
            "It sat out in the cold all night");

    @Override
    public List<Phase> definePhases(GameSettings settings) {
        GameConfig config = (GameConfig) settings;
        return List.of(
                new Phase("RoleReveal", REVEAL_SECONDS),
                new Phase("Night", config.timers().night()),
                new Phase("MorningReveal",
                        config.twistEnabled("last_will") ? MORNING_LAST_WILL_SECONDS : MORNING_SECONDS),
                new Phase("RoundTable", config.timers().roundTable()),
                new Phase("Vote", config.timers().vote()),
                new Phase("Revote", config.timers().vote()),
                new Phase("SuddenDeath", config.suddenDeathSeconds()),
                new Phase("Defense", config.timers().defense()),
                // Real durations (not untimed) so an unresponsive host can't stall the game —
                // a tie the host never breaks falls to a seeded random pick (advance()'s
                // "HostDecision" case), and missing ballots auto-abstain ("HostAssignVotes").
                new Phase("HostDecision", config.timers().vote()),
                new Phase("HostAssignVotes", config.timers().vote()),
                new Phase("VoteReview", VOTE_REVIEW_SECONDS),
                new Phase("Elimination", REVEAL_SECONDS),
                new Phase("WinCheck", REVEAL_SECONDS),
                new Phase("GhostJury", JURY_SECONDS),
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
        if (config.twistEnabled("seer_lantern") && specialIdx < n) {
            d.seer = shuffled.get(specialIdx++);
            d.emitToPlayer("SEER_GRANTED", Map.of(), d.seer);
        }
        if (config.twistEnabled("poisoned_gift")) {
            Object uses = config.twistParams("poisoned_gift").getOrDefault("uses", 1);
            d.giftUses = uses instanceof Number number ? Math.max(0, number.intValue()) : 1;
        }
        if (config.twistEnabled("poisoned_pie")) {
            Object uses = config.twistParams("poisoned_pie").getOrDefault("uses", 1);
            d.pieUses = uses instanceof Number number ? Math.max(0, number.intValue()) : 1;
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
            case "RECRUIT_OFFER" -> recruitOffer(d, s, action);
            case "RECRUIT_ANSWER" -> recruitAnswer(d, s, action);
            case "BAKE_PIE" -> bakePie(d, s, action);
            case "TAKE_PIE" -> takePie(d, s, action);
            case "ALIBI" -> alibi(d, s, action);
            case "SEER_LANTERN" -> lantern(d, s, action);
            case "PLACE_SPOT" -> placeSpot(d, s, action);
            case "PASS_SPOT" -> passSpot(d, s, action);
            case "LAST_STAND" -> lastStand(d, s, action);
            case "GHOST_VOTE" -> ghostVote(d, s, action);
            case "CROWD_VOTE" -> crowdVote(d, s, action);
            case "ADVANCE_PHASE" -> advance(d, d.phase);
            case "END_GAME" -> endByHost(d);
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
        require(!s.recruitNight, "RECRUITING_TONIGHT", "tonight the Traitors are recruiting, not murdering");
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
        maybeResolveNight(d);
    }

    /**
     * The night ends early once everyone it needs has acted: the Traitors (agreed, or
     * recruiting, or skipping), everyone's alibi in that mode, and the Seer's lantern.
     * Otherwise the clock ends it.
     */
    private void maybeResolveNight(TruearenaState.Draft d) {
        if (traitorsDone(d) && othersDone(d)) resolveNight(d);
    }

    private static boolean traitorsDone(TruearenaState.Draft d) {
        if (d.recruitNight || d.skipTonight) return true;
        List<String> living = build(d).aliveTraitors();
        boolean allIn = d.nightSubmissions.keySet().containsAll(living);
        boolean agreed = !d.config.nightKill().requireTraitorConsensus()
                || d.nightSubmissions.values().stream().distinct().count() == 1
                    && d.secondNightSubmissions.values().stream().distinct().count() <= 1;
        return allIn && agreed;
    }

    private static boolean othersDone(TruearenaState.Draft d) {
        if (d.config.twistEnabled("alibis") && !d.alibis.keySet().containsAll(d.alive)) return false;
        return !seerPending(d);
    }

    private static boolean seerPending(TruearenaState.Draft d) {
        return d.config.twistEnabled("seer_lantern") && d.seer != null && d.alive.contains(d.seer)
                && TruearenaState.FAITHFUL.equals(d.roles.get(d.seer)) && !d.lanternUsed && !d.lanternTonight;
    }

    private void nightSkip(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require(d.phase.equals("Night"), "WRONG_PHASE", "skip is Night-only");
        require(s.isTraitor(a.actor()) && s.alive.contains(a.actor()), "NOT_TRAITOR", "only living Traitors may skip");
        require(s.config.nightKill().allowSkip() && !s.nightSkipUsed, "SKIP_UNAVAILABLE", "no skip left");
        d.nightSkipUsed = true;
        d.skipTonight = true;
        d.nightTarget = null;
        maybeResolveNight(d);
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
            require(!d.poisonDue.containsKey(target), "BAD_TARGET", "that player is already poisoned");
            d.poisonDue.put(target, d.round + 1);
            d.emitToPlayer("POISONED", Map.of("dueRound", d.round + 1), target);
            d.emit("DIRECT_POISON_USED", Map.of("dueRound", d.round + 1));
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
            d.poisonDue.merge(a.actor(), d.round + 1, Math::min);
            d.emitToPlayer("POISONED", Map.of("dueRound", d.poisonDue.get(a.actor())), a.actor());
        }
    }

    private void awardImmunity(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("RoundTable".equals(d.phase), "WRONG_PHASE", "award immunity during discussion");
        require(s.config.twistEnabled("immunity_coin") && d.immunityHolder == null && !d.immunityConsumed,
                "IMMUNITY_UNAVAILABLE", "immunity has already been awarded");
        String target = a.str("target");
        require(target != null && s.alive.contains(target), "BAD_TARGET", "winner must be alive");
        d.immunityHolder = target;
        d.emit("IMMUNITY_AWARDED", Map.of("holder", target));
    }

    private void useImmunity(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("VoteReview".equals(d.phase) || "Elimination".equals(d.phase),
                "WRONG_PHASE", "use immunity before elimination");
        require(a.actor().equals(d.immunityHolder) && !d.immunitySpent && s.alive.contains(a.actor()),
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
        require(!a.actor().equals(s.spotSilenced), "BLACK_SPOT", "the Black Spot took your vote this round");
        require(!s.voteLocked.contains(a.actor()), "VOTE_LOCKED", "your vote is already locked");
        String target = a.str("target");
        require(target != null && s.alive.contains(target), "BAD_TARGET", "target must be a living player");
        require(!target.equals(a.actor()), "SELF_VOTE", "you cannot vote for yourself");
        if (!d.tieCandidates.isEmpty()) {
            require(d.tieCandidates.contains(target), "BAD_TARGET", "vote for a tied candidate");
        }
        d.votes.put(a.actor(), target);
        d.voteLocked.add(a.actor());
        d.emit("VOTE_PROGRESS", Map.of("locked", d.voteLocked.size(), "total", voters(d).size()));
        if (d.voteLocked.containsAll(voters(d))) {
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

    /**
     * Arms the twist: the next banished Faithful whose role would be shown is
     * announced as unknown instead. It has to be armed before the banishment —
     * the old version hid a role the morning after, by which time every client
     * had already received it in PLAYER_ELIMINATED, so it hid nothing. Only the
     * Traitors are told it's armed.
     */
    private void falseReveal(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require(!"Night".equals(d.phase) && !"RoleReveal".equals(d.phase),
                "WRONG_PHASE", "arm the false reveal during the day, before the banishment");
        require(s.isTraitor(a.actor()) && s.alive.contains(a.actor()), "NOT_TRAITOR", "only a living Traitor can force a false reveal");
        require(s.config.twistEnabled("false_reveal") && d.falseRevealUses > 0,
                "FALSE_REVEAL_UNAVAILABLE", "no false reveals remain");
        require(!d.falseRevealArmed, "FALSE_REVEAL_ARMED", "the false reveal is already armed");
        d.falseRevealArmed = true;
        d.emitToRole("FALSE_REVEAL_ARMED", Map.of("by", a.actor()), TruearenaState.TRAITOR);
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

    // ---------------------------------------------------------------- the dynamics

    /**
     * Whether the Traitors may recruit tonight. They have to have lost one of their own —
     * never growing past their starting number — and afterwards there must still be two
     * Faithful for every Traitor, so recruiting closes by itself once five are left.
     */
    static boolean recruitOpen(TruearenaState s) {
        if (!s.config.twistEnabled("recruiting") || s.recruitOffer != null || s.recruitNight) return false;
        int traitors = s.aliveTraitors().size();
        if (traitors == 0 || traitors >= s.originalTraitors.size()) return false;
        if (traitors + 1 > s.alive.size() / 3) return false;
        return s.aliveFaithful().stream().anyMatch(id -> !s.recruitAsked.contains(id));
    }

    /** Tonight the Traitors recruit instead of murdering: the offer reaches its Faithful at dawn, anonymously. */
    private void recruitOffer(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("Night".equals(d.phase), "WRONG_PHASE", "the Traitors recruit at night");
        require(s.alive.contains(a.actor()) && s.isTraitor(a.actor()), "NOT_TRAITOR", "only a living Traitor can recruit");
        require(recruitOpen(s), "RECRUIT_UNAVAILABLE", "the Traitors can't recruit tonight");
        String target = a.str("target");
        require(target != null && s.alive.contains(target) && !s.isTraitor(target) && !s.recruitAsked.contains(target),
                "BAD_TARGET", "make the offer to a living Faithful who hasn't been asked");
        d.recruitNight = true;
        d.recruitOffer = target;
        d.recruitAsked.add(target);
        d.nightSubmissions.clear();
        d.secondNightSubmissions.clear();
        d.nightTarget = null;
        d.emitToRole("RECRUIT_CHOSEN", Map.of("by", a.actor(), "target", target), TruearenaState.TRAITOR);
        maybeResolveNight(d);
    }

    /**
     * Join, or refuse. Refusing doesn't expose anyone — the offer never said who sent it —
     * and whether the threat was real is the Traitors' call the next night.
     */
    private void recruitAnswer(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("MorningReveal".equals(d.phase) || "RoundTable".equals(d.phase) || "Defense".equals(d.phase),
                "WRONG_PHASE", "answer the offer before the vote");
        require(a.actor().equals(s.recruitOffer) && s.alive.contains(a.actor()), "NO_OFFER", "you have no offer to answer");
        boolean accept = Boolean.TRUE.equals(a.data().get("accept"));
        d.recruitOffer = null;
        if (accept) {
            d.roles.put(a.actor(), TruearenaState.RECRUITED);
            List<String> fellows = build(d).aliveTraitors().stream().filter(id -> !id.equals(a.actor())).toList();
            d.emitToPlayer("RECRUITED_AS_TRAITOR", Map.of("reason", "offer"), a.actor());
            d.emitToPlayer("FELLOW_TRAITORS", Map.of("ids", fellows), a.actor());
            d.emitToRole("RECRUIT_ACCEPTED", Map.of("id", a.actor()), TruearenaState.TRAITOR);
        } else {
            d.emitToRole("RECRUIT_REFUSED", Map.of("id", a.actor(), "reason", "refused"), TruearenaState.TRAITOR);
        }
    }

    /** Once a game the Traitors bake: a real shield, or poison. It's served at dawn with a clue. */
    private void bakePie(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("Night".equals(d.phase), "WRONG_PHASE", "pies are baked at night");
        require(s.alive.contains(a.actor()) && s.isTraitor(a.actor()), "NOT_TRAITOR", "only a living Traitor can bake");
        require(s.config.twistEnabled("poisoned_pie") && s.pieUses > 0 && !s.pieBaked && !s.pieAvailable
                && s.pieHolder == null, "PIE_UNAVAILABLE", "there's no pie to bake tonight");
        String filling = a.str("filling");
        require("shield".equals(filling) || "poison".equals(filling), "BAD_FILLING", "bake a shield or poison");
        d.pieBaked = true;
        d.piePoisoned = "poison".equals(filling);
        d.pieUses--;
        d.emitToRole("PIE_BAKED", Map.of("by", a.actor(), "filling", filling), TruearenaState.TRAITOR);
    }

    /** First come, first served. Whoever takes it finds out the next night. */
    private void takePie(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("RoundTable".equals(d.phase), "WRONG_PHASE", "the pie is taken at the round table");
        require(s.pieAvailable && s.alive.contains(a.actor()), "PIE_UNAVAILABLE", "there's no pie on the table");
        d.pieAvailable = false;
        d.pieHolder = a.actor();
        d.emit("PIE_TAKEN", Map.of("holder", a.actor()));
    }

    /** Where you were tonight, and with whom. Secret until morning; you can change it until then. */
    private void alibi(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("Night".equals(d.phase), "WRONG_PHASE", "alibis are given at night");
        require(s.config.twistEnabled("alibis"), "ALIBIS_UNAVAILABLE", "this mode has no alibis");
        require(s.alive.contains(a.actor()), "DEAD", "only the living give alibis");
        String with = a.str("with");
        require(with != null && s.alive.contains(with) && !with.equals(a.actor()), "BAD_TARGET", "name another living player");
        d.alibis.put(a.actor(), with);
        maybeResolveNight(d);
    }

    /** The Seer looks at one player's true side — once a game. No target keeps the lantern for another night. */
    private void lantern(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("Night".equals(d.phase), "WRONG_PHASE", "the lantern is lit at night");
        require(s.config.twistEnabled("seer_lantern") && a.actor().equals(s.seer) && s.alive.contains(a.actor())
                && !s.isTraitor(a.actor()) && !s.lanternUsed && !s.lanternTonight,
                "LANTERN_UNAVAILABLE", "you hold no lantern tonight");
        String target = a.str("target");
        d.lanternTonight = true;
        if (target != null) {
            require(s.alive.contains(target) && !target.equals(a.actor()), "BAD_TARGET", "look at another living player");
            String side = s.isTraitor(target) ? "traitor" : "faithful";
            d.lanternUsed = true;
            d.visions.put(target, side);
            d.emitToPlayer("LANTERN_VISION", Map.of("target", target, "side", side), a.actor());
        }
        maybeResolveNight(d);
    }

    /** The Traitors mark someone. At dawn the whole table sees who holds the Black Spot. */
    private void placeSpot(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("Night".equals(d.phase), "WRONG_PHASE", "the Black Spot is placed at night");
        require(s.alive.contains(a.actor()) && s.isTraitor(a.actor()), "NOT_TRAITOR", "only a living Traitor can place it");
        require(s.config.twistEnabled("black_spot") && s.spotPending == null, "SPOT_UNAVAILABLE", "the Black Spot is already placed tonight");
        String target = a.str("target");
        require(target != null && s.alive.contains(target) && !target.equals(a.actor()), "BAD_TARGET", "mark another living player");
        d.spotPending = target;
        d.emitToRole("BLACK_SPOT_CHOSEN", Map.of("by", a.actor(), "target", target), TruearenaState.TRAITOR);
    }

    /** Pass it on — never to someone who has already held it today. Every pass is a public clue. */
    private void passSpot(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("MorningReveal".equals(d.phase) || "RoundTable".equals(d.phase), "WRONG_PHASE", "pass the Black Spot before the vote");
        require(a.actor().equals(s.spotHolder) && s.alive.contains(a.actor()), "NOT_HOLDER", "you don't hold the Black Spot");
        String to = a.str("to");
        require(to != null && s.alive.contains(to) && !s.spotChain.contains(to), "BAD_TARGET",
                "pass it to someone who hasn't held it today");
        d.spotHolder = to;
        d.spotChain.add(to);
        d.emit("BLACK_SPOT_PASSED", Map.of("from", a.actor(), "to", to));
    }

    /** At the final four: give up your place to show everyone one player's true side. Once a game. */
    private void lastStand(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("RoundTable".equals(d.phase), "WRONG_PHASE", "a Last Stand is made at the round table");
        require(s.config.twistEnabled("last_stand") && !s.lastStandUsed && s.alive.size() <= 4,
                "LAST_STAND_UNAVAILABLE", "a Last Stand is only possible at the final four");
        require(s.alive.contains(a.actor()), "DEAD", "only someone still at the table can make a stand");
        String target = a.str("target");
        require(target != null && s.alive.contains(target) && !target.equals(a.actor()), "BAD_TARGET", "choose another living player");
        String side = s.isTraitor(target) ? "traitor" : "faithful";
        d.lastStandUsed = true;
        d.standReveal = new LinkedHashMap<>(Map.of("by", a.actor(), "target", target, "side", side));
        d.emit("LAST_STAND", Map.of("by", a.actor(), "target", target, "side", side));
        eliminate(d, a.actor(), "last_stand");
        settleWin(d);
    }

    /** A ghost's verdict on a tie. Super Faithful count double — silently. */
    private void ghostVote(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require("GhostJury".equals(d.phase), "WRONG_PHASE", "the Ghost Jury isn't sitting");
        List<String> ghosts = s.ghosts();
        require(ghosts.contains(a.actor()), "NOT_A_GHOST", "only Faithful who are out sit on the Ghost Jury");
        String target = a.str("target");
        require(d.tieCandidates.contains(target), "BAD_TARGET", "choose one of the tied players");
        d.juryVotes.put(a.actor(), target);
        if (d.juryVotes.keySet().containsAll(ghosts)) resolveJury(d);
    }

    /**
     * The crowd's suspicion: spectators, and Faithful who are out. Living players can't
     * join it, and nor can a Traitor who's out. Each counts once; the table only ever
     * sees the total.
     */
    private void crowdVote(TruearenaState.Draft d, TruearenaState s, PlayerAction a) {
        require(s.config.twistEnabled("crowd_hunch"), "HUNCH_UNAVAILABLE", "this game has no crowd's hunch");
        require(!"RoleReveal".equals(d.phase), "WRONG_PHASE", "the crowd hasn't seen enough yet");
        require(!s.alive.contains(a.actor()), "PLAYING", "players at the table can't join the crowd");
        require(!s.players.contains(a.actor()) || !s.isTraitor(a.actor()), "NOT_A_GHOST",
                "only spectators and Faithful who are out join the crowd");
        String target = a.str("target");
        require(target != null && s.alive.contains(target), "BAD_TARGET", "suspect a living player");
        d.crowdVotes.put(a.actor(), target);
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
        require(voter != null && voters(d).contains(voter) && !d.voteLocked.contains(voter),
                "BAD_TARGET", "that player already voted or is not in this game");
        String target = a.str("target");
        require(target != null && s.alive.contains(target) && !target.equals(voter),
                "BAD_TARGET", "target must be a living player other than the voter");
        d.votes.put(voter, target);
        d.voteLocked.add(voter);
        d.emit("VOTE_PROGRESS", Map.of("locked", d.voteLocked.size(), "total", voters(d).size()));
        List<String> stillMissing = voters(d).stream().filter(id -> !d.voteLocked.contains(id)).toList();
        if (stillMissing.isEmpty()) {
            enterVoteReview(d);
        }
    }

    // ---------------------------------------------------------------- phase machine

    private void advance(TruearenaState.Draft d, String from) {
        switch (from) {
            case "RoleReveal" -> goNight(d);
            case "Night" -> resolveNight(d);
            case "GhostJury" -> resolveJury(d);
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
                List<String> stillMissing = voters(d).stream().filter(id -> !d.voteLocked.contains(id)).toList();
                if (!stillMissing.isEmpty()) {
                    d.voteLocked.addAll(stillMissing);
                    d.emit("AFK_ABSTAINED", Map.of("ids", stillMissing));
                }
                enterVoteReview(d);
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
        endRoundTable(d);
        d.phase = "Vote";
        d.votes.clear();
        d.voteLocked.clear();
        d.votesRevealed = 0;
        d.tieCandidates.clear();
        d.tieStage = 0;
        d.juryDone = false;
        d.emit("MICS_FORCE_MUTED", Map.of());
    }

    /**
     * The round table is over: an unanswered offer counts as a refusal, a pie nobody
     * took spoils, and whoever holds the Black Spot loses their vote.
     */
    private void endRoundTable(TruearenaState.Draft d) {
        if (d.recruitOffer != null) {
            d.emitToRole("RECRUIT_REFUSED", Map.of("id", d.recruitOffer, "reason", "no_answer"), TruearenaState.TRAITOR);
            d.emitToPlayer("RECRUIT_EXPIRED", Map.of(), d.recruitOffer);
            d.recruitOffer = null;
        }
        if (d.pieAvailable) {
            d.pieAvailable = false;
            d.emit("PIE_SPOILED", Map.of("filling", d.piePoisoned ? "poison" : "shield"));
        }
        if (d.spotHolder != null && d.alive.contains(d.spotHolder) && d.spotSilenced == null) {
            d.spotSilenced = d.spotHolder;
            d.emit("BLACK_SPOT_SILENCED", Map.of("holder", d.spotHolder));
        }
    }

    /** Who may vote today: everyone alive, except the one the Black Spot silenced. */
    private static List<String> voters(TruearenaState.Draft d) {
        return d.alive.stream().filter(id -> !id.equals(d.spotSilenced)).toList();
    }

    /**
     * trial_of_two's final vote: reuses the Vote phase but, unlike {@link #openVote},
     * deliberately keeps {@code tieCandidates} set (so {@link #castVote}'s existing
     * tie-restriction scopes this vote to just the two defended players) and leaves
     * {@code tieStage} at 1 (so a repeat tie falls to {@code secondTie}, not another
     * trial_of_two loop).
     */
    private void openFinalVote(TruearenaState.Draft d) {
        endRoundTable(d);
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
        d.accused = null; // yesterday's accusation is over
        d.alibis.clear();
        d.lanternTonight = false;
        d.recruitNight = false;
        d.skipTonight = false;
        d.spotPending = null;
        d.spotHolder = null;
        d.spotChain.clear();
        d.spotSilenced = null;
        d.crowdVotes.clear();
        d.juryDone = false;
        d.emit("NIGHT_FALLS", Map.of("round", d.round));
    }

    /**
     * Dawn. Poison takes whoever it was due to take, the pie someone took yesterday shows
     * what it was, tonight's murder lands (or the Traitors were recruiting instead), and the
     * morning brings its news: a clue, the alibis, the Black Spot and a fresh pie.
     */
    private void resolveNight(TruearenaState.Draft d) {
        boolean skipped = d.skipTonight;
        boolean opensDry = d.round == 1 && !d.config.nightKill().opensWithKill();
        List<String> eliminated = new ArrayList<>();
        List<String> murdered = new ArrayList<>();
        for (String poisoned : List.copyOf(d.poisonDue.keySet())) {
            if (d.poisonDue.get(poisoned) <= d.round) {
                if (d.alive.contains(poisoned)) {
                    eliminate(d, poisoned, "poison");
                    eliminated.add(poisoned);
                }
                d.poisonDue.remove(poisoned);
            }
        }
        // Yesterday's pie: poison takes its eater now; a real one guards them tonight.
        String pieGuard = null;
        if (d.pieHolder != null && d.alive.contains(d.pieHolder)) {
            if (d.piePoisoned) {
                eliminate(d, d.pieHolder, "poison");
                eliminated.add(d.pieHolder);
                d.emit("PIE_REVEALED", Map.of("holder", d.pieHolder, "filling", "poison"));
            } else {
                pieGuard = d.pieHolder;
            }
        }
        if (d.recruitNight) {
            d.emit("NO_MURDER", Map.of("round", d.round, "reason", "recruiting"));
        } else if (opensDry || skipped) {
            d.emit("NO_MURDER", Map.of("round", d.round, "reason", opensDry ? "opening_night" : "skipped"));
        } else if (d.config.nightKill().requireTraitorConsensus()
                && d.nightSubmissions.values().stream().distinct().count() > 1) {
            d.emit("NO_MURDER", Map.of("round", d.round, "reason", "no_consensus"));
        } else if (d.nightTarget != null && d.alive.contains(d.nightTarget)) {
            List<String> targets = new ArrayList<>(List.of(d.nightTarget));
            String second = d.secondNightSubmissions.values().stream().findFirst().orElse(null);
            if (second != null) targets.add(second);
            for (String target : targets) {
                if (!d.alive.contains(target)) continue;
                if (target.equals(d.shieldHolder) && !d.shieldPoisoned) {
                    d.emit("SHIELD_BLOCKED_MURDER", Map.of("holder", d.shieldHolder));
                    d.shieldHolder = null;
                } else if (target.equals(pieGuard)) {
                    d.emit("PIE_SAVED", Map.of("holder", pieGuard));
                } else {
                    eliminate(d, target, "murder");
                    eliminated.add(target);
                    murdered.add(target);
                    notifySilentWitness(d, target);
                }
            }
        } else {
            d.emit("NO_MURDER", Map.of("round", d.round, "reason", "no_target"));
        }
        if (pieGuard != null) {
            d.emit("PIE_REVEALED", Map.of("holder", pieGuard, "filling", "shield"));
        }
        d.pieHolder = null;
        for (String victim : murdered) {
            crimeClue(d, victim);
        }
        // Tonight's offer reaches its Faithful — without saying who sent it.
        if (d.recruitOffer != null) {
            if (d.alive.contains(d.recruitOffer)) {
                d.emitToPlayer("RECRUIT_OFFER", Map.of("round", d.round), d.recruitOffer);
            } else {
                d.emitToRole("RECRUIT_REFUSED", Map.of("id", d.recruitOffer, "reason", "gone"), TruearenaState.TRAITOR);
                d.recruitOffer = null;
            }
        }
        if (d.config.twistEnabled("alibis")) {
            d.alibiBoard = new LinkedHashMap<>(d.alibis);
            d.emit("ALIBIS_REVEALED", Map.of("round", d.round, "alibis", Map.copyOf(d.alibiBoard)));
            d.alibis.clear();
        }
        if (d.spotPending != null) {
            if (d.alive.contains(d.spotPending)) {
                d.spotHolder = d.spotPending;
                d.spotChain = new ArrayList<>(List.of(d.spotPending));
                d.emit("BLACK_SPOT_MARKED", Map.of("holder", d.spotPending));
            }
            d.spotPending = null;
        }
        if (d.pieBaked) {
            d.pieBaked = false;
            d.pieAvailable = true;
            d.pieClue = pieClue(d);
            d.emit("PIE_SERVED", Map.of("clue", d.pieClue));
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

    /** The pie's clue: true about two times in three — honest, or the other filling's look. */
    private static String pieClue(TruearenaState.Draft d) {
        RandomSource rng = RandomSource.seeded(d.seed + 4049L * d.round);
        Object truth = d.config.twistParams("poisoned_pie").getOrDefault("clueTruth", 0.67);
        double p = truth instanceof Number number ? number.doubleValue() : 0.67;
        boolean honest = rng.nextInt(100) < Math.round(p * 100);
        List<String> pool = honest == d.piePoisoned ? POISON_CLUES : SHIELD_CLUES;
        return pool.get(rng.nextInt(pool.size()));
    }

    /**
     * Every murder leaves one true but vague clue about the killers: how near one sat to
     * the victim, three names at least one of whom is a Traitor, or a Faithful a Traitor
     * voted for. Never a name on its own.
     */
    private void crimeClue(TruearenaState.Draft d, String victim) {
        if (!d.config.twistEnabled("crime_clues")) return;
        TruearenaState now = build(d);
        List<String> traitors = now.aliveTraitors();
        if (traitors.isEmpty()) return;
        RandomSource rng = RandomSource.seeded(d.seed + 7919L * d.round + d.eliminationIndex);
        int first = rng.nextInt(3);
        Map<String, Object> clue = null;
        for (int i = 0; i < 3 && clue == null; i++) {
            clue = switch ((first + i) % 3) {
                case 0 -> seatClue(d, victim, traitors, rng);
                case 1 -> trioClue(traitors, now.aliveFaithful(), rng);
                default -> voteClue(d, now, traitors);
            };
        }
        if (clue == null) return;
        clue.put("round", d.round);
        clue.put("victim", victim);
        d.crimeClues.add(clue);
        d.emit("CRIME_CLUE", new LinkedHashMap<>(clue));
    }

    /** "A Traitor sat within N seats of the victim" — counted round the table, either way. */
    private static Map<String, Object> seatClue(TruearenaState.Draft d, String victim, List<String> traitors, RandomSource rng) {
        int n = d.players.size();
        int at = d.players.indexOf(victim);
        if (at < 0 || n < 4) return null;
        int nearest = n;
        for (String t : traitors) {
            int gap = Math.abs(d.players.indexOf(t) - at);
            nearest = Math.min(nearest, Math.min(gap, n - gap));
        }
        Map<String, Object> clue = new LinkedHashMap<>();
        clue.put("kind", "seat");
        clue.put("within", Math.min(n / 2, nearest + rng.nextInt(2)));
        return clue;
    }

    /** "At least one of these three is a Traitor." */
    private static Map<String, Object> trioClue(List<String> traitors, List<String> faithful, RandomSource rng) {
        if (faithful.size() < 2) return null;
        List<String> pool = new ArrayList<>(faithful);
        rng.shuffle(pool);
        List<String> trio = new ArrayList<>(List.of(traitors.get(rng.nextInt(traitors.size())), pool.get(0), pool.get(1)));
        trio.sort(Comparator.naturalOrder()); // no order to read anything into
        Map<String, Object> clue = new LinkedHashMap<>();
        clue.put("kind", "trio");
        clue.put("ids", trio);
        return clue;
    }

    /** "A Traitor voted for X at the last vote" — X being Faithful. Never from a veiled ballot. */
    private static Map<String, Object> voteClue(TruearenaState.Draft d, TruearenaState now, List<String> traitors) {
        if (d.ballotHistory.isEmpty()) return null;
        Map<String, Object> last = d.ballotHistory.getLast();
        if (Boolean.TRUE.equals(last.get("veiled")) || !(last.get("votes") instanceof Map<?, ?> votes)) return null;
        for (String traitor : traitors.stream().sorted().toList()) {
            if (votes.get(traitor) instanceof String target && !now.isTraitor(target)) {
                Map<String, Object> clue = new LinkedHashMap<>();
                clue.put("kind", "vote");
                clue.put("target", target);
                return clue;
            }
        }
        return null;
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
            // Same rule as winCheckStep: the last original Traitor falling before the
            // trigger recruits instead of ending — including to poison overnight.
            if (TwistRegistry.recruitEligible(d)) {
                recruit(d);
                return false;
            }
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
        List<String> missing = voters(d).stream().filter(id -> !d.voteLocked.contains(id)).toList();
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
        enterVoteReview(d);
    }

    /**
     * Every route into VoteReview goes through here — a normal close, the host
     * filling in AFK ballots, or the AFK timer running out — so {@code all_at_once}
     * behaves the same on all of them. It used to apply only to the first: after
     * an AFK detour the game sat in VoteReview, where REVEAL_NEXT is refused in
     * all_at_once mode, until the host force-advanced.
     */
    private void enterVoteReview(TruearenaState.Draft d) {
        d.phase = "VoteReview";
        d.votesRevealed = 0;
        d.emit("ALL_VOTES_IN", Map.of("count", d.votes.size(), "veiled", veiled(d)));
        // all_at_once: reveal immediately, no waiting on REVEAL_NEXT or a host force-advance —
        // that's the one real behavioral difference from `sequential` (see revealNext()'s guard).
        if ("all_at_once".equals(d.config.voteReveal())) {
            if (!veiled(d)) {
                while (d.votesRevealed < d.votes.size()) {
                    String voter = new ArrayList<>(d.votes.keySet()).get(d.votesRevealed++);
                    d.emit("VOTE_REVEALED", Map.of("voter", voter, "target", d.votes.get(voter)));
                }
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
            expireImmunity(d);
            return;
        }
        // Kept for Results: a veiled endgame withholds these at the time, and the
        // spec promises the full ballot history at the end.
        d.ballotHistory.add(Map.of(
                "round", d.round,
                "stage", d.tieStage == 0 ? "vote" : "tie",
                "veiled", veiled(d),
                "votes", new LinkedHashMap<>(d.votes)));
        // A Faithful who votes for a real Traitor earns the Ghost Jury's double vote, should they fall.
        TruearenaState now = build(d);
        d.votes.forEach((voter, target) -> {
            if (!now.isTraitor(voter) && now.isTraitor(target)) d.rightVoters.add(voter);
        });
        Map<String, Integer> tally = new LinkedHashMap<>();
        for (String t : d.votes.values()) {
            tally.merge(t, 1, Integer::sum);
        }
        int max = tally.values().stream().mapToInt(Integer::intValue).max().orElse(0);
        List<String> tied = tally.entrySet().stream().filter(e -> e.getValue() == max).map(Map.Entry::getKey).sorted().toList();
        if (tied.size() == 1) {
            banish(d, tied.get(0), max);
            return;
        }
        breakTie(d, tied, max);
    }

    /**
     * A tied ballot. The Ghost Jury sits first where the mode has one (Classic only after its
     * revote); otherwise — or if the ghosts can't agree — the mode's own tie rule decides.
     */
    private void breakTie(TruearenaState.Draft d, List<String> tied, int max) {
        if (jurySits(d)) {
            d.tieCandidates = new ArrayList<>(tied);
            d.juryTopVotes = max;
            d.juryVotes.clear();
            d.phase = "GhostJury";
            clearBallot(d);
            // No juror count: it would say how many of the hidden eliminations were Faithful.
            d.emit("GHOST_JURY_OPEN", Map.of("tied", tied));
            return;
        }
        String banished;
        if (d.tieStage == 0 && (d.config.twistEnabled("trial_of_two")
                || "trial_of_two".equals(d.config.tieBreak()))) {
            // Twist takes precedence over whatever `tieBreak` is configured (docs/GAME_CONFIG.md
            // compatibility rule: "the twist wins"). Reuses the existing Defense phase/timer;
            // advance()'s Defense case routes here via tieDefensePending instead of the normal
            // accusation-reply openVote(). Picking trial_of_two as the plain tie rule (no twist)
            // takes this path too — it used to fall through to SuddenDeath with no defense.
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
                d.tieStage = 0;
                clearBallot(d);
                expireImmunity(d);
                return;
            }
            if (d.tieStage == 0 && ("revote".equals(rule) || "sudden_death".equals(rule))) {
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

    /** Whether the Ghost Jury sits for this tie: once a day, only with ghosts, and in Classic only after the revote. */
    private static boolean jurySits(TruearenaState.Draft d) {
        if (!d.config.twistEnabled("ghost_jury") || d.juryDone) return false;
        if (Boolean.TRUE.equals(d.config.twistParams("ghost_jury").get("afterRevote")) && d.tieStage == 0) return false;
        return !build(d).ghosts().isEmpty();
    }

    /** The ghosts' verdict. A clear choice is banished; otherwise the mode's own rule takes over. */
    private void resolveJury(TruearenaState.Draft d) {
        List<String> tied = List.copyOf(d.tieCandidates);
        Map<String, Integer> weight = new LinkedHashMap<>();
        d.juryVotes.forEach((ghost, target) -> weight.merge(target, d.rightVoters.contains(ghost) ? 2 : 1, Integer::sum));
        int top = weight.values().stream().mapToInt(Integer::intValue).max().orElse(0);
        List<String> leaders = weight.entrySet().stream().filter(e -> e.getValue() == top)
                .map(Map.Entry::getKey).sorted().toList();
        d.juryVotes.clear();
        d.juryDone = true;
        if (leaders.size() == 1) {
            d.emit("GHOST_JURY_VERDICT", Map.of("chosen", leaders.getFirst()));
            banish(d, leaders.getFirst(), d.juryTopVotes);
        } else {
            d.emit("GHOST_JURY_VERDICT", Map.of("undecided", tied));
            breakTie(d, tied, d.juryTopVotes);
        }
    }

    private void banish(TruearenaState.Draft d, String banished, int votes) {
        if (banished.equals(d.immunityHolder) && d.immunitySpent) {
            d.emit("IMMUNITY_BLOCKED_BANISH", Map.of("holder", banished));
        } else {
            eliminate(d, banished, "banish");
            d.emit("BANISHED", Map.of("id", banished, "votes", votes));
        }
        expireImmunity(d);
        clearBallot(d);
        d.tieCandidates.clear();
        d.tieStage = 0;
        d.phase = "WinCheck";
    }

    /**
     * A spent coin covers the elimination it was spent for and nothing after —
     * otherwise spending it early would cost nothing, and "one use" would mean
     * "permanent once spent". Either way the game's only coin is then gone; it
     * used to reset to unawarded after blocking a banish, so the host could
     * award a second one.
     */
    private void expireImmunity(TruearenaState.Draft d) {
        if (d.immunitySpent) {
            d.immunitySpent = false;
            d.immunityHolder = null;
            d.immunityConsumed = true;
        }
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

    /**
     * The host stops the game partway: it's over, with no winner — so no
     * result, rating, stats or coins — and everyone sees who was who.
     */
    private void endByHost(TruearenaState.Draft d) {
        d.endedByHost = true;
        d.phase = "Results";
        d.emit("GAME_ENDED_BY_HOST", Map.of("round", d.round));
        d.emit("FULL_REVEAL", reveal(d));
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
        d.emit("FULL_REVEAL", reveal(d));
    }

    /** Everything that was hidden: who was who, how each one went, every ballot. */
    private static Map<String, Object> reveal(TruearenaState.Draft d) {
        Map<String, Object> reveal = new LinkedHashMap<>();
        reveal.put("roles", new LinkedHashMap<>(d.roles));
        reveal.put("eliminated", List.copyOf(d.eliminatedLog));
        reveal.put("causes", new LinkedHashMap<>(d.eliminationCause));
        reveal.put("ballots", List.copyOf(d.ballotHistory));
        if (d.shieldHolder != null) {
            Map<String, Object> shield = new LinkedHashMap<>();
            shield.put("holder", d.shieldHolder);
            shield.put("poisoned", d.shieldPoisoned);
            reveal.put("shield", shield);
        }
        return reveal;
    }

    private void eliminate(TruearenaState.Draft d, String id, String cause) {
        d.alive.remove(id);
        d.eliminatedLog.add(id);
        d.eliminationCause.put(id, cause);
        boolean shown = roleShownAt(d.config.revealOnElimination(), d.eliminationIndex);
        if (shown && "banish".equals(cause) && d.falseRevealArmed
                && TruearenaState.FAITHFUL.equals(d.roles.get(id))) {
            shown = false;
            d.falseRevealArmed = false;
            d.falseRevealUses--;
            d.emitToRole("FALSE_REVEAL_USED", Map.of("id", id), TruearenaState.TRAITOR);
        }
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

    /**
     * The clearest, least-ambiguous cases only — Night (every living Traitor
     * must act) and Vote/Revote (every living player who hasn't locked a
     * vote yet) and Defense (the accused). The remaining phases
     * (RoleReveal/MorningReveal/RoundTable/SuddenDeath/HostDecision/
     * HostAssignVotes/VoteReview/Elimination/WinCheck) are short reveal beats,
     * purely informational, or not yet worth a push reminder (free
     * discussion, a sudden-death tiebreak) — left empty rather than guessed
     * at, per the plan's "do this one last, with its own care" note.
     */
    @Override
    public java.util.Set<String> playersToAct(GameState state) {
        TruearenaState s = (TruearenaState) state;
        if (s.finished()) return java.util.Set.of();
        return switch (s.phase()) {
            case "Night" -> s.alive.stream().filter(id -> s.isTraitor(id)
                            || s.config.twistEnabled("alibis") && !s.alibis.containsKey(id)
                            || id.equals(s.seer) && s.config.twistEnabled("seer_lantern") && !s.lanternUsed
                                    && !s.lanternTonight && !s.isTraitor(id))
                    .collect(java.util.stream.Collectors.toSet());
            case "Vote", "Revote" -> s.alive.stream().filter(id -> !s.voteLocked.contains(id) && !id.equals(s.spotSilenced))
                    .collect(java.util.stream.Collectors.toSet());
            case "MorningReveal", "RoundTable" -> s.recruitOffer == null ? java.util.Set.of() : java.util.Set.of(s.recruitOffer);
            case "GhostJury" -> s.ghosts().stream().filter(id -> !s.juryVotes.containsKey(id))
                    .collect(java.util.stream.Collectors.toSet());
            case "Defense" -> s.tieDefensePending ? java.util.Set.copyOf(s.tieCandidates)
                    : s.accused == null ? java.util.Set.of() : java.util.Set.of(s.accused);
            default -> java.util.Set.of();
        };
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
                // What each Traitor has picked tonight. Without this, a mode that
                // needs consensus (The Last Alibi) was nearly unplayable: nobody
                // could see whether they agreed.
                m.put("nightPicks", s.nightSubmissions);
                m.put("secondNightPicks", s.secondNightSubmissions);
                m.put("canSkipNight", s.config.nightKill().allowSkip() && !s.nightSkipUsed);
                Integer after = s.config.nightKill().doubleAfterRound();
                m.put("doubleMurderAvailable", after != null && after > 0 && s.round > after);
                if (s.config.twistEnabled("double_agent") && !s.doubleAgentRecruited
                        && s.doubleAgentCandidate != null && s.alive.contains(s.doubleAgentCandidate)) {
                    m.put("doubleAgentCandidate", s.doubleAgentCandidate);
                }
            }
            if (s.config.twistEnabled("false_reveal")) {
                m.put("falseRevealUses", s.falseRevealUses);
                m.put("falseRevealArmed", s.falseRevealArmed);
            }
        }
        if (s.votes.containsKey(playerId)) {
            // Your own locked ballot, so the app can show it — never anyone else's.
            m.put("yourVote", s.votes.get(playerId));
        }
        if (s.poisonDue.containsKey(playerId)) {
            m.put("poisonedUntilRound", s.poisonDue.get(playerId));
        }
        if (s.config.twistEnabled("confessional") && s.alive.contains(playerId)) {
            m.put("confessionalSubmitted", s.confessionals.containsKey(playerId));
        }
        if (s.config.twistEnabled("last_will") && "MorningReveal".equals(s.phase)
                && s.eliminatedLog.contains(playerId) && !s.lastWills.containsKey(playerId)) {
            m.put("canLeaveLastWill", true);
        }
        if (!s.finished()) privateDynamics(s, playerId, m);
        if (s.finished()) {
            m.put("allRoles", s.roles);
        }
        return new PlayerVisibleState(m);
    }

    /** What only this player gets to see of the dynamics — their own offer, pie, lantern, alibi or jury seat. */
    private static void privateDynamics(TruearenaState s, String playerId, Map<String, Object> m) {
        boolean night = "Night".equals(s.phase);
        boolean traitor = s.isTraitor(playerId) && s.alive.contains(playerId);
        if (traitor && night && recruitOpen(s)) {
            m.put("canRecruit", true);
            m.put("recruitTargets", s.aliveFaithful().stream().filter(id -> !s.recruitAsked.contains(id)).toList());
        }
        if (traitor && s.recruitNight) m.put("recruitingTonight", s.recruitOffer);
        if (playerId.equals(s.recruitOffer) && !night) m.put("recruitOffer", true);
        if (traitor && night && s.config.twistEnabled("poisoned_pie") && s.pieUses > 0 && !s.pieBaked
                && !s.pieAvailable && s.pieHolder == null) {
            m.put("canBakePie", true);
        }
        if (s.isTraitor(playerId) && s.pieBaked) m.put("pieBakedTonight", s.piePoisoned ? "poison" : "shield");
        if (traitor && night && s.config.twistEnabled("black_spot")) {
            m.put("canPlaceSpot", s.spotPending == null);
            m.put("spotPending", s.spotPending);
        }
        if (night && s.config.twistEnabled("alibis") && s.alive.contains(playerId)) {
            m.put("alibiNeeded", true);
            m.put("yourAlibi", s.alibis.get(playerId));
        }
        if (playerId.equals(s.seer) && s.config.twistEnabled("seer_lantern")) {
            Map<String, Object> seer = new LinkedHashMap<>();
            seer.put("lanternUsed", s.lanternUsed);
            seer.put("canLight", night && s.alive.contains(playerId) && !s.isTraitor(playerId)
                    && !s.lanternUsed && !s.lanternTonight);
            seer.put("visions", s.visions);
            m.put("seer", seer);
        }
        if ("GhostJury".equals(s.phase) && s.ghosts().contains(playerId)) {
            m.put("ghostJuror", true);
            m.put("yourJuryVote", s.juryVotes.get(playerId));
        }
        if (s.config.twistEnabled("crowd_hunch") && !s.alive.contains(playerId) && !s.isTraitor(playerId)
                && !"RoleReveal".equals(s.phase)) {
            m.put("canCrowdVote", true);
            m.put("yourCrowdVote", s.crowdVotes.get(playerId));
        }
        if (s.config.twistEnabled("last_stand") && !s.lastStandUsed && "RoundTable".equals(s.phase)
                && s.alive.size() <= 4 && s.alive.contains(playerId)) {
            m.put("canLastStand", true);
        }
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
        m.put("voteProgress", Map.of("locked", s.voteLocked.size(),
                "total", (int) s.alive.stream().filter(id -> !id.equals(s.spotSilenced)).count()));
        m.put("rules", rulesView(s.config));
        m.put("immunityAvailable", s.config.twistEnabled("immunity_coin")
                && s.immunityHolder == null && !s.immunityConsumed);
        if ("HostAssignVotes".equals(s.phase)) {
            m.put("missingVoters", s.alive.stream().filter(id -> !s.voteLocked.contains(id) && !id.equals(s.spotSilenced)).toList());
        }
        publicDynamics(s, m);
        if (s.config.twistEnabled("survivors_choice")) {
            m.put("survivorsChoiceVotes", s.survivorsChoiceVotes.size());
        }
        m.put("veiled", s.config.veilThreshold() > 0 && s.alive.size() <= s.config.veilThreshold());
        if (s.finished()) m.put("winningSide", s.win.winningSide());
        return m;
    }

    /** What the whole table (and every spectator) sees of the dynamics. */
    private static void publicDynamics(TruearenaState s, Map<String, Object> m) {
        GameConfig c = s.config;
        if (c.twistEnabled("poisoned_pie")) {
            Map<String, Object> pie = new LinkedHashMap<>();
            pie.put("available", s.pieAvailable);
            pie.put("clue", s.pieAvailable ? s.pieClue : null);
            pie.put("holder", s.pieHolder);
            m.put("pie", pie);
        }
        if (c.twistEnabled("crime_clues")) m.put("crimeClues", s.crimeClues);
        if (c.twistEnabled("alibis")) m.put("alibiBoard", s.alibiBoard);
        if (c.twistEnabled("black_spot")) {
            Map<String, Object> spot = new LinkedHashMap<>();
            spot.put("holder", s.spotHolder);
            spot.put("chain", s.spotChain);
            spot.put("silenced", s.spotSilenced);
            m.put("blackSpot", spot);
        }
        if (c.twistEnabled("last_stand")) {
            m.put("lastStandUsed", s.lastStandUsed);
            m.put("standReveal", s.standReveal);
        }
        if (c.twistEnabled("crowd_hunch")) m.put("crowdHunch", crowdHunch(s));
    }

    /**
     * The crowd's favourite suspect, shown only once enough have voted that no single vote
     * can be picked out. Super Faithful count double — nobody is told.
     */
    static Map<String, Object> crowdHunch(TruearenaState s) {
        Map<String, Object> h = new LinkedHashMap<>();
        int voters = s.crowdVotes.size();
        h.put("voters", voters);
        Object min = s.config.twistParams("crowd_hunch").getOrDefault("minVoters", 3);
        if (voters < (min instanceof Number n ? Math.max(3, n.intValue()) : 3)) return h;
        Map<String, Integer> weight = new LinkedHashMap<>();
        s.crowdVotes.forEach((voter, target) -> {
            if (s.alive.contains(target)) weight.merge(target, s.rightVoters.contains(voter) ? 2 : 1, Integer::sum);
        });
        int total = weight.values().stream().mapToInt(Integer::intValue).sum();
        if (total == 0) return h;
        int top = weight.values().stream().mapToInt(Integer::intValue).max().orElse(0);
        List<String> leaders = weight.entrySet().stream().filter(e -> e.getValue() == top).map(Map.Entry::getKey).sorted().toList();
        h.put("suspect", leaders.getFirst());
        h.put("percent", Math.round(100f * top / total));
        h.put("split", leaders.size() > 1);
        return h;
    }

    /**
     * The table's rules, public on purpose — everyone at the table agreed to them
     * in the lobby. The app reads this rather than guessing from the preset name,
     * which left every rule unusable in a Custom game.
     */
    private static Map<String, Object> rulesView(GameConfig c) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("twists", List.copyOf(c.twists().keySet()));
        r.put("allowSkip", c.nightKill().allowSkip());
        r.put("doubleAfterRound", c.nightKill().doubleAfterRound());
        r.put("requireTraitorConsensus", c.nightKill().requireTraitorConsensus());
        r.put("voteReveal", c.voteReveal());
        r.put("afk", c.afk());
        r.put("tieBreak", c.tieBreak());
        r.put("revealOnElimination", c.revealOnElimination());
        r.put("timers", Map.of("night", c.timers().night(), "roundTable", c.timers().roundTable(),
                "vote", c.timers().vote(), "defense", c.timers().defense(),
                "suddenDeath", c.suddenDeathSeconds()));
        return r;
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
