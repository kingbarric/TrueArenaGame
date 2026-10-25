package app.truearena.api.room;

import app.truearena.game.monopoly.MonopolyConfig;
import app.truearena.game.truearena.Presets;
import app.truearena.game.whot.WhotModule;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.util.Map;

/**
 * The fewest players each game starts with — people and Cyber Agents
 * together — for a room's stored rules. The app shows it before anyone taps
 * Start, so a short table is told to add a player or an agent instead of
 * being refused. Each game's own {@code initialState} is still the judge;
 * TableSizesTest keeps the two in step.
 */
public final class TableSizes {

    /** The Tell plays in teams of two: 4, 6 or 8. */
    public static final int TELL_MIN = 4;

    private static final ObjectMapper JSON = new ObjectMapper();

    private TableSizes() {
    }

    public static int minPlayers(String gameType, String gameConfig) {
        if (gameType == null) return 2;
        Map<?, ?> config = read(gameConfig);
        return switch (gameType) {
            case "wordbluff" -> 4;
            case "whot" -> "tell".equals(config.get("mode")) ? TELL_MIN : WhotModule.MIN_PLAYERS;
            case "monopoly" -> MonopolyConfig.MIN_PLAYERS;
            case "truearena" -> traitorsMin(config);
            // Chess, Draughts and Macala are one on one; Ludo, two to four.
            default -> 2;
        };
    }

    /**
     * A Traitors table's own minimum — the mode's, or a custom table's. An
     * override lets a host go down to four. No rules at all: the server
     * plays Classic Conspiracy.
     */
    private static int traitorsMin(Map<?, ?> config) {
        if (config.get("table") instanceof Map<?, ?> table) {
            if (Boolean.TRUE.equals(table.get("adminOverride"))) return 4;
            if (table.get("minPlayers") instanceof Number min) return min.intValue();
        }
        Presets.Mode preset = config.get("preset") instanceof String slug ? Presets.bySlug(slug) : null;
        return (preset != null ? preset : Presets.CLASSIC_CONSPIRACY).config().table().minPlayers();
    }

    private static Map<?, ?> read(String gameConfig) {
        if (gameConfig == null || gameConfig.isBlank()) return Map.of();
        try {
            return JSON.readValue(gameConfig, Map.class);
        } catch (Exception e) {
            return Map.of();
        }
    }
}
