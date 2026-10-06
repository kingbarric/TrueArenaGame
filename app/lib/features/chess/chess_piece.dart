import 'package:flutter/material.dart';

import 'chess_view.dart';

/// A chess piece drawn from its Unicode glyph: cream with a dark edge for
/// white, near-black with a light edge for black, so both read on either
/// square colour.
class ChessPieceGlyph extends StatelessWidget {
  const ChessPieceGlyph({super.key, required this.code, required this.size});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final white = code.startsWith('w');
    final glyph = glyphFor(code);
    final base = TextStyle(
      fontSize: size,
      height: 1.0,
      fontFamilyFallback: const [
        'Apple Symbols',
        'Segoe UI Symbol',
        'Noto Sans Symbols 2',
        'DejaVu Sans'
      ],
    );
    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        child: Stack(alignment: Alignment.center, children: [
          Text(glyph,
              style: base.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = size * 0.07
                  ..strokeJoin = StrokeJoin.round
                  ..color =
                      white ? const Color(0xff2b1d10) : const Color(0xffe9dcc4),
              )),
          Text(glyph,
              style: base.copyWith(
                color:
                    white ? const Color(0xfffff8ea) : const Color(0xff1d1712),
                shadows: const [
                  Shadow(
                      color: Color(0x66000000),
                      blurRadius: 3,
                      offset: Offset(0, 1.5)),
                ],
              )),
        ]),
      ),
    );
  }
}
