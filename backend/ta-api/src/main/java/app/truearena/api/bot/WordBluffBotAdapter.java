package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.Optional;

/**
 * Word Bluff's bot adapter — with an honest, load-bearing limitation: a
 * Cyber Agent cannot literally speak a verbal description of a word out
 * loud to its teammates, so it can never legitimately earn points as
 * describer. When it's this bot's turn to describe, it still plays its
 * part faithfully in the game's mechanics — it spins, reveals a word, then
 * immediately skips — rather than stalling the game or silently sitting on
 * the turn timer. This is documented behavior, not a bug: a Cyber Agent
 * filling a Word Bluff seat contributes as a *guesser* (during teammates'
 * turns there's nothing for it to submit — guessing happens by voice) and
 * as a describer it always skips, same as a human describer who draws a
 * word nobody could act on.
 *
 * <p>Because SPIN/REVEAL/SKIP are never real decisions (there is exactly
 * one correct next step at each stage), {@link #parseAction} ignores the
 * model's response entirely and always returns that deterministic action —
 * still routed through the same LLM pipeline as every other adapter, just
 * with nothing riding on its content.
 */
public final class WordBluffBotAdapter implements GameBotAdapter {

    private String phase = "Turn";
    private String describer;

    /** The word the agent has already given a clue for, so a fresh frame
     *  doesn't set it describing the same word over and over. */
    private String describedWord;

    /** What the agent calls itself in its own clue prompt. */
    private final String agentName = "Cyber Agent";

    /// The two teams, and which of them have signed off the review. An
    /// agent has no opinion about a disputed call, so it accepts — and it
    /// has to, because the review waits on both teams and has no clock. A
    /// table of agents used to sit there forever.
    private final List<String> teamA = new ArrayList<>();
    private final List<String> teamB = new ArrayList<>();
    private final Set<String> acceptedTeams = new HashSet<>();
    private boolean reviewAcceptSent;
    private boolean hasCategory;
    private boolean hasWord;

    /// The word in hand and the category it came from. Only ever set from
    /// WORD_REVEALED, which the server sends to the describer alone.
    private String word;
    private String category = "";
    private boolean finished;

    @Override
    public String gameType() {
        return "wordbluff";
    }

    @Override
    @SuppressWarnings("unchecked")
    public Optional<BotPrompt> onFrame(String frameType, Map<String, Object> payload, String botUserId, Difficulty difficulty) {
        switch (frameType) {
            case "SNAPSHOT" -> applySnapshot(payload);
            case "EVENT" -> applyEvent((Map<String, Object>) payload.getOrDefault("data", Map.of()),
                    String.valueOf(payload.get("type")));
            // Same discipline as the other adapters: a bare PHASE frame arrives
            // before the domain EVENTs describing what changed (see
            // GameOrchestrator.afterMutation) — never decide off it directly.
            case "PHASE" -> {
                phase = String.valueOf(payload.get("phase"));
                return Optional.empty();
            }
            default -> { /* ERROR and anything else: nothing to update here */ }
        }
        if (finished) {
            return Optional.empty();
        }
        if ("Review".equals(phase)) {
            // Nothing to think about — sign the review off so the round can
            // move on. Handled through the same prompt path so the runtime
            // actually sends it.
            return shouldAcceptReview(botUserId)
                    ? Optional.of(new BotPrompt(
                            "You are a Cyber Agent reviewing the round's calls. Reply with anything.",
                            "stage=REVIEW_ACCEPT"))
                    : Optional.empty();
        }
        if (!"Turn".equals(phase) || !botUserId.equals(describer)) {
            return Optional.empty();
        }
        if (!hasCategory) {
            return Optional.of(new BotPrompt(
                    "You are a Cyber Agent about to spin the category wheel in Word Bluff. "
                            + "Reply with anything — spinning takes no decision.",
                    "stage=SPIN"));
        }
        if (!hasWord) {
            return Optional.of(new BotPrompt(
                    "You are a Cyber Agent waiting on the next word in Word Bluff. "
                            + "Reply with anything — this takes no decision.",
                    "stage=REVEAL"));
        }
        // There's a word in hand: describe it. Only prompt once per word,
        // or every inbound frame would set the agent talking over itself.
        if (word.equals(describedWord)) {
            return Optional.empty();
        }
        describedWord = word;
        String system = """
                You are %s, describing a word to your team in Word Bluff, out loud, \
                across a table.

                Hard rules:
                - NEVER say the word itself, any part of it, or a word that rhymes with it.
                - No spelling it, no first letters, no "sounds like".
                - One or two short sentences. Sound like speech, not a dictionary.
                - Describe what it is, what it does, or where you'd find it.
                Reply with the description only.""".formatted(agentName);
        return Optional.of(new BotPrompt(
                system,
                "The word is \"%s\" (category: %s). Describe it.".formatted(word, category),
                true,
                word));
    }

    @SuppressWarnings("unchecked")
    private void applySnapshot(Map<String, Object> p) {
        Object ph = p.get("phase");
        if (ph != null) phase = String.valueOf(ph);
        Object d = p.get("describer");
        if (d != null) describer = String.valueOf(d);
        Object hc = p.get("hasActiveCategory");
        if (hc != null) hasCategory = Boolean.TRUE.equals(hc);
        Object hw = p.get("hasActiveWord");
        if (hw != null) hasWord = Boolean.TRUE.equals(hw);
    }

    @SuppressWarnings("unchecked")
    private void rememberTeams(Map<String, Object> data) {
        Object a = data.get("teamA");
        Object b = data.get("teamB");
        if (a instanceof List<?> la) {
            teamA.clear();
            la.forEach(v -> teamA.add(String.valueOf(v)));
        }
        if (b instanceof List<?> lb) {
            teamB.clear();
            lb.forEach(v -> teamB.add(String.valueOf(v)));
        }
    }

    /** "A", "B", or null if this id isn't playing. */
    private String teamOf(String userId) {
        if (teamA.contains(userId)) {
            return "A";
        }
        return teamB.contains(userId) ? "B" : null;
    }

    private void applyEvent(Map<String, Object> data, String type) {
        switch (type) {
            case "GAME_STARTED" -> rememberTeams(data);
            case "TURN_ENDED" -> {
                // The review opens; nobody has signed off yet.
                acceptedTeams.clear();
                reviewAcceptSent = false;
            }
            case "REVIEW_ACCEPTED" -> {
                Object t = data.get("team");
                if (t != null) {
                    acceptedTeams.add(String.valueOf(t));
                }
            }
            case "TURN_STARTED" -> {
                describer = String.valueOf(data.get("describer"));
                hasCategory = false;
                hasWord = false;
                word = null;
                describedWord = null;
                acceptedTeams.clear();
                reviewAcceptSent = false;
            }
            case "CATEGORY_LANDED" -> {
                hasCategory = true;
                Object c = data.get("categoryName");
                if (c != null) category = String.valueOf(c);
            }
            case "WORD_REVEALED" -> {
                hasWord = true;
                Object w = data.get("word");
                if (w != null) word = String.valueOf(w);
            }
            case "WORD_RESOLVED" -> {
                // The category belongs to the turn, not the word — a
                // resolved word is followed straight away by the next one
                // from the same category, so only the word clears here.
                hasWord = false;
                word = null;
            }
            case "GAME_OVER" -> finished = true;
            default -> { /* TURN_ENDED etc. carry nothing this bot needs to track beyond the PHASE frame */ }
        }
    }

    private Optional<PlayerAction> currentDeterministicAction(String botUserId) {
        if (finished) {
            return Optional.empty();
        }
        if ("Review".equals(phase)) {
            return reviewAcceptFor(botUserId);
        }
        if (!"Turn".equals(phase) || !botUserId.equals(describer)) {
            return Optional.empty();
        }
        String type = hasWord ? "SKIP" : hasCategory ? "REVEAL" : "SPIN";
        return Optional.of(PlayerAction.of(botUserId, type, Map.of()));
    }

    /**
     * Whether this agent still owes the review a signature. Deliberately
     * free of side effects: it's asked once to decide whether to prompt and
     * again to produce the action, and an earlier version flipped its own
     * flag on the first call — so the second returned nothing and the agent
     * decided to accept without ever sending anything.
     */
    private boolean shouldAcceptReview(String botUserId) {
        String team = teamOf(botUserId);
        return team != null && !reviewAcceptSent && !acceptedTeams.contains(team);
    }

    /** Signs the review off, once. A second send would be refused anyway. */
    private Optional<PlayerAction> reviewAcceptFor(String botUserId) {
        if (!shouldAcceptReview(botUserId)) {
            return Optional.empty();
        }
        reviewAcceptSent = true;
        return Optional.of(PlayerAction.of(botUserId, "REVIEW_ACCEPT", Map.of()));
    }

    @Override
    public Optional<PlayerAction> parseAction(String rawResponse, String botUserId) {
        return currentDeterministicAction(botUserId);
    }

    @Override
    public Optional<PlayerAction> fallbackAction(String botUserId) {
        return currentDeterministicAction(botUserId);
    }
}
