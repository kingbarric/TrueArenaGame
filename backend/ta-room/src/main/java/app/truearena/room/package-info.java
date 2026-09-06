/**
 * Ephemeral room state in Redis: {@code room:{id}:meta|members|state|events|phase},
 * pub/sub fan-out, {@code session:{token}}, and the per-room mutation lock.
 * Phases 3.4, 4.3–4.7.
 */
package app.truearena.room;
