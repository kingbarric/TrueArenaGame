package app.truearena.api.bot;

import app.truearena.engine.PlayerAction;

import java.util.Map;
import java.util.Optional;

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
     * `payload` its raw payload map). Returns a prompt to send to the model
     * if — after applying this frame — it's now this bot's turn to act;
     * empty otherwise (including: it's not this bot's game yet, the game
     * already ended, or it's the other player's turn).
     */
    Optional<BotPrompt> onFrame(String frameType, Map<String, Object> payload, String botUserId, Difficulty difficulty);

    /** Turns the model's raw text response into a concrete action, or empty if it couldn't be parsed as one. */
    Optional<PlayerAction> parseAction(String rawResponse, String botUserId);

    /** A safe, always-legal move for when the model fails, times out, or is a stub — the game must never stall on a bot. */
    Optional<PlayerAction> fallbackAction(String botUserId);

    /**
     * True for games with a real engine of their own (chess): the runtime
     * calls {@link #decideLocally} instead of asking a model, on a worker
     * thread since searching takes real CPU time.
     */
    default boolean decidesLocally() {
        return false;
    }

    /**
     * The adapter's own decision for the turn {@link #onFrame} just flagged.
     * Any pacing ("thinking" time) is the adapter's to apply, because only
     * it knows how much clock it can spend.
     */
    default Optional<PlayerAction> decideLocally(String botUserId, Difficulty difficulty) {
        return Optional.empty();
    }

    /**
     * What to ask the model for.
     *
     * <p>Usually the answer is a move, parsed by {@link #parseAction}. When
     * {@code speak} is set the answer is something the agent says out loud
     * instead — a Word Bluff describer's clue — which the runtime posts to
     * the table and then follows with {@link #fallbackAction} once the
     * table has had a moment with it.
     *
     * <p>{@code forbidden} is the one word that must never appear in a
     * spoken answer. Saying it would hand the round away, so the runtime
     * drops any line containing it rather than trusting the model.
     */
    record BotPrompt(String systemPrompt, String userPrompt, boolean speak, String forbidden) {
        BotPrompt(String systemPrompt, String userPrompt) {
            this(systemPrompt, userPrompt, false, null);
        }
    }
}
