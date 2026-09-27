/// A Dart mirror of the backend's `CaptureEngine`/`Board` (see
/// `ta-game-draughts`) — used purely to highlight legal destinations as the
/// player taps around; the server stays the sole authority and re-validates
/// every move, so a bug here means a wrong highlight, never a wrong outcome.
/// Kept in lockstep with the Java version deliberately, including comments,
/// so a rules change on one side is easy to notice as a diff on the other.
library;

const int boardSize = 50;

bool isPlayable(int row, int col) => row >= 0 && row < 10 && col >= 0 && col < 10 && (row + col).isOdd;

int squareOf(int row, int col) {
  if (!isPlayable(row, col)) return -1;
  final colIndexInRow = col ~/ 2;
  return row * 5 + colIndexInRow;
}

int rowOf(int square) => square ~/ 5;

int colOf(int square) {
  final row = rowOf(square);
  final colIndexInRow = square % 5;
  return row.isEven ? colIndexInRow * 2 + 1 : colIndexInRow * 2;
}

const List<(int, int)> directions = [(-1, -1), (-1, 1), (1, -1), (1, 1)];

int step(int square, int dRow, int dCol) => squareOf(rowOf(square) + dRow, colOf(square) + dCol);

/// A board cell's contents, mirroring the Java `Piece` enum's `.name()` strings.
class DraughtsPiece {
  const DraughtsPiece(this.side, this.isKing);
  final String side; // "A" | "B"
  final bool isKing;

  static DraughtsPiece? parse(String? raw) {
    if (raw == null) return null;
    return DraughtsPiece(raw.startsWith('A') ? 'A' : 'B', raw.endsWith('KING'));
  }
}

class Landing {
  const Landing(this.captured, this.to);
  final int captured;
  final int to;
}

List<Landing> captureLandings(List<String?> board, int from) {
  final piece = DraughtsPiece.parse(board[from]);
  final out = <Landing>[];
  if (piece == null) return out;
  for (final (dRow, dCol) in directions) {
    if (piece.isKing) {
      _addKingCaptureLandings(board, from, dRow, dCol, piece.side, out);
    } else {
      _addManCaptureLanding(board, from, dRow, dCol, piece.side, out);
    }
  }
  return out;
}

void _addManCaptureLanding(List<String?> board, int from, int dRow, int dCol, String side, List<Landing> out) {
  final adjacent = step(from, dRow, dCol);
  if (adjacent < 0) return;
  final adjacentPiece = DraughtsPiece.parse(board[adjacent]);
  if (adjacentPiece == null || adjacentPiece.side == side) return;
  final landing = step(adjacent, dRow, dCol);
  if (landing >= 0 && board[landing] == null) {
    out.add(Landing(adjacent, landing));
  }
}

void _addKingCaptureLandings(List<String?> board, int from, int dRow, int dCol, String side, List<Landing> out) {
  var cur = from;
  while (true) {
    cur = step(cur, dRow, dCol);
    if (cur < 0 || board[cur] != null) break;
  }
  if (cur < 0) return;
  final blocker = DraughtsPiece.parse(board[cur]);
  if (blocker == null || blocker.side == side) return;
  final captured = cur;
  var landing = step(captured, dRow, dCol);
  while (landing >= 0 && board[landing] == null) {
    out.add(Landing(captured, landing));
    landing = step(landing, dRow, dCol);
  }
}

List<int> simpleLandings(List<String?> board, int from) {
  final piece = DraughtsPiece.parse(board[from]);
  final out = <int>[];
  if (piece == null) return out;
  for (final (dRow, dCol) in directions) {
    if (!piece.isKing && !_isForward(piece, dRow)) continue;
    if (piece.isKing) {
      var cur = from;
      while (true) {
        cur = step(cur, dRow, dCol);
        if (cur < 0 || board[cur] != null) break;
        out.add(cur);
      }
    } else {
      final to = step(from, dRow, dCol);
      if (to >= 0 && board[to] == null) out.add(to);
    }
  }
  return out;
}

bool _isForward(DraughtsPiece piece, int dRow) => piece.side == 'A' ? dRow > 0 : dRow < 0;

/// The board after one jump. Public because the screen simulates a whole
/// capture chain locally before sending any of it — see the chain builder in
/// `draughts_game_screen.dart`.
List<String?> applyCaptureTo(List<String?> board, int from, Landing landing) =>
    _applyCapture(board, from, landing);

/// The board after an ordinary move. Public for the same reason as
/// [applyCaptureTo] — the screen replays a chosen move locally before
/// sending it.
List<String?> applySimpleMoveTo(List<String?> board, int from, int to) {
  final copy = List<String?>.of(board);
  copy[to] = copy[from];
  copy[from] = null;
  return copy;
}

List<String?> _applyCapture(List<String?> board, int from, Landing landing) {
  final copy = List<String?>.of(board);
  copy[landing.to] = copy[from];
  copy[from] = null;
  copy[landing.captured] = null;
  return copy;
}

int maxCaptureCount(List<String?> board, int from) {
  var best = 0;
  for (final landing in captureLandings(board, from)) {
    final after = _applyCapture(board, from, landing);
    final total = 1 + maxCaptureCount(after, landing.to);
    if (total > best) best = total;
  }
  return best;
}

int requiredCaptureCount(List<String?> board, String side) {
  var best = 0;
  for (var sq = 0; sq < boardSize; sq++) {
    final p = DraughtsPiece.parse(board[sq]);
    if (p != null && p.side == side) {
      final count = maxCaptureCount(board, sq);
      if (count > best) best = count;
    }
  }
  return best;
}

/// Legal destinations for a tap on `from`, already filtered to the maximal
/// capture sequences when a capture is mandatory this turn.
List<int> legalDestinationsFrom(List<String?> board, int from, int requiredTotal) {
  if (requiredTotal > 0) {
    return captureLandings(board, from)
        .where((l) => 1 + maxCaptureCount(_applyCapture(board, from, l), l.to) == requiredTotal)
        .map((l) => l.to)
        .toList();
  }
  return simpleLandings(board, from);
}
