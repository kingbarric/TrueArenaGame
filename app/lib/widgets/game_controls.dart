import 'package:flutter/material.dart';

/// One button in a game's control row.
class GameControl {
  const GameControl({required this.id, required this.icon, required this.label, this.onTap, this.lit = false});

  /// Stable name for tests and keys: `undo`, `draw`, `var`, `rules`, `resign`.
  final String id;
  final IconData icon;
  final String label;

  /// Null greys the button out.
  final VoidCallback? onTap;

  /// Something waiting on you (e.g. a draw offered to you).
  final bool lit;
}

/// The same row of controls under every board — Draughts, Chess and Ludo:
/// Undo · Draw · VAR · Rules · Resign, in that order, with the same look.
/// A game leaves out what it doesn't have (Ludo has no draws).
class GameControlBar extends StatelessWidget {
  const GameControlBar({super.key, required this.controls});

  final List<GameControl> controls;

  static const _tile = Color(0xcc1a1008);
  static const _gold = Color(0xffe0a94a);
  static const _cream = Color(0xfff0d8a8);

  /// The standard set, in the standard order.
  static List<GameControl> standard({
    required VoidCallback? onUndo,
    String undoLabel = 'Undo',
    VoidCallback? onDraw,
    String drawLabel = 'Draw',
    bool drawLit = false,
    bool hasDraw = true,
    required VoidCallback? onVar,
    required VoidCallback onRules,
    required VoidCallback? onResign,
  }) =>
      [
        GameControl(id: 'undo', icon: Icons.undo_rounded, label: undoLabel, onTap: onUndo),
        if (hasDraw)
          GameControl(id: 'draw', icon: Icons.handshake_rounded, label: drawLabel, onTap: onDraw, lit: drawLit),
        GameControl(id: 'var', icon: Icons.live_tv_rounded, label: 'VAR', onTap: onVar),
        GameControl(id: 'rules', icon: Icons.help_outline_rounded, label: 'Rules', onTap: onRules),
        GameControl(id: 'resign', icon: Icons.flag_rounded, label: 'Resign', onTap: onResign),
      ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Row(children: [
        for (var i = 0; i < controls.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(child: _button(controls[i])),
        ],
      ]),
    );
  }

  Widget _button(GameControl c) {
    final enabled = c.onTap != null;
    final fg = !enabled ? _cream.withValues(alpha: 0.35) : (c.lit ? const Color(0xff241708) : _gold);
    return Material(
      key: ValueKey('game-control-${c.id}'),
      color: c.lit ? const Color(0xffffc233) : _tile,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: c.onTap,
        child: SizedBox(
          height: 50,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(c.icon, size: 19, color: fg),
            const SizedBox(height: 3),
            Text(c.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.lit ? const Color(0xff241708) : (enabled ? _cream : _cream.withValues(alpha: 0.35)),
                    fontSize: 10,
                    fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}

/// "eric wants to undo their move" — Allow / No, the same box in every game.
class UndoAskBanner extends StatelessWidget {
  const UndoAskBanner({super.key, required this.who, required this.onAnswer});

  final String who;
  final void Function(bool allow) onAnswer;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('undo-ask'),
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xffffc233),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: const Color(0xffffc233).withValues(alpha: 0.45), blurRadius: 12)],
      ),
      child: Row(children: [
        const Icon(Icons.undo_rounded, color: Color(0xff241708)),
        const SizedBox(width: 10),
        Expanded(
          child: Text('$who wants to undo their move',
              style: const TextStyle(color: Color(0xff241708), fontWeight: FontWeight.w900, fontSize: 15)),
        ),
        TextButton(
          key: const ValueKey('undo-no'),
          onPressed: () => onAnswer(false),
          child: const Text('No', style: TextStyle(color: Color(0xff241708), fontWeight: FontWeight.w800)),
        ),
        FilledButton(
          key: const ValueKey('undo-yes'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xff241708)),
          onPressed: () => onAnswer(true),
          child: const Text('Allow', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }
}
