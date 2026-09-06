package app.truearena.game.truearena;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class TrueArenaModuleTest {

    @Test
    void exposesGameType() {
        assertEquals("truearena", new TrueArenaModule().gameType());
    }
}
