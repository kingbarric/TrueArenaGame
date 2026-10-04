import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One board wood tone for Goosi's pit tray — same idea as Draughts'
/// `BoardPalette` (`draughts_theme.dart`), reused rather than shared 1:1
/// since Goosi's board has one carved-bowl surface, not alternating light/
/// dark squares.
class GoosiBoardPalette {
  const GoosiBoardPalette({
    required this.id,
    required this.label,
    required this.blurb,
    required this.tray,
    required this.trayGrain,
    required this.bowl,
    required this.bowlRim,
    required this.frameTop,
    required this.frameBottom,
    this.ring,
    this.hinge = false,
    this.radius = 14,
    this.organicEdge = false,
    this.gloss = false,
    this.grain = 1.0,
  });

  final String id;
  final String label;

  /// One line on what the board is, for the picker — these are five
  /// different objects, not five stains of the same one.
  final String blurb;

  final Color tray; // the plank the pits are carved into
  final Color trayGrain;
  final Color bowl; // inside of each carved pit
  final Color bowlRim;
  final Color frameTop;
  final Color frameBottom;

  /// A metal collar turned into the rim of every pit — brass or gold. Null
  /// on the boards that are plain wood all the way through.
  final Color? ring;

  /// The hinge and pins down the centre of a folding travel set.
  final bool hinge;

  /// Outer corner rounding. A carved block is soft; a boxed set is crisp.
  final double radius;

  /// Uneven corners, for the board that was cut from one live-edged plank
  /// rather than squared off in a workshop.
  final bool organicEdge;

  /// A diagonal sheen across the surface, for the lacquered board.
  final bool gloss;

  /// How strongly the grain reads, 0 (painted flat) to 1 (open-pored wood).
  final double grain;
}

/// One seed finish. The default "Market Glass" finish is rendered as the
/// mixed ivory, onyx, green and turquoise beads from the PlayHuud mockup;
/// the other entries remain single-colour cosmetic choices.
class GoosiStonePalette {
  const GoosiStonePalette(
      {required this.id,
      required this.label,
      required this.top,
      required this.mid,
      required this.rim});

  final String id;
  final String label;
  final Color top;
  final Color mid;
  final Color rim;
}

/// The five boards Goosi can be played on. Each is a different object —
/// a shop-bought folding set, a carved block, a worn plank, a lacquered
/// piece, a modern one in ebony and brass — rather than the same tray in
/// five stains.
///
/// The first entry is the default for anyone who hasn't chosen (see
/// [GoosiThemeController.load]) — Macala Classic, the carved block.
const List<GoosiBoardPalette> goosiBoardPalettes = [
  GoosiBoardPalette(
    id: 'oware',
    label: 'Macala Classic',
    blurb: 'Heirloom · hand-cut',
    tray: Color(0xff7a4a24),
    trayGrain: Color(0xff4a2c13),
    bowl: Color(0xff20140a),
    bowlRim: Color(0xffd69858),
    frameTop: Color(0xff6b431f),
    frameBottom: Color(0xff35200f),
    radius: 20,
  ),
  GoosiBoardPalette(
    id: 'folding',
    label: 'The Folding Set',
    blurb: 'Familiar · shop-bought',
    tray: Color(0xffd8b07a),
    trayGrain: Color(0xffb98c53),
    bowl: Color(0xff2f4a35), // green felt in the bottom of each cup
    bowlRim: Color(0xff8a6538),
    frameTop: Color(0xffc99b63),
    frameBottom: Color(0xff8a6538),
    hinge: true,
    radius: 10,
    grain: 0.35,
  ),
  GoosiBoardPalette(
    id: 'riverstone',
    label: 'Riverstone Slab',
    blurb: 'Quiet · worn smooth',
    tray: Color(0xffc9bda8),
    trayGrain: Color(0xffa3947c),
    bowl: Color(0xff6d6250),
    bowlRim: Color(0xff8d8067),
    frameTop: Color(0xffbdb097),
    frameBottom: Color(0xff8d8067),
    organicEdge: true,
    radius: 30,
    grain: 0.55,
  ),
  GoosiBoardPalette(
    id: 'lacquer',
    label: 'Palm Wine Lacquer',
    blurb: 'Ornate · house colours',
    tray: Color(0xff7e2338),
    trayGrain: Color(0xff47121f),
    bowl: Color(0xff3a0e18),
    bowlRim: Color(0xffd9a441),
    frameTop: Color(0xff7e2338),
    frameBottom: Color(0xff47121f),
    ring: Color(0xffd9a441),
    radius: 16,
    gloss: true,
    grain: 0.2,
  ),
  GoosiBoardPalette(
    id: 'ebony',
    label: 'Ebony & Brass',
    blurb: 'Sharp · high contrast',
    tray: Color(0xff2b2724),
    trayGrain: Color(0xff100e0d),
    bowl: Color(0xff17140f),
    bowlRim: Color(0xffb98c3c),
    frameTop: Color(0xff2b2724),
    frameBottom: Color(0xff0a0908),
    ring: Color(0xffb98c3c),
    radius: 14,
    grain: 0.45,
  ),
];

const List<GoosiStonePalette> goosiStonePalettes = [
  GoosiStonePalette(
      id: 'river_stone',
      label: 'Market Glass',
      top: Color(0xfff7f1df),
      mid: Color(0xffc8bfa9),
      rim: Color(0xff544c3a)),
  GoosiStonePalette(
      id: 'amber',
      label: 'Amber',
      top: Color(0xffffcf7a),
      mid: Color(0xffe0a030),
      rim: Color(0xff7a4e10)),
  GoosiStonePalette(
      id: 'jade',
      label: 'Jade',
      top: Color(0xff9de0c0),
      mid: Color(0xff3ea378),
      rim: Color(0xff164a34)),
  GoosiStonePalette(
      id: 'carnelian',
      label: 'Carnelian',
      top: Color(0xffff9d7a),
      mid: Color(0xffe06848),
      rim: Color(0xff7a2a18)),
  GoosiStonePalette(
      id: 'onyx',
      label: 'Onyx',
      top: Color(0xff6a7078),
      mid: Color(0xff3a3f46),
      rim: Color(0xff16181c)),
];

GoosiBoardPalette goosiBoardById(String id) => goosiBoardPalettes
    .firstWhere((p) => p.id == id, orElse: () => goosiBoardPalettes.first);
GoosiStonePalette goosiStoneById(String id) => goosiStonePalettes
    .firstWhere((p) => p.id == id, orElse: () => goosiStonePalettes.first);

/// Persists the player's board/stone color choice locally — same pattern as
/// `DraughtsThemeController`, a per-device cosmetic preference.
class GoosiThemeController extends ChangeNotifier {
  GoosiThemeController._(this._board, this._stone);

  static const _boardKey = 'goosi.boardTheme';
  static const _stoneKey = 'goosi.stoneTheme';

  GoosiBoardPalette _board;
  GoosiStonePalette _stone;

  GoosiBoardPalette get board => _board;
  GoosiStonePalette get stone => _stone;

  static Future<GoosiThemeController> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return GoosiThemeController._(
        goosiBoardById(
            prefs.getString(_boardKey) ?? goosiBoardPalettes.first.id),
        goosiStoneById(
            prefs.getString(_stoneKey) ?? goosiStonePalettes.first.id),
      );
    } catch (_) {
      return GoosiThemeController._(
          goosiBoardPalettes.first, goosiStonePalettes.first);
    }
  }

  Future<void> setBoard(GoosiBoardPalette p) async {
    _board = p;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString(_boardKey, p.id);
    } catch (_) {}
  }

  Future<void> setStone(GoosiStonePalette p) async {
    _stone = p;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString(_stoneKey, p.id);
    } catch (_) {}
  }
}
