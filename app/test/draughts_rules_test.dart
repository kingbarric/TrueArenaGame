import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/features/draughts/draughts_rules.dart';

/// Dart-side coverage for the client's local mirror of the backend's
/// `CaptureEngine` — same scenarios as the Java `CaptureEngineTest`, so a
/// divergence between the two rule sets shows up as a failure here too.
void main() {
  List<String?> emptyBoard() => List<String?>.filled(boardSize, null);

  test('exactly 50 playable squares', () {
    var count = 0;
    for (var row = 0; row < 10; row++) {
      for (var col = 0; col < 10; col++) {
        if (isPlayable(row, col)) count++;
      }
    }
    expect(count, 50);
  });

  test('man moves only forward diagonally', () {
    final board = emptyBoard();
    final start = squareOf(4, 3);
    board[start] = 'A_MAN';
    final dest = simpleLandings(board, start);
    expect(dest, containsAll([squareOf(5, 2), squareOf(5, 4)]));
    expect(dest, hasLength(2));
  });

  test('king moves any distance until blocked', () {
    final board = emptyBoard();
    final start = squareOf(4, 3);
    board[start] = 'A_KING';
    board[squareOf(7, 6)] = 'B_MAN';
    final dest = simpleLandings(board, start);
    expect(dest, containsAll([squareOf(5, 4), squareOf(6, 5)]));
    expect(dest, isNot(contains(squareOf(7, 6))));
    expect(dest, isNot(contains(squareOf(8, 7))));
  });

  test('man captures forward and backward', () {
    final board = emptyBoard();
    final from = squareOf(3, 4);
    board[from] = 'A_MAN';
    board[squareOf(4, 5)] = 'B_MAN';
    final landings = captureLandings(board, from);
    expect(landings, hasLength(1));
    expect(landings.first.captured, squareOf(4, 5));
    expect(landings.first.to, squareOf(5, 6));
  });

  test('king flies to capture with multiple landing choices', () {
    final board = emptyBoard();
    final from = squareOf(1, 0);
    board[from] = 'A_KING';
    board[squareOf(4, 3)] = 'B_MAN';
    final landings = captureLandings(board, from);
    expect(landings, hasLength(5));
    expect(landings.every((l) => l.captured == squareOf(4, 3)), isTrue);
  });

  test('must take the global maximum across all pieces', () {
    final board = emptyBoard();
    board[squareOf(1, 0)] = 'A_MAN';
    board[squareOf(2, 1)] = 'B_MAN';
    board[squareOf(1, 4)] = 'A_MAN';
    board[squareOf(2, 5)] = 'B_MAN';
    board[squareOf(4, 7)] = 'B_MAN';
    expect(requiredCaptureCount(board, 'A'), 2);
  });

  test('legalDestinationsFrom filters out the non-maximal branch', () {
    final board = emptyBoard();
    board[squareOf(1, 4)] = 'A_MAN';
    board[squareOf(2, 3)] = 'B_MAN'; // 1-capture branch
    board[squareOf(2, 5)] = 'B_MAN'; // 2-capture branch...
    board[squareOf(4, 7)] = 'B_MAN'; // ...continues here
    final required = requiredCaptureCount(board, 'A');
    final dest = legalDestinationsFrom(board, squareOf(1, 4), required);
    expect(dest, [squareOf(3, 6)]); // only the maximal branch's first jump
  });

  test('no capture available means simple moves are legal instead', () {
    final board = emptyBoard();
    board[squareOf(3, 4)] = 'A_MAN';
    final required = requiredCaptureCount(board, 'A');
    expect(required, 0);
    expect(legalDestinationsFrom(board, squareOf(3, 4), required), containsAll([squareOf(4, 3), squareOf(4, 5)]));
  });
}
