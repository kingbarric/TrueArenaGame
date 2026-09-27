package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;

import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * The Trust & Traitors ("TrueArena") bot adapter. Unlike Draughts this game
 * has no board to keep in sync — everything the bot needs (its own role,
 * who else is a fellow Traitor, who's still alive, the current phase) comes
 * straight off the per-player SNAPSHOT and the events the server already
 * routes only to this bot's own connection (role-scoped {@code emitToPlayer}
 * / {@code emitToRole} calls in {@code TrueArenaModule} never leave the wire
 * for anyone else, so nothing here needs its own visibility filtering).
 *
 * <p>Role strings ("traitor" / "recruited_traitor" / "faithful") are
 * hardcoded to match {@code TruearenaState}'s package-private constants —
 * that class isn't public API, so this module can't reference them
 * directly.
 *
 * <p>Only two phases ever require this bot to act: {@code Night} (a living
 * Traitor picks a kill target) and {@code Vote} (any living player casts a
 * vote). Every other phase (RoleReveal, MorningReveal, RoundTable,
 * VoteReview, Elimination, WinCheck, Results) is either automatic or
 * advanced by the host — a bot has nothing to submit there.
 */
public final class TrueArenaBotAdapter implements GameBotAdapter {

    private static final SecureRandom RNG = new SecureRandom();
    private static final String TRAITOR = "traitor";
    private static final String RECRUITED = "recruited_traitor";
    private static final Pattern TARGET_JSON = Pattern.compile("\"target\"\\s*:\\s*\"([^\"]+)\"");

    private String phase = "RoleReveal";
    private final Set<String> alive = new LinkedHashSet<>();
    private String myRole;
    private final Set<String> fellowTraitors = new LinkedHashSet<>();
    private boolean finished;
    // Guards against re-deciding on every subsequent event within the same
    // phase (e.g. fellow traitors' NIGHT_TARGET_SET broadcasts, which this
    // bot also receives while it's a Night phase it already acted in).
    private String actedInPhase;

    @Override
    public String gameType() {
        return "truearena";
    }

    @Override
    @SuppressWarnings("unchecked")
    public Optional<BotPrompt> onFrame(String frameType, Map<String, Object> payload, String botUserId, Difficulty difficulty) {
        switch (frameType) {
            case "SNAPSHOT" -> applySnapshot(payload);
            case "EVENT" -> applyEvent((Map<String, Object>) payload.getOrDefault("data", Map.of()),
                    String.valueOf(payload.get("type")));
            // Same discipline as DraughtsBotAdapter: a bare PHASE frame arrives
            // before the domain EVENTs that describe what changed (see
            // GameOrchestrator.afterMutation). Track it, but decide only once an
            // EVENT (or a fresh SNAPSHOT) confirms we're caught up.
            case "PHASE" -> {
                String newPhase = String.valueOf(payload.get("phase"));
                if (!newPhase.equals(phase)) {
                    actedInPhase = null;
                }
                phase = newPhase;
                return Optional.empty();
            }
            default -> { /* ERROR and anything else: nothing to update here */ }
        }
        if (finished || myRole == null || phase.equals(actedInPhase)) {
            return Optional.empty();
        }
        if ("Night".equals(phase) && isTraitor() && alive.contains(botUserId)) {
            List<String> targets = alive.stream().filter(id -> !isFellowTraitor(id) && !id.equals(botUserId)).toList();
            if (targets.isEmpty()) {
                return Optional.empty();
            }
            actedInPhase = phase;
            return Optional.of(nightPrompt(targets, difficulty));
        }
        if ("Vote".equals(phase) && alive.contains(botUserId)) {
            List<String> targets = alive.stream().filter(id -> !id.equals(botUserId)).toList();
            if (targets.isEmpty()) {
                return Optional.empty();
            }
            actedInPhase = phase;
            return Optional.of(votePrompt(targets, difficulty));
        }
        return Optional.empty();
    }

    @SuppressWarnings("unchecked")
    private void applySnapshot(Map<String, Object> p) {
        Object ph = p.get("phase");
        if (ph != null) phase = String.valueOf(ph);
        Object al = p.get("alive");
        if (al instanceof List<?> list) {
            alive.clear();
            for (Object o : list) alive.add(String.valueOf(o));
        }
        Object role = p.get("yourRole");
        if (role != null) myRole = String.valueOf(role);
        Object fellows = p.get("fellowTraitors");
        if (fellows instanceof List<?> list) {
            fellowTraitors.clear();
            for (Object o : list) fellowTraitors.add(String.valueOf(o));
        }
    }

    private void applyEvent(Map<String, Object> data, String type) {
        switch (type) {
            case "GAME_STARTED" -> {
                alive.clear();
                Object players = data.get("players");
                if (players instanceof List<?> list) for (Object o : list) alive.add(String.valueOf(o));
            }
            case "ROLE_ASSIGNED" -> myRole = String.valueOf(data.get("role"));
            case "FELLOW_TRAITORS" -> {
                fellowTraitors.clear();
                Object ids = data.get("ids");
                if (ids instanceof List<?> list) for (Object o : list) fellowTraitors.add(String.valueOf(o));
            }
            case "RECRUITED_AS_TRAITOR" -> myRole = RECRUITED;
            case "PLAYER_ELIMINATED" -> alive.remove(String.valueOf(data.get("id")));
            case "GAME_OVER" -> finished = true;
            default -> { /* NIGHT_FALLS, MORNING_REVEAL, MICS_FORCE_MUTED etc. carry nothing this bot needs to track */ }
        }
    }

    private boolean isTraitor() {
        return TRAITOR.equals(myRole) || RECRUITED.equals(myRole);
    }

    private boolean isFellowTraitor(String id) {
        return fellowTraitors.contains(id);
    }

    private BotPrompt nightPrompt(List<String> targets, Difficulty difficulty) {
        String system = """
                You are a secret Traitor in a Trust & Traitors social deduction game. \
                It's Night — pick which living player to eliminate.
                %s
                Reply with ONLY a JSON object of the exact shape {"target": "<playerId>"} \
                naming one of the candidate ids — no other text.""".formatted(
                switch (difficulty) {
                    case EASY -> "Pick a reasonable target.";
                    case MEDIUM -> "Prefer eliminating players who seem to be building trust or leading the discussion.";
                    case HARD -> "Think about who is most likely to expose the Traitors next round and eliminate the "
                            + "biggest threat, while avoiding an obvious pattern across rounds.";
                })
                + "\nCandidates: " + targets;
        String user = "Candidates: " + targets;
        return new BotPrompt(system, user);
    }

    private BotPrompt votePrompt(List<String> targets, Difficulty difficulty) {
        String system = """
                You are a player in a Trust & Traitors social deduction game. It's time to vote to banish someone.
                %s
                Reply with ONLY a JSON object of the exact shape {"target": "<playerId>"} \
                naming one of the candidate ids — no other text.""".formatted(
                switch (difficulty) {
                    case EASY -> "Pick a reasonable target.";
                    case MEDIUM, HARD -> "Vote for whoever seems most suspicious based on the round so far.";
                })
                + "\nCandidates: " + targets;
        String user = "Candidates: " + targets;
        return new BotPrompt(system, user);
    }

    @Override
    public Optional<PlayerAction> parseAction(String rawResponse, String botUserId) {
        if (rawResponse == null || rawResponse.isBlank()) {
            return Optional.empty();
        }
        Matcher m = TARGET_JSON.matcher(rawResponse);
        if (!m.find()) {
            return Optional.empty();
        }
        String target = m.group(1);
        if (!alive.contains(target) || target.equals(botUserId)) {
            return Optional.empty();
        }
        String actionType = "Night".equals(phase) ? "NIGHT_TARGET" : "CAST_VOTE";
        return Optional.of(PlayerAction.of(botUserId, actionType, Map.of("target", target)));
    }

    @Override
    public Optional<PlayerAction> fallbackAction(String botUserId) {
        if ("Night".equals(phase)) {
            List<String> candidates = alive.stream().filter(id -> !isFellowTraitor(id) && !id.equals(botUserId)).toList();
            if (candidates.isEmpty()) {
                return Optional.empty();
            }
            String target = candidates.get(RNG.nextInt(candidates.size()));
            return Optional.of(PlayerAction.of(botUserId, "NIGHT_TARGET", Map.of("target", target)));
        }
        if ("Vote".equals(phase)) {
            List<String> candidates = alive.stream().filter(id -> !id.equals(botUserId)).toList();
            if (candidates.isEmpty()) {
                return Optional.empty();
            }
            String target = candidates.get(RNG.nextInt(candidates.size()));
            return Optional.of(PlayerAction.of(botUserId, "CAST_VOTE", Map.of("target", target)));
        }
        return Optional.empty();
    }
}
