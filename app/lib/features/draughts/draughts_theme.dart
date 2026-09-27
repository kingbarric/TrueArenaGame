import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One board wood tone — dark/light squares stay the same walnut *species*
/// (see `draughts_game_screen.dart`'s `_PlankCell` doc), just re-stained.
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

/// One pair of piece colors. Every preset here is chosen to stay legible
/// against every `BoardPalette` above — that was the actual bug report
/// ("piece is too dark and blends with the board") — so don't add a pair
/// without checking it against the darkest board tone.
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

const List<BoardPalette> boardPalettes = [
  BoardPalette(
    id: 'walnut',
    label: 'Walnut',
    darkSquare: Color(0xff251a10),
    lightSquare: Color(0xff7a5230),
    darkGrain: Color(0xff0a0603),
    lightGrain: Color(0xff4a3018),
    frameTop: Color(0xff5c3a1c),
    frameBottom: Color(0xff2e1c0e),
  ),
  BoardPalette(
    id: 'ebony',
    label: 'Ebony',
    darkSquare: Color(0xff17110c),
    lightSquare: Color(0xff4a3a2c),
    darkGrain: Color(0xff000000),
    lightGrain: Color(0xff241a12),
    frameTop: Color(0xff3a2c1e),
    frameBottom: Color(0xff140e08),
  ),
  BoardPalette(
    id: 'rosewood',
    label: 'Rosewood',
    darkSquare: Color(0xff2e1210),
    lightSquare: Color(0xff8a4030),
    darkGrain: Color(0xff100604),
    lightGrain: Color(0xff5a241a),
    frameTop: Color(0xff6b2e1e),
    frameBottom: Color(0xff33130c),
  ),
  BoardPalette(
    id: 'driftwood',
    label: 'Driftwood Ash',
    darkSquare: Color(0xff40382c),
    lightSquare: Color(0xffa89778),
    darkGrain: Color(0xff1c1710),
    lightGrain: Color(0xff6b5c42),
    frameTop: Color(0xff7a6b52),
    frameBottom: Color(0xff363024),
  ),
  BoardPalette(
    id: 'mahogany',
    label: 'Mahogany Fire',
    darkSquare: Color(0xff33140a),
    lightSquare: Color(0xffb35a24),
    darkGrain: Color(0xff140704),
    lightGrain: Color(0xff6b2e10),
    frameTop: Color(0xff8a3c14),
    frameBottom: Color(0xff2e1206),
  ),
];

const List<PiecePalette> piecePalettes = [
  PiecePalette(
    id: 'terracotta_ivory',
    label: 'Terracotta vs. Ivory',
    aTop: Color(0xffe8b25a),
    aMid: Color(0xffc9822f),
    aRim: Color(0xff6b3f16),
    bTop: Color(0xfff2ead9),
    bMid: Color(0xffcfc3a8),
    bRim: Color(0xff7a6f56),
  ),
  PiecePalette(
    id: 'amber_slate',
    label: 'Amber vs. Slate',
    aTop: Color(0xffffcf7a),
    aMid: Color(0xffe0a030),
    aRim: Color(0xff7a4e10),
    bTop: Color(0xff8fa3b8),
    bMid: Color(0xff546a80),
    bRim: Color(0xff26333f),
  ),
  PiecePalette(
    id: 'coral_teal',
    label: 'Coral vs. Teal',
    aTop: Color(0xffff9d7a),
    aMid: Color(0xffe06848),
    aRim: Color(0xff7a2a18),
    bTop: Color(0xff5ecfc0),
    bMid: Color(0xff2a8a7e),
    bRim: Color(0xff123a34),
  ),
  PiecePalette(
    id: 'bone_charcoal',
    label: 'Bone vs. Charcoal',
    aTop: Color(0xfff5ecd8),
    aMid: Color(0xffd8c9a3),
    aRim: Color(0xff8a7a52),
    bTop: Color(0xff6a7078),
    bMid: Color(0xff3a3f46),
    bRim: Color(0xff16181c),
  ),
  PiecePalette(
    id: 'gold_crimson',
    label: 'Gold vs. Crimson',
    aTop: Color(0xffffe08a),
    aMid: Color(0xffe0ab30),
    aRim: Color(0xff7a5610),
    bTop: Color(0xffe0607a),
    bMid: Color(0xffa32e4a),
    bRim: Color(0xff4a1220),
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
