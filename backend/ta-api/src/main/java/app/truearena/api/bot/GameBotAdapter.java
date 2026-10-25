package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;

import java.util.Map;
import java.util.Optional;
import java.time.Duration;

/**
 * The only per-game piece of the whole bot system — {@link BotRuntime} knows
 * nothing about any game's rules, board shape, or action vocabulary. One
 * instance is created fresh per bot session (it holds mutable state: the
 * board as the bot has seen it evolve, since {@link BotRuntime} only ever
 * hands it raw inbound frames, not a ready-made snapshot).
 *
 * <p>Adding a new game to the bot roster is exactly implementing this
 * interface — see {@link DraughtsBotAdapter} — nothing else changes.
 */
public interface GameBotAdapter {

    String gameType();

    /**
     * Feed one inbound WS frame (`type` is "SNAPSHOT"/"EVENT"/"PHASE"/"ERROR",
     * `payload` its raw payload map). Returns a turn marker (or a communication prompt)
     * if — after applying this frame — it's now this bot's turn to act;
     * empty otherwise (including: it's not this bot's game yet, the game
     * already ended, or it's the other player's turn).
     */
    Optional<BotPrompt> onFrame(String frameType, Map<String, Object> payload, String botUserId, Difficulty difficulty);

    /** Legacy response parser, retained for compatibility tests. The runtime never uses it for gameplay. */
    Optional<PlayerAction> parseAction(String rawResponse, String botUserId);

    /** A safe local move if the normal strategy cannot produce an action — the game must never stall on a bot. */
    Optional<PlayerAction> fallbackAction(String botUserId);

    /**
     * All supported games decide locally. The runtime never sends gameplay
     * prompts to the communication model.
     */
    default boolean decidesLocally() {
        return true;
    }

    /**
     * The adapter's own decision for the turn {@link #onFrame} just flagged.
     * Any pacing ("thinking" time) is the adapter's to apply, because only
     * it knows how much clock it can spend.
     */
    default Optional<PlayerAction> decideLocally(String botUserId, Difficulty difficulty) {
        return fallbackAction(botUserId);
    }

    /** Brief cosmetic pacing, independent of model latency. Clock-aware engines can override it. */
    default Duration actionDelay() { return Duration.ofMillis(400); }

    default boolean speaksThroughActions() { return false; }

    default Optional<PlayerAction> speechAction(BotPrompt prompt, String text, String botUserId) {
        return Optional.empty();
    }

    default String fallbackSpeech(BotPrompt prompt) { return ""; }

    /** Word puzzles use their curated clue verbatim; arbitrary rephrasing changes the puzzle. */
    default boolean usesModelForSpeech() { return true; }

    /** Checked before submitting asynchronous speech; adapters can reject obsolete contexts. */
    default boolean speechIsCurrent(BotPrompt prompt) { return true; }

    /**
     * After the agent's said a clue through {@link #speechAction}: which
     * word it was about, for {@link #followUp} to check it's still current.
     * Negative when there's nothing to follow up.
     */
    default int describingToken() { return -1; }

    /**
     * What to do when the table's had a while with the clue for word
     * {@code token} and hasn't got it — another clue, or giving up on it.
     * Empty once that word has moved on. The runtime calls this on a timer,
     * off the frame thread, and again after each clue it returns.
     */
    default Optional<PlayerAction> followUp(String botUserId, int token) { return Optional.empty(); }

    /**
     * What to ask the model for.
     *
     * <p>Only markers with {@code speak} set may reach the communication model.
     * Other prompt text is legacy diagnostic context, never a model request.
     * With {@code speak} set the answer is something the agent says out loud
     * instead — a Word Bluff describer's clue — which the runtime posts to
     * the table and then follows with {@link #fallbackAction} once the
     * table has had a moment with it.
     *
     * <p>{@code forbidden} is the one word that must never appear in a
     * spoken answer. Saying it would hand the round away, so the runtime
     * drops any line containing it rather than trusting the model.
     */
    record BotPrompt(String systemPrompt, String userPrompt, boolean speak, String forbidden,
                     Map<String, Object> context) {
        BotPrompt(String systemPrompt, String userPrompt, boolean speak, String forbidden) {
            this(systemPrompt, userPrompt, speak, forbidden, Map.of());
        }
        BotPrompt(String systemPrompt, String userPrompt) {
            this(systemPrompt, userPrompt, false, null);
        }
    }
}
