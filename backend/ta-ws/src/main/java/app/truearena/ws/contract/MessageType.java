package app.truearena.ws.contract;

/**
 * Baseline mirror of {@code shared/contract/envelope.schema.json#/$defs/messageType}.
 * Hand-maintained until the codegen task lands (see shared/contract/README.md).
 */
public enum MessageType {
    // client → server
    HELLO,
    READY_SET,
    CONFIG_SET,
    GAME_START,
    PLAYER_ACTION,
    HOST_CONTROL,
    CHAT_SEND,
    PAUSE_TOGGLE,
    MUTE_SPECTATORS_TOGGLE,
    SPECTATOR_VOICE_REQUEST,
    SPECTATOR_VOICE_APPROVE,
    SPECTATOR_VOICE_DECLINE,
    SPECTATOR_VOICE_MUTE_TOGGLE,
    SPECTATOR_VOICE_REMOVE,
    /** A player stepped away from the game screen ({away: true}) or came back ({away: false}). */
    PRESENCE,
    PING,
    // server → client
    SNAPSHOT,
    EVENT,
    PHASE,
    ERROR,
    PONG
}
