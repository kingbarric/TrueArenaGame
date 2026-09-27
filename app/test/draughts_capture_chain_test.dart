import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/features/draughts/draughts_rules.dart';

/// Regression cover for the turn that used to hang on "MUST CAPTURE".
///
/// Mid-chain, the board-wide `requiredCaptureCount` is the wrong figure to
/// filter a continuation against: it rescans every piece you own, so a
/// *different* piece with a longer capture available makes it demand a total
/// the piece you're actually jumping with can no longer reach. Nothing is
/// then highlighted, every tap is a no-op, and the turn only ends when the
/// timer runs out.
///
/// The server never had this bug — it keeps the turn's required total and
/// subtracts what's been captured so far — so the fix was to mirror that on
/// the client rather than recompute.
void main() {
  /// Two independent two-capture chains for side A, far enough apart not to
  /// interact. Starting either one leaves that piece with exactly one
  /// capture left while the other still offers two.
  List<String?> twoRivalChains() {
    final board = List<String?>.filled(boardSize, null);
    void put(int row, int col, String piece) => board[squareOf(row, col)] = piece;

    // Chain 1: A at (2,1) jumps (3,2) to (4,3), then (5,4) to (6,5).
    put(2, 1, 'A_MAN');
    put(3, 2, 'B_MAN');
    put(5, 4, 'B_MAN');

    // Chain 2: A at (2,7) jumps (3,8) to (4,9), then (5,8) to (6,7).
    put(2, 7, 'A_MAN');
    put(3, 8, 'B_MAN');
    put(5, 8, 'B_MAN');
    return board;
  }

  test('the position really does offer two rival two-capture chains', () {
    final board = twoRivalChains();
    expect(requiredCaptureCount(board, 'A'), 2);
    expect(maxCaptureCount(board, squareOf(2, 1)), 2);
    expect(maxCaptureCount(board, squareOf(2, 7)), 2);
  });

  test('the first jump of a chain is offered', () {
    final board = twoRivalChains();
    final from = squareOf(2, 1);
    expect(legalDestinationsFrom(board, from, 2), contains(squareOf(4, 3)));
  });

  group('after the first capture of the chain', () {
    late List<String?> board;
    late int active;

    setUp(() {
      board = twoRivalChains();
      // Play (2,1) x (3,2) -> (4,3) by hand, as the event stream would.
      board[squareOf(4, 3)] = board[squareOf(2, 1)];
      board[squareOf(2, 1)] = null;
      board[squareOf(3, 2)] = null;
      active = squareOf(4, 3);
    });

    test('the active piece has exactly one capture left', () {
      expect(maxCaptureCount(board, active), 1);
    });

    test('the old board-wide recompute still demands two — this was the bug', () {
      // The rival chain is untouched, so a fresh scan still says 2...
      expect(requiredCaptureCount(board, 'A'), 2);
      // ...and asking for a 2-capture continuation from a piece that only has
      // 1 left returns nothing at all. That empty list is the frozen turn.
      expect(legalDestinationsFrom(board, active, 2), isEmpty);
    });

    test('filtering by what the turn still owes finds the continuation', () {
      const required = 2;
      const capturedSoFar = 1;
      expect(
        legalDestinationsFrom(board, active, required - capturedSoFar),
        contains(squareOf(6, 5)),
      );
    });
  });

  test('a turn with no capture available falls back to simple moves', () {
    final board = List<String?>.filled(boardSize, null);
    board[squareOf(4, 3)] = 'A_MAN';
    expect(requiredCaptureCount(board, 'A'), 0);
    // remaining == 0 must mean "ordinary move", not "no legal move".
    expect(legalDestinationsFrom(board, squareOf(4, 3), 0), isNotEmpty);
  });
}
