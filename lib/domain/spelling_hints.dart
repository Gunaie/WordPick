/// 看义拼写的分级提示生成（纯函数，便于单测）
///
/// 三级递进：首字母 → 音节数 → 词根拆解。
library;

import 'affix.dart';

/// 首字母 + 下划线占位，揭示词长。
///
/// 例：`predict` → `p _ _ _ _ _ _`
String firstLetterHint(String word) {
  final w = word.trim();
  if (w.isEmpty) return '';
  if (w.length == 1) return w;
  final rest = List<String>.filled(w.length - 1, '_').join(' ');
  return '${w[0]} $rest';
}

/// 音节数（元音组启发式，近似值，仅作提示）。
///
/// 统计连续元音（a e i o u y）的组数；对词尾不发音的 e 做修正，
/// `-le` 前是辅音时保留为一个音节。至少返回 1。
/// 例：`predict` → 2，`beautiful` → 3，`make` → 1，`apple` → 2。
int syllableCount(String word) {
  final w = word.toLowerCase().trim();
  if (w.isEmpty) return 0;
  var count = 0;
  var inVowel = false;
  for (final c in w.codeUnits) {
    final isVowel = 'aeiouy'.contains(String.fromCharCode(c));
    if (isVowel && !inVowel) count++;
    inVowel = isVowel;
  }
  // 词尾哑音 e：以 e 结尾且 e 自成一个元音组时减 1；
  // 但 -le 前是辅音（音节性 l）时不减，如 apple / table。
  if (w.length > 2 && w.endsWith('e') && count > 1) {
    final prev = w[w.length - 2];
    final prev2 = w.length > 3 ? w[w.length - 3] : '';
    final isSyllabicLE =
        prev == 'l' && prev2.isNotEmpty && !'aeiouy'.contains(prev2);
    if (!isSyllabicLE && !'aeiouy'.contains(prev)) {
      count--;
    }
  }
  return count < 1 ? 1 : count;
}

/// 词根拆解提示：命中的词缀段按顺序用 ` + ` 连接。
///
/// 例：`predict` → `pre- + dict`；无拆解返回空串。
String affixBreakdownHint(
  String word,
  List<Affix> affixes, {
  bool Function(String)? isKnownWord,
}) {
  final matches = analyzeWord(word, affixes, isKnownWord: isKnownWord);
  if (matches.isEmpty) return '';
  return matches.map((m) => m.segment).join(' + ');
}
