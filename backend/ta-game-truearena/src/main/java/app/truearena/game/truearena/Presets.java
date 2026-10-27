package app.truearena.game.truearena;

import app.truearena.engine.ConfigVocab;
import app.truearena.engine.GameConfig;

import java.util.List;
import java.util.Map;

/** The five shipped modes as {@link GameConfig} (docs/GAME_CONFIG.md §6). Seeded as {@code scope='builtin'}. */
public final class Presets {

    public record Mode(String slug, String name, String tag, String description, GameConfig config) {
    }

    public static final Mode CLASSIC_CONSPIRACY = new Mode(
            "classic_conspiracy", "Classic Conspiracy", "Default",
            "No powers, no shields — pure deduction. Every murder leaves a clue, and the ghosts settle a deadlock.",
            cfg("classic_conspiracy", 6, 10, List.of(pair(6, 2)), 8,
                    nightKill("on", null, false, false),
                    "always", "revote", "no_elimination", "final_4",
                    Map.of("crime_clues", Map.of(),
                            "crowd_hunch", Map.of(),
                            "ghost_jury", Map.of("afterRevote", true))));

    public static final Mode MIDNIGHT_HEIST = new Mode(
            "midnight_heist", "Midnight Heist", null,
            "The Traitors bake a pie — a shield or poison — and serve it with a clue. Lose one of their own, and they recruit.",
            cfg("midnight_heist", 7, 12, List.of(pair(7, 2), pair(10, 3)), 10,
                    nightKill("on", null, false, false),
                    "always", "host_decides", "no_elimination", "final_5",
                    Map.of("poisoned_pie", Map.of("uses", 1, "clueTruth", 0.67),
                            "immunity_coin", Map.of(),
                            "recruiting", Map.of(),
                            "crowd_hunch", Map.of(),
                            "ghost_jury", Map.of())));

    public static final Mode BLOOD_MOON = new Mode(
            "blood_moon", "Blood Moon", null,
            "Single murders in rounds 1–2, then a double murder is on the table. The Black Spot steals a vote.",
            cfg("blood_moon", 8, 14, List.of(pair(8, 3)), 10,
                    nightKill("on", 2, true, false),
                    "always", "random", "no_elimination", "final_5",
                    Map.of("black_spot", Map.of(),
                            "recruiting", Map.of(),
                            "crowd_hunch", Map.of(),
                            "ghost_jury", Map.of())));

    public static final Mode THE_LAST_ALIBI = new Mode(
            "the_last_alibi", "The Last Alibi", null,
            "Everyone names who they were with each night. Reveals alternate public, hidden, public; the Traitors must agree.",
            cfg("the_last_alibi", 9, 16, List.of(pair(9, 3), pair(13, 4)), 12,
                    nightKill("on", null, false, true),
                    "alternating", "sudden_death", "no_elimination", "final_6",
                    Map.of("alibis", Map.of(),
                            "crime_clues", Map.of(),
                            "recruiting", Map.of(),
                            "crowd_hunch", Map.of(),
                            "ghost_jury", Map.of())));

    public static final Mode FINAL_GAMBIT = new Mode(
            "final_gambit", "Final Gambit", null,
            "No opening-night murder. One Faithful holds a secret accusation, another a Seer's lantern — and the final four can make a Last Stand.",
            cfg("final_gambit", 5, 8, List.of(pair(5, 1), pair(7, 2)), 7,
                    nightKill("off", null, false, false),
                    "always", "no_elimination", "no_elimination", "final_4",
                    Map.of("secret_accusation", Map.of("defenseSeconds", 60),
                            "seer_lantern", Map.of(),
                            "last_stand", Map.of(),
                            "recruiting", Map.of(),
                            "crowd_hunch", Map.of(),
                            "ghost_jury", Map.of())));

    public static final List<Mode> ALL = List.of(
            CLASSIC_CONSPIRACY, MIDNIGHT_HEIST, BLOOD_MOON, THE_LAST_ALIBI, FINAL_GAMBIT);

    public static Mode bySlug(String slug) {
        return ALL.stream().filter(m -> m.slug().equals(slug)).findFirst().orElse(null);
    }

    private static List<Integer> pair(int fromPlayers, int traitors) {
        return List.of(fromPlayers, traitors);
    }

    private static GameConfig.NightKill nightKill(String opening, Integer dbl, boolean skip, boolean consensus) {
        return new GameConfig.NightKill(opening, dbl, skip, consensus);
    }

    private static GameConfig cfg(String preset, int min, int max, List<List<Integer>> curve, int players,
                                  GameConfig.NightKill nk, String reveal, String tie, String secondTie,
                                  String veil, Map<String, Map<String, Object>> twists) {
        return new GameConfig(
                ConfigVocab.CATALOG_VERSION, preset,
                new GameConfig.Table(players, min, max, false, curve),
                new GameConfig.Timers(60, 300, 60, 60),
                nk, reveal, tie, secondTie, 30, "abstain", "sequential", veil, twists);
    }

    private Presets() {
    }
}
