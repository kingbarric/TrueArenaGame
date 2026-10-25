import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Original Huud sigils for the private Tell signals. Shapes stay distinct at
/// small sizes and do not depend on an operating system's emoji font.
class HuudSignalArt extends StatelessWidget {
  const HuudSignalArt(this.kind, {super.key, required this.size});
  final String kind;
  final double size;
  static const _glyphs = <String, String>{
    'shooting-star':
        '<path d="M40 9l4 10 11 1-9 8 3 11-10-6-9 6 2-11-8-8 11-1z"/><path d="M25 34L11 49M29 41L20 53" stroke="#fff1ca" stroke-width="4" stroke-linecap="round"/>',
    'planet':
        '<ellipse cx="32" cy="32" rx="14" ry="14"/><ellipse cx="32" cy="32" rx="25" ry="8" fill="none" stroke="#fff1ca" stroke-width="5" transform="rotate(-25 32 32)"/>',
    'galaxy':
        '<path d="M45 25c-10-15-31-5-26 10 4 13 26 11 27-2 1-10-13-15-18-7-4 6 5 12 8 6" fill="none" stroke="#fff1ca" stroke-width="5" stroke-linecap="round"/><circle cx="14" cy="16" r="3"/><circle cx="49" cy="48" r="3"/>',
    'comet':
        '<path d="M13 13l25 13-13 12z"/><path d="M25 12l20 19M12 26l19 20" fill="none" stroke="#fff1ca" stroke-width="4" stroke-linecap="round"/><circle cx="41" cy="42" r="12"/>',
    'new-moon':
        '<circle cx="32" cy="32" r="19" fill="#713409" stroke="#fff1ca" stroke-width="3"/>',
    'waxing-crescent':
        '<circle cx="32" cy="32" r="20"/><circle cx="23" cy="28" r="19" fill="#713409"/>',
    'first-quarter':
        '<circle cx="32" cy="32" r="20" fill="#713409"/><path d="M32 12a20 20 0 0 1 0 40z"/>',
    'waxing-gibbous':
        '<circle cx="32" cy="32" r="20"/><path d="M32 12a20 20 0 0 0 0 40c-15-9-15-31 0-40" fill="#713409"/>',
    'full-moon':
        '<circle cx="32" cy="32" r="20"/><circle cx="23" cy="23" r="4" fill="#f8c564"/><circle cx="39" cy="35" r="6" fill="#f8c564"/>',
    'waning-crescent':
        '<circle cx="32" cy="32" r="20"/><circle cx="41" cy="28" r="19" fill="#713409"/>',
    'dark-face':
        '<circle cx="32" cy="32" r="20" fill="#713409"/><circle cx="25" cy="29" r="3"/><circle cx="39" cy="29" r="3"/><path d="M23 39q9 7 18 0" fill="none" stroke="#fff1ca" stroke-width="3"/>',
    'light-face':
        '<circle cx="32" cy="32" r="20"/><circle cx="25" cy="29" r="3" fill="#713409"/><circle cx="39" cy="29" r="3" fill="#713409"/><path d="M23 39q9 7 18 0" fill="none" stroke="#713409" stroke-width="3"/>',
    'crystal':
        '<circle cx="32" cy="27" r="17"/><path d="M19 46h26l4 8H15z" fill="#713409"/><path d="M32 15v23M21 27h22" stroke="#f8c564" stroke-width="4"/>',
    'talisman':
        '<path d="M9 32q23-29 46 0-23 29-46 0z"/><circle cx="32" cy="32" r="12" fill="#713409"/><circle cx="32" cy="32" r="6" fill="#f8c564"/>',
    'candle':
        '<path d="M25 27h15v27H25z"/><path d="M32 9q-13 15 0 17 13-4 0-17z"/><path d="M19 54h28" stroke="#713409" stroke-width="4" stroke-linecap="round"/>',
    'mirror':
        '<ellipse cx="32" cy="25" rx="16" ry="20" fill="none" stroke="#fff1ca" stroke-width="5"/><path d="M28 46h8v12h-8z"/><path d="M23 18l10-6M27 25l13-9" stroke="#fff1ca" stroke-width="3"/>',
    'wand':
        '<path d="M14 52l29-30" stroke="#fff1ca" stroke-width="7" stroke-linecap="round"/><path d="M43 7l3 9 10 3-10 3-3 9-3-9-10-3 10-3z"/><circle cx="18" cy="16" r="3"/><circle cx="49" cy="43" r="3"/>',
    'portal':
        '<ellipse cx="32" cy="34" rx="22" ry="15"/><ellipse cx="32" cy="34" rx="15" ry="9" fill="#713409"/><ellipse cx="32" cy="34" rx="7" ry="4" fill="#f8c564"/>',
    'ufo':
        '<path d="M20 29q0-24 24 0z"/><ellipse cx="32" cy="34" rx="24" ry="10"/><path d="M22 45l-6 10M32 46v11M42 45l6 10" stroke="#fff1ca" stroke-width="3" stroke-linecap="round"/>',
    'stone':
        '<path d="M20 9h25l4 43H16z"/><path d="M24 23h17M33 23v14h8M23 44h17" fill="none" stroke="#713409" stroke-width="5"/><path d="M20 52h29v6H20z"/>',
    'dna':
        '<path d="M18 8c32 12-4 36 28 48M46 8C14 20 50 44 18 56" fill="none" stroke="#fff1ca" stroke-width="5" stroke-linecap="round"/><path d="M23 15h18M26 26h12M26 38h12M23 49h18" stroke="#fff1ca" stroke-width="3"/>',
    'spiral':
        '<path d="M52 32c0-26-40-26-40 0 0 22 34 22 34 0 0-15-24-15-24 0 0 8 13 8 13 0" fill="none" stroke="#fff1ca" stroke-width="5" stroke-linecap="round"/>',
    'flask':
        '<path d="M23 9h18M28 10v20L14 50q-3 6 5 6h26q8 0 5-6L36 30V10" fill="none" stroke="#fff1ca" stroke-width="5" stroke-linecap="round"/><path d="M22 43h20l6 10H16z"/>',
    'gem':
        '<path d="M18 13h28l12 15-26 30L6 28z"/><path d="M6 28h52M18 13l14 45 14-45M18 13l14 15 14-15" fill="none" stroke="#c66a09" stroke-width="3"/>',
    'puzzle':
        '<path d="M13 15h13a7 7 0 1 1 12 0h13v13a7 7 0 1 0 0 12v12H38a7 7 0 1 0-12 0H13V40a7 7 0 1 1 0-12z"/>',
  };
  @override
  Widget build(BuildContext context) {
    final glyph = _glyphs[kind] ?? _glyphs['gem']!;
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
      '<defs><linearGradient id="g" x2=".7" y2="1"><stop stop-color="#ffd16c"/>'
      '<stop offset=".5" stop-color="#ff941b"/><stop offset="1" stop-color="#d95c00"/></linearGradient></defs>'
      '<rect x="1" y="2" width="62" height="60" rx="16" fill="#713409"/>'
      '<rect x="2" y="1" width="60" height="58" rx="15" fill="url(#g)"/>'
      '<g fill="#fff1ca" transform="translate(4 4) scale(.875)">$glyph</g></svg>',
      width: size,
      height: size,
      excludeFromSemantics: true,
    );
  }
}
