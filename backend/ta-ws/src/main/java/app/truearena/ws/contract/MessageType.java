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
    PING,
    // server → client
    SNAPSHOT,
    EVENT,
    PHASE,
    ERROR,
    PONG
}
