/// Fuzzy string matching for Word Bluff's voice auto-detect — deliberately not
/// exact: "gerraffe" or "a giraffe" should both still lock in "giraffe". Pure
/// Dart, no platform dependency, so it's trivially unit-testable on its own.
library;

/// Levenshtein edit distance between [a] and [b].
int _editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  List<int> prev = List<int>.generate(b.length + 1, (j) => j);
  List<int> curr = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      curr[j] = [
        curr[j - 1] + 1, // insertion
        prev[j] + 1, // deletion
        prev[j - 1] + cost, // substitution
      ].reduce((x, y) => x < y ? x : y);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

/// 1.0 = identical, 0.0 = completely different. Normalized by the longer
/// string's length so "cat" vs "cats" (1 edit / 4 chars) scores 0.75, not 0.
double similarity(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  final maxLen = a.length > b.length ? a.length : b.length;
  if (maxLen == 0) return 1;
  return 1 - (_editDistance(a, b) / maxLen);
}

String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9' ]"), ' ').trim();

/// True if any single word (or short run of adjacent words, for a multi-word
/// target like "polar bear") inside [heard] is close enough to [target] to
/// count as a match at [threshold] (0.0-1.0; higher = stricter/closer to
/// exact). Checked word-by-word rather than as one long string so a target
/// buried in a whole sentence of description still matches.
bool isCloseMatch(String heard, String target, double threshold) {
  final normTarget = _normalize(target);
  if (normTarget.isEmpty) return false;
  final targetWords = normTarget.split(' ').where((w) => w.isNotEmpty).toList();
  if (targetWords.isEmpty) return false;

  final words = _normalize(heard).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return false;

  // A single word close to the whole target (a one-word target), or to any
  // one of the target's own words (a guesser saying just the head noun of a
  // multi-word target, e.g. "bear" for "polar bear").
  for (final w in words) {
    if (similarity(w, normTarget) >= threshold) return true;
    for (final targetWord in targetWords) {
      if (similarity(w, targetWord) >= threshold) return true;
    }
  }
  // A sliding window of every adjacent word-run the same length as the
  // target, for a multi-word target said in full ("polar bear").
  if (targetWords.length > 1) {
    for (var i = 0; i + targetWords.length <= words.length; i++) {
      final window = words.sublist(i, i + targetWords.length).join(' ');
      if (similarity(window, normTarget) >= threshold) return true;
    }
  }
  return false;
}
