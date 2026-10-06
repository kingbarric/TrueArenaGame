package app.truearena.game.chess;

/** Squares are 0-63: a1 = 0, b1 = 1 … h1 = 7, a2 = 8 … h8 = 63. */
public final class Square {

    public static final int NONE = -1;

    private Square() {
    }

    public static int of(int file, int rank) {
        return rank * 8 + file;
    }

    public static int file(int sq) {
        return sq & 7;
    }

    public static int rank(int sq) {
        return sq >> 3;
    }

    public static boolean onBoard(int file, int rank) {
        return file >= 0 && file < 8 && rank >= 0 && rank < 8;
    }

    public static boolean isLight(int sq) {
        return ((file(sq) + rank(sq)) & 1) == 1;
    }

    public static String name(int sq) {
        return "" + (char) ('a' + file(sq)) + (char) ('1' + rank(sq));
    }

    /** Parses {@code "e4"}; returns {@link #NONE} for anything else. */
    public static int parse(String s) {
        if (s == null || s.length() != 2) {
            return NONE;
        }
        int file = s.charAt(0) - 'a';
        int rank = s.charAt(1) - '1';
        return onBoard(file, rank) ? of(file, rank) : NONE;
    }
}
