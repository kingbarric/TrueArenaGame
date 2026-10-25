package app.truearena.api.huudspace;

import app.truearena.engine.GameEvent;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * A game's public log, told as the lines under a Live Huud's card: who did
 * what just now. Pure — names are filled in afterwards. Only public events
 * are ever read, so nothing secret (a hand, a Traitor's identity) can leak;
 * the ones worth stopping a scroll for are {@code notable}, and an ordinary
 * move only shows when nothing else happened.
 */
final class HuudMomentText {

    /** {@code text} names other players as {0}, {1}… — their ids are {@code mentions}. */
    record Line(String actor, String text, List<String> mentions, boolean notable) {
    }

    private HuudMomentText() {
    }

    /** The newest notable lines (at most {@code max}), or the newest ordinary one when nothing stood out. */
    static List<Line> pick(String gameType, List<GameEvent> events, Map<String, String> sides, int max) {
        List<Line> notable = new ArrayList<>();
        Line ordinary = null;
        for (int i = events.size() - 1; i >= 0 && notable.size() < max; i--) {
            GameEvent e = events.get(i);
            if (e.visibility() == null || !e.visibility().isPublic()) continue;
            Line line = describe(gameType, e.type(), e.payload() == null ? Map.of() : e.payload(), sides).orElse(null);
            if (line == null) continue;
            if (line.notable()) notable.add(line);
            else if (ordinary == null) ordinary = line;
        }
        return notable.isEmpty() && ordinary != null ? List.of(ordinary) : notable;
    }

    /** Who plays which side, from the opening event: Chess white/black, Draughts A/B. */
    static Map<String, String> sides(String gameType, GameEvent opening) {
        if (opening == null || !"GAME_STARTED".equals(opening.type()) || opening.payload() == null) return Map.of();
        Map<String, Object> p = opening.payload();
        return switch (gameType == null ? "" : gameType) {
            case "chess" -> sideMap("white", str(p, "white"), "black", str(p, "black"));
            case "draughts" -> sideMap("A", str(p, "playerA"), "B", str(p, "playerB"));
            default -> Map.of();
        };
    }

    static Optional<Line> describe(String gameType, String type, Map<String, Object> p, Map<String, String> sides) {
        return Optional.ofNullable(switch (gameType == null ? "" : gameType) {
            case "whot" -> whot(type, p);
            case "chess" -> chess(type, p, sides);
            case "draughts" -> draughts(type, p, sides);
            case "ludo" -> ludo(type, p);
            case "goosi" -> goosi(type, p);
            case "monopoly" -> huudpoly(type, p);
            case "wordbluff" -> wordBluff(type, p);
            case "truearena" -> traitors(type, p);
            default -> null;
        });
    }

    private static Line whot(String type, Map<String, Object> p) {
        return switch (type) {
            case "GENERAL_MARKET" -> line(str(p, "by"), "called General Market. Everyone picks one", true);
            case "CARD_PLAYED" -> {
                String by = str(p, "by");
                if (handSize(p, by) == 1) yield line(by, "is on last card!", true);
                String card = str(p, "card");
                int dash = card.lastIndexOf('-');
                String shape = dash < 0 ? card : card.substring(0, dash);
                int number = dash < 0 ? -1 : toInt(card.substring(dash + 1));
                yield switch (number) {
                    case 1 -> line(by, "played Hold On", true);
                    case 2 -> line(by, "played Pick Two", true);
                    case 8 -> line(by, "played Suspension", true);
                    case 20 -> {
                        String called = str(p, "calledShape");
                        yield line(by, called.isEmpty() ? "played Whot" : "played Whot and asked for " + plural(called), true);
                    }
                    default -> line(by, "played " + capitalise(shape) + " " + number, false);
                };
            }
            case "CARD_DRAWN" -> num(p, "count") >= 2
                    ? line(str(p, "by"), "picked " + num(p, "count") + " cards", true)
                    : line(str(p, "by"), "went to market", false);
            case "PLAYER_FORFEITED" -> line(str(p, "player"), "left the game", false);
            case "GAME_OVER" -> line(str(p, "winner"), "won the game!", true);
            default -> null;
        };
    }

    private static Line chess(String type, Map<String, Object> p, Map<String, String> sides) {
        return switch (type) {
            case "MOVE_PLAYED" -> {
                String who = sides.get(str(p, "side"));
                String san = str(p, "san");
                if (!str(p, "castle").isEmpty()) yield line(who, "castled", true);
                if (!str(p, "promotion").isEmpty()) yield line(who, "promoted a pawn (" + san + ")", true);
                String captured = str(p, "captured");
                if (!captured.isEmpty()) yield line(who, "took a " + pieceName(captured) + " (" + san + ")", true);
                if (Boolean.TRUE.equals(p.get("check"))) yield line(who, "gave check (" + san + ")", true);
                yield line(who, "played " + san, false);
            }
            case "DRAW_OFFERED" -> line(str(p, "by"), "offered a draw", true);
            case "GAME_OVER" -> {
                String winner = sides.get(str(p, "winningSide"));
                yield winner == null ? line(null, "The game ended in a draw", true)
                        : line(winner, "won by " + str(p, "reason").replace('_', ' '), true);
            }
            default -> null;
        };
    }

    private static Line draughts(String type, Map<String, Object> p, Map<String, String> sides) {
        return switch (type) {
            case "PIECE_CAPTURED" -> line(sides.get(str(p, "side")), "captured a piece", true);
            case "PIECE_MOVED" -> line(sides.get(str(p, "side")), "moved a piece", false);
            case "DRAW_OFFERED" -> line(str(p, "by"), "offered a draw", true);
            case "GAME_OVER" -> {
                String winner = sides.get(str(p, "winningSide"));
                yield winner == null ? line(null, "The game ended in a draw", true) : line(winner, "won the game!", true);
            }
            default -> null;
        };
    }

    private static Line ludo(String type, Map<String, Object> p) {
        return switch (type) {
            case "PIECE_MOVED" -> {
                String player = str(p, "player");
                List<String> victims = new ArrayList<>();
                if (p.get("captured") instanceof Collection<?> captured) {
                    for (Object c : captured) {
                        String id = String.valueOf(c);
                        int colon = id.lastIndexOf(':');
                        victims.add(colon < 0 ? id : id.substring(0, colon));
                    }
                }
                if (!victims.isEmpty()) yield new Line(player, "sent {0} back home", List.of(victims.getFirst()), true);
                if (num(p, "to") == 56) yield line(player, "got a token home", true);
                if (num(p, "from") == -1) yield line(player, "brought a token out", false);
                yield line(player, "moved a token", false);
            }
            case "DICE_ROLLED" -> p.get("dice") instanceof Collection<?> dice && dice.stream().anyMatch(d -> toInt(String.valueOf(d)) == 6)
                    ? line(str(p, "player"), "rolled a six", false) : null;
            case "PLAYER_FORFEITED" -> line(str(p, "player"), "left the game", false);
            default -> null;
        };
    }

    private static Line goosi(String type, Map<String, Object> p) {
        return switch (type) {
            case "CAPTURED" -> num(p, "count") > 0
                    ? line(str(p, "by"), "captured " + num(p, "count") + " seeds", true) : null;
            case "PLAYER_RESIGNED" -> line(str(p, "player"), "resigned", true);
            case "GAME_OVER" -> p.get("winners") instanceof List<?> winners && winners.size() == 1
                    ? line(String.valueOf(winners.getFirst()), "won the game!", true)
                    : line(null, "The game ended level", true);
            default -> null;
        };
    }

    private static Line huudpoly(String type, Map<String, Object> p) {
        return switch (type) {
            case "BUILT" -> line(str(p, "player"), num(p, "buildings") >= 5 ? "built a hotel" : "built a house", true);
            case "BANKRUPT" -> line(str(p, "player"), "went bankrupt", true);
            case "SENT_TO_JAIL" -> line(str(p, "player"), "went to jail", true);
            case "GAME_ENDED" -> line(str(p, "winner"), "won the game!", true);
            case "PASSED_GO" -> line(str(p, "player"), "passed GO", false);
            default -> null;
        };
    }

    private static Line wordBluff(String type, Map<String, Object> p) {
        return switch (type) {
            case "WORD_RESOLVED" -> "correct".equals(str(p, "result")) && !str(p, "word").isEmpty()
                    ? line(null, "“" + str(p, "word") + "” was guessed", true) : null;
            case "GAME_OVER" -> {
                String team = str(p, "winningTeam");
                yield team.isEmpty() || "draw".equals(team) ? line(null, "The game ended level", true)
                        : line(null, "Team " + team + " won " + num(p, "teamAScore") + "–" + num(p, "teamBScore"), true);
            }
            default -> null;
        };
    }

    private static Line traitors(String type, Map<String, Object> p) {
        return switch (type) {
            case "PUBLIC_ACCUSATION" -> new Line(str(p, "by"), "accused {0}", List.of(str(p, "accused")), true);
            case "BANISHED" -> line(str(p, "id"), "was banished", true);
            case "MORNING_REVEAL" -> str(p, "eliminated").isEmpty() ? null
                    : line(str(p, "eliminated"), "was murdered in the night", true);
            case "NO_MURDER" -> line(null, "Nobody was murdered last night", true);
            case "FINAL_VOTE_OPEN" -> line(null, "The final vote is open", true);
            case "ROUND_TABLE_OPEN" -> line(null, "The round table is open", false);
            case "VOTE_PROGRESS" -> line(null, num(p, "locked") + " of " + num(p, "total") + " have voted", false);
            case "GAME_OVER" -> "traitors".equals(str(p, "winningSide"))
                    ? line(null, "The Traitors win!", true) : line(null, "The Faithful win!", true);
            default -> null;
        };
    }

    // ---------------------------------------------------------------- helpers

    private static Line line(String actor, String text, boolean notable) {
        return new Line(actor == null || actor.isEmpty() ? null : actor, text, List.of(), notable);
    }

    private static Map<String, String> sideMap(String a, String playerA, String b, String playerB) {
        return playerA.isEmpty() || playerB.isEmpty() ? Map.of() : Map.of(a, playerA, b, playerB);
    }

    private static String str(Map<String, Object> p, String key) {
        Object v = p.get(key);
        return v == null ? "" : String.valueOf(v);
    }

    private static int num(Map<String, Object> p, String key) {
        Object v = p.get(key);
        return v instanceof Number n ? n.intValue() : toInt(v == null ? "" : String.valueOf(v));
    }

    private static int toInt(String s) {
        try {
            return Integer.parseInt(s.trim());
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    private static int handSize(Map<String, Object> p, String player) {
        return p.get("handSizes") instanceof Map<?, ?> sizes && sizes.get(player) instanceof Number n ? n.intValue() : -1;
    }

    private static String pieceName(String code) {
        char kind = code.isEmpty() ? 'P' : Character.toUpperCase(code.charAt(code.length() - 1));
        return switch (kind) {
            case 'N' -> "knight";
            case 'B' -> "bishop";
            case 'R' -> "rook";
            case 'Q' -> "queen";
            case 'K' -> "king";
            default -> "pawn";
        };
    }

    private static String plural(String shape) {
        return shape.endsWith("s") ? shape + "es" : shape + "s";
    }

    private static String capitalise(String s) {
        return s.isEmpty() ? s : Character.toUpperCase(s.charAt(0)) + s.substring(1);
    }
}
