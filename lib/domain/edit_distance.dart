/// 编辑距离（Levenshtein）：用于拼写纠错容错
library;

int editDistance(String a, String b) {
  final s = a.toLowerCase();
  final t = b.toLowerCase();
  if (s == t) return 0;
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;

  var prev = List<int>.generate(t.length + 1, (i) => i);
  var cur = List<int>.filled(t.length + 1, 0);

  for (var i = 1; i <= s.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= t.length; j++) {
      final cost = s.codeUnitAt(i - 1) == t.codeUnitAt(j - 1) ? 0 : 1;
      final del = prev[j] + 1;
      final ins = cur[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    final tmp = prev;
    prev = cur;
    cur = tmp;
  }
  return prev[t.length];
}

enum SpellVerdict {
  /// 完全正确
  correct,

  /// 编辑距离 1，视为笔误，半对
  nearMiss,

  /// 错误
  wrong;

  static SpellVerdict of(String input, String answer) {
    final d = editDistance(input.trim(), answer.trim());
    if (d == 0) return correct;
    if (d <= 1) return nearMiss;
    return wrong;
  }
}
