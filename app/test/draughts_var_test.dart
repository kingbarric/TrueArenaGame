import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/features/draughts/draughts_var.dart';

void main() {
  test('VAR keeps a complete multi-capture turn and its original board', () {
    final recorder = DraughtsVarRecorder();
    final board = List<String?>.filled(50, null);
    board[10] = 'A_MAN';
    board[16] = 'B_MAN';
    board[27] = 'B_MAN';

    recorder.move(board, 'A', 10, 21, captured: 16);
    board[10] = null;
    board[16] = null;
    board[21] = 'A_MAN';
    recorder.move(board, 'A', 21, 32, captured: 27);
    recorder.promote(32);
    recorder.complete();

    final turn = recorder.lastCompleted!;
    expect(turn.side, 'A');
    expect(turn.before[10], 'A_MAN');
    expect(turn.before[16], 'B_MAN');
    expect(turn.before[27], 'B_MAN');
    expect(turn.steps, hasLength(2));
    expect(turn.steps[0].captured, 16);
    expect(turn.steps[1].captured, 27);
    expect(turn.steps[1].promoted, isTrue);
    expect(board[10], isNull);
  });

  test('a snapshot discards an incomplete turn', () {
    final recorder = DraughtsVarRecorder();
    recorder.move(List<String?>.filled(50, null), 'B', 30, 19,
        captured: 24);
    recorder.reset();
    recorder.complete();
    expect(recorder.lastCompleted, isNull);
  });
}
