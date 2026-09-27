import 'package:flutter/material.dart';

const whotShapes = {
  'circle': '●',
  'triangle': '▲',
  'cross': '✚',
  'square': '■',
  'star': '★',
  'whot': 'W',
};

/// A card is identified by its wire code, not its position in the hand.
/// Multiple decks may contain the same code.
class WhotCardView extends StatelessWidget {
  const WhotCardView(
      {super.key,
      this.code,
      this.selected = false,
      this.enabled = true,
      this.compact = false,
      this.showDetails = true,
      this.scale = 1,
      this.onTap});
  final String? code;
  final bool selected, enabled, compact, showDetails;
  final double scale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final parts = code?.split('-');
    final shape = parts?.first;
    final number = parts?.last;
    final width = (compact ? 62.0 : 88.0) * scale;
    final height = (compact ? 88.0 : 124.0) * scale;
    return Semantics(
      label: code == null ? 'Market deck' : '$shape $number',
      button: onTap != null,
      selected: selected,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14 * scale),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: width,
          height: height,
          padding: EdgeInsets.all((compact ? 6 : 9) * scale),
          decoration: BoxDecoration(
            color: code == null
                ? const Color(0xff81293c)
                : const Color(0xfffff3dc),
            borderRadius: BorderRadius.circular(14 * scale),
            border: Border.all(
                color: selected
                    ? const Color(0xffeebd64)
                    : const Color(0xff4d2527),
                width: selected ? 4 : 2),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x55000000), offset: Offset(0, 4), blurRadius: 5)
            ],
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: DefaultTextStyle(
              style: const TextStyle(
                  color: Color(0xff81293c), fontWeight: FontWeight.w900),
              child: code == null
                  ? const Center(
                      child: RotatedBox(
                          quarterTurns: 3,
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('WHOT',
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                      color: Color(0xffffe6b2),
                                      fontSize: 23,
                                      letterSpacing: 2)))))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Text(number!,
                              style: TextStyle(
                                  fontSize: (compact ? 12 : 17) * scale)),
                          Expanded(
                              child: Center(
                                  child: Text(whotShapes[shape] ?? '?',
                                      style: TextStyle(
                                          fontSize:
                                              (compact ? 24 : 36) * scale)))),
                          if (showDetails)
                            Align(
                                alignment: Alignment.bottomRight,
                                child: Text(number,
                                    style: TextStyle(
                                        fontSize:
                                            (compact ? 12 : 17) * scale))),
                        ]),
            ),
          ),
        ),
      ),
    );
  }
}

bool whotCanPlay(String code, Map<String, dynamic> state) {
  final parts = code.split('-');
  final rules = state['rules'] as Map? ?? {};
  if ((state['pendingPick'] as int? ?? 0) > 0) {
    return parts.last == '2' &&
        rules['pickTwo'] == true &&
        rules['pickTwoStacking'] == true;
  }
  final top = state['topCard'] as String? ?? '';
  return parts.first == 'whot' ||
      parts.first == state['activeShape'] ||
      parts.last == top.split('-').last;
}
