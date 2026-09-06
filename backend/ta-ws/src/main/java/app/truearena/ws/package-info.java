/**
 * WebSocket handler for {@code /ws/room/{roomId}}: envelope codec, HELLO/SNAPSHOT,
 * event replay, and per-connection {@code getVisibleStateFor} filtering applied
 * after Redis fan-out. Phase 4.
 */
package app.truearena.ws;
