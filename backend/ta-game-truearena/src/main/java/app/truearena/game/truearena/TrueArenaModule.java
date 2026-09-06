package app.truearena.game.truearena;

import app.truearena.engine.GameModule;

/** Phase 6 fills this in. Phase 0 only needs it to compile against the SPI. */
public final class TrueArenaModule implements GameModule {

    public static final String GAME_TYPE = "truearena";

    @Override
    public String gameType() {
        return GAME_TYPE;
    }
}
