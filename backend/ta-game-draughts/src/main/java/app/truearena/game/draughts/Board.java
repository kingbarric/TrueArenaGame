package app.truearena.game.draughts;

/**
 * Coordinates for the 10x10 international board. Only the 50 dark squares
 * are playable, so the board is stored as a flat 50-slot array (index 0-49)
 * rather than a 100-slot grid — {@link #squareOf} and {@link #rowOf}/
 * {@link #colOf} convert between that index and (row, col), both 0-9.
 *
 * <p>Row 0 is Side A's back row, row 9 is Side B's back row — A moves toward
 * increasing rows, B toward decreasing rows. A square is playable exactly
 * when {@code (row + col)} is odd.
 */
public final class Board {

    public static final int SIZE = 50;

    private Board() {
    }

    public static boolean isPlayable(int row, int col) {
        return row >= 0 && row < 10 && col >= 0 && col < 10 && (row + col) % 2 == 1;
    }

    /** -1 if (row, col) isn't a valid playable square. */
    public static int squareOf(int row, int col) {
        if (!isPlayable(row, col)) {
            return -1;
        }
        int colIndexInRow = col / 2; // 5 playable squares per row, every other column
        return row * 5 + colIndexInRow;
    }

    public static int rowOf(int square) {
        return square / 5;
    }

    public static int colOf(int square) {
        int row = rowOf(square);
        int colIndexInRow = square % 5;
        return row % 2 == 0 ? colIndexInRow * 2 + 1 : colIndexInRow * 2;
    }

    /** The 4 diagonal step directions, as (dRow, dCol) pairs. */
    public static final int[][] DIRECTIONS = {{-1, -1}, {-1, 1}, {1, -1}, {1, 1}};

    /** -1 if stepping (dRow, dCol) from `square` lands off the board. */
    public static int step(int square, int dRow, int dCol) {
        return squareOf(rowOf(square) + dRow, colOf(square) + dCol);
    }
}
