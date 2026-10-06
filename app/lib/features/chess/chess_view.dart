/// The parts of a chess game the screen needs, read straight off the
/// server's view. There is no move generator here on purpose: the server
/// publishes `legalMoves` with every snapshot, so the app only ever offers
/// moves the engine has already agreed to.
library;

/// Squares are indexed the way the server indexes them: a1 = 0, h1 = 7,
/// a8 = 56, h8 = 63.
int fileOf(int square) => square % 8;
int rankOf(int square) => square ~/ 8;

String squareName(int square) =>
    '${String.fromCharCode(97 + fileOf(square))}${rankOf(square) + 1}';

int? parseSquare(String? name) {
  if (name == null || name.length != 2) return null;
  final file = name.codeUnitAt(0) - 97;
  final rank = name.codeUnitAt(1) - 49;
  if (file < 0 || file > 7 || rank < 0 || rank > 7) return null;
  return rank * 8 + file;
}

/// Which square sits at a given on-screen cell. White sees a1 at the bottom
/// left; black sees the board turned round, h8 at the bottom left.
int squareAtCell(int row, int col, {required bool flipped}) =>
    flipped ? row * 8 + (7 - col) : (7 - row) * 8 + col;

/// 'w' or 'b' for a piece code like "wN".
String? colorOf(String? code) => code == null || code.isEmpty ? null : code[0];

/// The solid glyph for a piece kind, with the text-presentation selector so
/// Android doesn't swap the pawn for its emoji.
String glyphFor(String code) {
  final glyph = switch (code.length > 1 ? code[1] : '') {
    'K' => '♚',
    'Q' => '♛',
    'R' => '♜',
    'B' => '♝',
    'N' => '♞',
    _ => '♟',
  };
  return '$glyph︎';
}

/// Material value used to order captured pieces and show the lead.
int pieceValue(String code) => switch (code.length > 1 ? code[1] : '') {
      'Q' => 9,
      'R' => 5,
      'B' || 'N' => 3,
      'P' => 1,
      _ => 0,
    };

/// Whether moving [from] → [to] needs the promotion picker.
bool needsPromotion(String? piece, int to) {
  if (piece == null || piece.length < 2 || piece[1] != 'P') return false;
  return piece[0] == 'w' ? rankOf(to) == 7 : rankOf(to) == 0;
}

/// How a finished game ended, in a player's words.
String describeResult(String? reason) => switch (reason) {
      'checkmate' => 'Checkmate',
      'resignation' => 'Resignation',
      'forfeit' => 'Opponent left the game',
      'timeout' => 'Won on time',
      'timeout_vs_insufficient_material' =>
        'Time ran out, but checkmate was impossible',
      'stalemate' => 'Stalemate',
      'dead_position' => 'Neither side can checkmate',
      'seventy_five_move_rule' => '75 moves without a capture or pawn move',
      'fivefold_repetition' => 'Same position five times',
      'threefold_repetition' => 'Threefold repetition claimed',
      'fifty_move_rule' => '50-move rule claimed',
      'agreement' => 'Draw agreed',
      _ => 'Game over',
    };

/// Clock text: m:ss above twenty seconds, then tenths so a scramble reads.
String formatClock(int ms) {
  final clamped = ms < 0 ? 0 : ms;
  final totalSeconds = clamped ~/ 1000;
  if (clamped < 20000) {
    final tenths = (clamped % 1000) ~/ 100;
    return '0:${totalSeconds.toString().padLeft(2, '0')}.$tenths';
  }
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}

/// One snapshot of the game as the server described it.
class ChessView {
  const ChessView({
    this.phase = 'TurnW',
    this.white = '',
    this.black = '',
    this.turn = 'white',
    this.board = const [],
    this.inCheck = false,
    this.moves = const [],
    this.lastFrom,
    this.lastTo,
    this.capturedByWhite = const [],
    this.capturedByBlack = const [],
    this.whiteMs = 0,
    this.blackMs = 0,
    this.incrementMs = 0,
    this.pendingDrawOffer,
    this.canClaimThreefold = false,
    this.canClaimFiftyMove = false,
    this.legalMoves = const {},
    this.winningSide,
    this.resultReason,
  });

  final String phase;
  final String white;
  final String black;
  final String turn;
  final List<String?> board;
  final bool inCheck;
  final List<String> moves;
  final int? lastFrom;
  final int? lastTo;
  final List<String> capturedByWhite;
  final List<String> capturedByBlack;
  final int whiteMs;
  final int blackMs;
  final int incrementMs;
  final String? pendingDrawOffer;
  final bool canClaimThreefold;
  final bool canClaimFiftyMove;
  final Map<int, List<int>> legalMoves;
  final String? winningSide;
  final String? resultReason;

  bool get finished => phase == 'Results';
  bool get hasBoard => board.length == 64;

  factory ChessView.fromJson(Map<String, dynamic> p) {
    final last = (p['lastMove'] as Map?)?.cast<String, dynamic>();
    final legal = <int, List<int>>{};
    final rawLegal = (p['legalMoves'] as Map?) ?? const {};
    for (final e in rawLegal.entries) {
      final from = parseSquare(e.key as String?);
      if (from == null) continue;
      legal[from] = [
        for (final to in (e.value as List? ?? const []))
          if (parseSquare(to as String?) case final sq?) sq
      ];
    }
    List<String> strings(Object? raw) =>
        [for (final v in (raw as List? ?? const [])) v.toString()];
    return ChessView(
      phase: p['phase'] as String? ?? 'TurnW',
      white: p['white'] as String? ?? '',
      black: p['black'] as String? ?? '',
      turn: p['turn'] as String? ?? 'white',
      board: [for (final v in (p['board'] as List? ?? const [])) v as String?],
      inCheck: p['inCheck'] as bool? ?? false,
      moves: strings(p['moves']),
      lastFrom: parseSquare(last?['from'] as String?),
      lastTo: parseSquare(last?['to'] as String?),
      capturedByWhite: strings(p['capturedByWhite']),
      capturedByBlack: strings(p['capturedByBlack']),
      whiteMs: (p['whiteMs'] as num?)?.toInt() ?? 0,
      blackMs: (p['blackMs'] as num?)?.toInt() ?? 0,
      incrementMs: (p['incrementMs'] as num?)?.toInt() ?? 0,
      pendingDrawOffer: p['pendingDrawOffer'] as String?,
      canClaimThreefold: p['canClaimThreefold'] as bool? ?? false,
      canClaimFiftyMove: p['canClaimFiftyMove'] as bool? ?? false,
      legalMoves: legal,
      winningSide: p['winningSide'] as String?,
      resultReason: p['resultReason'] as String?,
    );
  }

  /// The square of [side]'s king, for the check highlight.
  int? kingSquare(String side) {
    final code = side == 'white' ? 'wK' : 'bK';
    final i = board.indexOf(code);
    return i < 0 ? null : i;
  }

  String playerFor(String side) => side == 'white' ? white : black;
}
