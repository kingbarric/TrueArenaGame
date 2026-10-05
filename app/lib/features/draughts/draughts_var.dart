/// A public, completed Draft turn. The board is copied before its first step.
class DraughtsVarTurn {
  const DraughtsVarTurn({
    required this.side,
    required this.before,
    required this.steps,
  });

  final String side;
  final List<String?> before;
  final List<DraughtsVarStep> steps;
}

class DraughtsVarStep {
  const DraughtsVarStep({
    required this.from,
    required this.to,
    this.captured,
    this.promoted = false,
  });

  final int from;
  final int to;
  final int? captured;
  final bool promoted;

  DraughtsVarStep withPromotion() => DraughtsVarStep(
        from: from,
        to: to,
        captured: captured,
        promoted: true,
      );
}

/// Groups the engine's per-jump events into the complete turn they belong to.
class DraughtsVarRecorder {
  DraughtsVarTurn? lastCompleted;
  List<String?>? _before;
  String? _side;
  final List<DraughtsVarStep> _steps = [];

  void reset() {
    _before = null;
    _side = null;
    _steps.clear();
    lastCompleted = null;
  }

  void move(List<String?> boardBeforeEvent, String side, int from, int to,
      {int? captured}) {
    if (_before == null || _side != side) {
      _before = List<String?>.of(boardBeforeEvent);
      _side = side;
      _steps.clear();
    }
    _steps.add(DraughtsVarStep(from: from, to: to, captured: captured));
  }

  void promote(int square) {
    if (_steps.isEmpty || _steps.last.to != square) return;
    _steps[_steps.length - 1] = _steps.last.withPromotion();
  }

  void complete() {
    if (_before != null && _side != null && _steps.isNotEmpty) {
      lastCompleted = DraughtsVarTurn(
        side: _side!,
        before: List<String?>.unmodifiable(_before!),
        steps: List<DraughtsVarStep>.unmodifiable(_steps),
      );
    }
    _before = null;
    _side = null;
    _steps.clear();
  }
}
