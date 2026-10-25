import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/features/draughts/draughts_var.dart';

void main() {
  test('VAR keeps a seizure as the first step of the turn that made it', () {
    final board = List<String?>.filled(50, null)
      ..[21] = 'A_MAN'
      ..[30] = 'B_MAN';
    final recorder = DraughtsVarRecorder()
      ..seize(board, 'B', 21)
      ..move(List<String?>.of(board)..[21] = null, 'B', 30, 25)
      ..complete();

    final turn = recorder.lastCompleted!;
    expect(turn.side, 'B');
    expect(turn.before[21], 'A_MAN'); // the replay starts with the seized piece still there
    expect(turn.steps.first.seized, isTrue);
    expect(turn.steps.first.captured, 21);
    expect(turn.steps.last.seized, isFalse);
    expect(turn.steps.last.to, 25);
  });
}
