package app.truearena.room;

/**
 * A discussion-phase chat line. Flows through the same {@link RoomRuntime#bus} as
 * everything else, but — unlike engine {@code GameEvent}s and {@link LobbyBroadcast}
 * — it is <b>not</b> appended to {@code RoomEventLog}/Postgres: chat is ephemeral by
 * design (v1 simplification, see docs/DEV_REFERENCE.md §7). A client that reconnects
 * mid-discussion gets the game snapshot back, not the chat transcript.
 *
 * <p>{@code channel} is {@code "table"} (everyone) or {@code "traitors"} (only
 * traitor/recruited-traitor viewers see it — enforced by
 * {@code GameOrchestrator.toEnvelope}, the same place role-scoped {@code GameEvent}s
 * are filtered, so it rides the one already-tested secret-data path rather than a
 * second one).
 */
public record ChatMessage(String channel, String fromUserId, String text, long ts) {
    public static final String TABLE = "table";
    public static final String TRAITORS = "traitors";
    /**
     * The always-open audience channel — TikTok-style spectator comments.
     * Unlike {@link #TABLE}/{@link #TRAITORS} it isn't gated to a phase or a
     * role, and it's open to spectators as well as players, in every game
     * type (see {@code GameOrchestrator.handleChat}).
     */
    public static final String SPECTATE = "spectate";

    /**
     * Cyber Agent table talk — the short, in-character lines an agent says
     * around its own moves. Always open like {@link #SPECTATE}, but
     * write-restricted to bots (see {@code GameOrchestrator.handleChat}): a
     * human posting here would be impersonating an agent. Muting is a
     * per-listener client choice, not a server flag — one player silencing
     * the chatter shouldn't silence it for everyone else.
     */
    public static final String AGENT = "agent";
}
