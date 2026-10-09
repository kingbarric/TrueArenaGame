import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One board look: the colour of the squares pieces sit on, the empty ones,
/// and the frame around them.
class BoardPalette {
  const BoardPalette({
    required this.id,
    required this.label,
    required this.darkSquare,
    required this.lightSquare,
    required this.darkGrain,
    required this.lightGrain,
    required this.frameTop,
    required this.frameBottom,
  });

  final String id;
  final String label;
  final Color darkSquare;
  final Color lightSquare;
  final Color darkGrain;
  final Color lightGrain;
  final Color frameTop;
  final Color frameBottom;
}

/// One pair of piece colors. Every pair must stay legible against every
/// `BoardPalette` — check a new pair against the darkest board's playing
/// squares (the black ones) before adding it.
class PiecePalette {
  const PiecePalette({
    required this.id,
    required this.label,
    required this.aTop,
    required this.aMid,
    required this.aRim,
    required this.bTop,
    required this.bMid,
    required this.bRim,
  });

  final String id;
  final String label;
  final Color aTop;
  final Color aMid;
  final Color aRim;
  final Color bTop;
  final Color bMid;
  final Color bRim;
}

/// Four boards, each with a clear difference between the squares pieces
/// sit on (`darkSquare`) and the empty ones (`lightSquare`) — the older
/// all-brown set was too dark and the grid was hard to read. The first is
/// the default. Saved choices from the old set fall back to it.
///
/// The grain colours stay close to their square colour on purpose: the
/// squares should look like clean flat tiles, not a busy texture.
const List<BoardPalette> boardPalettes = [
  BoardPalette(
    id: 'classic',
    label: 'Black & White',
    darkSquare: Color(0xff1b1b1f),
    lightSquare: Color(0xfff4f1ea),
    darkGrain: Color(0xff242429),
    lightGrain: Color(0xffe6e2d6),
    frameTop: Color(0xff3a3a40),
    frameBottom: Color(0xff121214),
  ),
  BoardPalette(
    id: 'tournament',
    label: 'Green & Cream',
    darkSquare: Color(0xff2f6f4a),
    lightSquare: Color(0xfff0e8c8),
    darkGrain: Color(0xff3a7d55),
    lightGrain: Color(0xffe2d9b4),
    frameTop: Color(0xff3f8a5c),
    frameBottom: Color(0xff1d4630),
  ),
  BoardPalette(
    id: 'ocean',
    label: 'Blue & Ice',
    darkSquare: Color(0xff2a5d9f),
    lightSquare: Color(0xffe3edf8),
    darkGrain: Color(0xff3468ab),
    lightGrain: Color(0xffd0deef),
    frameTop: Color(0xff3a72b8),
    frameBottom: Color(0xff183a68),
  ),
  BoardPalette(
    id: 'wood',
    label: 'Light Wood',
    darkSquare: Color(0xff8a5530),
    lightSquare: Color(0xfff0d9b0),
    darkGrain: Color(0xff96603a),
    lightGrain: Color(0xffe4cb9d),
    frameTop: Color(0xffa8693a),
    frameBottom: Color(0xff5a3318),
  ),
];

/// Bright, saturated pairs that are easy to tell apart from each other and
/// from every board above — never a dark piece colour, which was what
/// blended into the board before.
const List<PiecePalette> piecePalettes = [
  // The default: red against blue, both bright on the black squares.
  PiecePalette(
    id: 'red_blue',
    label: 'Red vs. Blue',
    aTop: Color(0xffff6f60),
    aMid: Color(0xffe53935),
    aRim: Color(0xff8e1b17),
    bTop: Color(0xff8cc4ff),
    bMid: Color(0xff2f7cf6),
    bRim: Color(0xff123f8f),
  ),
  PiecePalette(
    id: 'red_white',
    label: 'Red vs. White',
    aTop: Color(0xffff6f60),
    aMid: Color(0xffe53935),
    aRim: Color(0xff8e1b17),
    bTop: Color(0xffffffff),
    bMid: Color(0xffeceff1),
    bRim: Color(0xff90a4ae),
  ),
  PiecePalette(
    id: 'gold_sky',
    label: 'Gold vs. Sky',
    aTop: Color(0xffffe27a),
    aMid: Color(0xffffb300),
    aRim: Color(0xff8a5a00),
    bTop: Color(0xff9fe0ff),
    bMid: Color(0xff29a8f0),
    bRim: Color(0xff0d5a8c),
  ),
  PiecePalette(
    id: 'pink_lime',
    label: 'Pink vs. Lime',
    aTop: Color(0xffff8ac6),
    aMid: Color(0xffff3d9a),
    aRim: Color(0xff9c1560),
    bTop: Color(0xffe2ff7a),
    bMid: Color(0xffa6e022),
    bRim: Color(0xff4f7a0a),
  ),
  PiecePalette(
    id: 'orange_teal',
    label: 'Orange vs. Teal',
    aTop: Color(0xffffb35c),
    aMid: Color(0xffff8a1f),
    aRim: Color(0xff8f4a08),
    bTop: Color(0xff6ee7f0),
    bMid: Color(0xff1fc2d4),
    bRim: Color(0xff0a6674),
  ),
];

BoardPalette boardPaletteById(String id) => boardPalettes.firstWhere((p) => p.id == id, orElse: () => boardPalettes.first);
PiecePalette piecePaletteById(String id) => piecePalettes.firstWhere((p) => p.id == id, orElse: () => piecePalettes.first);

/// Persists the player's board/piece color choice locally (per-device
/// cosmetic preference — no reason this needs to touch the server or be
/// shared between viewers of the same game).
class DraughtsThemeController extends ChangeNotifier {
  DraughtsThemeController._(this._board, this._piece);

  static const _boardKey = 'draughts.boardTheme';
  static const _pieceKey = 'draughts.pieceTheme';

  BoardPalette _board;
  PiecePalette _piece;

  BoardPalette get board => _board;
  PiecePalette get piece => _piece;

  static Future<DraughtsThemeController> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return DraughtsThemeController._(
        boardPaletteById(prefs.getString(_boardKey) ?? boardPalettes.first.id),
        piecePaletteById(prefs.getString(_pieceKey) ?? piecePalettes.first.id),
      );
    } catch (_) {
      return DraughtsThemeController._(boardPalettes.first, piecePalettes.first);
    }
  }

  Future<void> setBoard(BoardPalette p) async {
    _board = p;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString(_boardKey, p.id);
    } catch (_) {
      // best-effort — a failed save just means the choice doesn't survive a restart
    }
  }

  Future<void> setPiece(PiecePalette p) async {
    _piece = p;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString(_pieceKey, p.id);
    } catch (_) {}
  }
}
