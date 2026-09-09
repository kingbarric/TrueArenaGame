package app.truearena.game.truearena;

import app.truearena.engine.ConfigVocab;
import app.truearena.engine.GameConfig;

import java.util.ArrayList;
import java.util.List;

/**
 * Validates a {@link GameConfig} against docs/GAME_CONFIG.md §8. Errors block a launch;
 * warnings are surfaced in the lobby but do not.
 */
public final class ConfigValidator {

    public record Result(List<String> errors, List<String> warnings) {
        public boolean ok() {
            return errors.isEmpty();
        }
    }

    public static Result validate(GameConfig c) {
        List<String> err = new ArrayList<>();
        List<String> warn = new ArrayList<>();

        if (c.catalogVersion() != ConfigVocab.CATALOG_VERSION) {
            err.add("unknown catalogVersion " + c.catalogVersion() + " (this build serves " + ConfigVocab.CATALOG_VERSION + ")");
        }

        GameConfig.Table t = c.table();
        if (t == null) {
            err.add("table is required");
            return new Result(err, warn);
        }
        int lo = t.adminOverride() ? 4 : t.minPlayers();
        int hi = t.adminOverride() ? 20 : t.maxPlayers();
        if (t.players() < lo || t.players() > hi) {
            err.add("players " + t.players() + " outside " + lo + "–" + hi
                    + (t.adminOverride() ? "" : " (turn on adminOverride to widen to 4–20)"));
        } else if (t.adminOverride() && (t.players() < t.minPlayers() || t.players() > t.maxPlayers())) {
            warn.add("players " + t.players() + " is outside the recommended "
                    + t.minPlayers() + "–" + t.maxPlayers() + " — balance may shift");
        }
        int traitors = t.traitorCurve() == null || t.traitorCurve().isEmpty() ? 0 : t.resolveTraitors(t.players());
        if (traitors < 1) {
            err.add("traitorCurve resolves to " + traitors + " for " + t.players() + " players");
        } else if (traitors > t.players() / 2 - 1) {
            err.add("traitor count " + traitors + " is too high for " + t.players() + " players (max " + (t.players() / 2 - 1) + ")");
        }

        inSet("revealOnElimination", c.revealOnElimination(), ConfigVocab.REVEAL, err);
        inSet("tieBreak", c.tieBreak(), ConfigVocab.TIE_BREAK, err);
        if (c.secondTie() != null) {
            inSet("secondTie", c.secondTie(), ConfigVocab.SECOND_TIE, err);
        }
        inSet("afk", c.afk(), ConfigVocab.AFK, err);
        inSet("voteReveal", c.voteReveal(), ConfigVocab.VOTE_REVEAL, err);
        inSet("endgameVeil", c.endgameVeil(), ConfigVocab.VEIL, err);

        GameConfig.NightKill nk = c.nightKill();
        if (nk == null) {
            err.add("nightKill is required");
        } else {
            inSet("nightKill.openingNight", nk.openingNight(), ConfigVocab.OPENING_NIGHT, err);
            if (nk.doubleAfterRound() != null && nk.doubleAfterRound() < 0) {
                err.add("nightKill.doubleAfterRound must be >= 0 or null");
            }
        }

        GameConfig.Timers tm = c.timers();
        if (tm == null) {
            err.add("timers is required");
        } else {
            range("timers.night", tm.night(), 30, 120, err);
            range("timers.roundTable", tm.roundTable(), 60, 600, err);
            range("timers.vote", tm.vote(), 30, 90, err);
        }

        for (String id : c.twists().keySet()) {
            if (!ConfigVocab.TWISTS.contains(id) || !TwistRegistry.isKnown(id)) {
                err.add("unknown twist '" + id + "' for catalogVersion " + c.catalogVersion());
            }
        }

        long specialFaithfulNeed = c.twists().keySet().stream()
                .filter(id -> id.equals("secret_accusation") || id.equals("blackmail") || id.equals("double_agent"))
                .count();
        if (specialFaithfulNeed > Math.max(0, t.players() - traitors - 1)) {
            warn.add("enabled twists need " + specialFaithfulNeed + " special Faithful but only "
                    + Math.max(0, t.players() - traitors - 1) + " are available");
        }

        int veil = c.veilThreshold();
        if (veil > 0 && veil >= t.players()) {
            warn.add("veiled endgame threshold (" + veil + ") is at or above the player count — votes stay hidden from the start");
        }

        return new Result(err, warn);
    }

    private static void inSet(String field, String value, java.util.Set<String> allowed, List<String> err) {
        if (value == null || !allowed.contains(value)) {
            err.add(field + " '" + value + "' is not one of " + allowed);
        }
    }

    private static void range(String field, int value, int min, int max, List<String> err) {
        if (value < min || value > max) {
            err.add(field + " " + value + " outside " + min + "–" + max);
        }
    }

    private ConfigValidator() {
    }
}
