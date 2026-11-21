/// 看义拼写的分级提示生成（纯函数，便于单测）
///
/// 递进提示：首字母 → 音节数 → 词根拆解 → 四选一。
library;

import 'dart:math';

import 'affix.dart';
import 'word.dart';

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

/// 音节数；优先与 [splitSyllables] 共用同一套切分，切分不确定时回退启发式。
///
/// 例：`predict` → 2，`beautiful` → 3，`make` → 1，`apple` → 2。
int syllableCount(String word) {
  final parts = splitSyllables(word);
  if (parts != null && parts.isNotEmpty) return parts.length;

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

/// 按音节切分单词，返回各音节（保持原大小写）；无法可靠切分时返回 null。
///
/// 规则：元音组 + 常见辅音丛归属 + 常见后缀（-tion / -ture 等），
/// 并用少量例外表兜底。宁可返回 null 由调用方隐藏，也不展示明显错误的分节。
/// 例：`resilient` → `re·sil·ient`，`inspection` → `in·spec·tion`。
List<String>? splitSyllables(String word) {
  final raw = word.trim();
  if (raw.isEmpty) return const [];
  final w = raw.toLowerCase();
  if (!RegExp(r'^[a-z]+$').hasMatch(w)) return null;
  if (w.length <= 2) return [raw];

  final exception = _syllableExceptions[w];
  if (exception != null) return _applyCase(raw, exception);

  // 常见后缀整体作为一个音节，避免 tion 被拆成 ti·on
  String? suffix;
  for (final s in _atomicSuffixes) {
    if (w.endsWith(s) && w.length - s.length >= 2) {
      suffix = s;
      break;
    }
  }
  final stem = suffix == null ? w : w.substring(0, w.length - suffix.length);

  final nuclei = _nuclei(stem);
  if (nuclei == null) return null;

  final parts = <String>[];
  var start = 0;
  for (var i = 0; i < nuclei.length - 1; i++) {
    final clusterStart = nuclei[i].end;
    final clusterEnd = nuclei[i + 1].start;
    final cluster = stem.substring(clusterStart, clusterEnd);
    final boundary = clusterStart + _onsetOffset(cluster);
    parts.add(stem.substring(start, boundary));
    start = boundary;
  }
  parts.add(stem.substring(start));
  if (suffix != null) parts.add(suffix);

  return _applyCase(raw, parts);
}

const Set<String> _vowelChars = {'a', 'e', 'i', 'o', 'u', 'y'};

/// 允许作为一个音节的连续元音组合；不在表内的组合视为不确定，不切分
const Set<String> _allowedVowelGroups = {
  'ai', 'ay', 'ea', 'ee', 'ei', 'ey', 'ie', 'oa', 'oe', 'oi', 'oo', 'ou',
  'ow', 'oy', 'ue', 'ui', 'au', 'aw', 'eu', 'ew', 'eau', 'ieu', 'iew',
};

/// 常见后缀：本身通常只占一个音节
const List<String> _atomicSuffixes = [
  'tion', 'sion', 'cian', 'tial', 'cial', 'cious', 'tious', 'geous', 'gious',
  'cient', 'ient', 'ture', 'sure',
];

/// 可作为音节开头的辅音（单字母 + 常见辅音丛）
const Set<String> _onsets = {
  'b', 'c', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'm', 'n', 'p', 'q', 'r',
  's', 't', 'v', 'w', 'y', 'z',
  'bl', 'br', 'ch', 'cl', 'cr', 'dr', 'dw', 'fl', 'fr', 'gl', 'gr', 'gu',
  'kn', 'ph', 'pl', 'pr', 'qu', 'sc', 'sh', 'sk', 'sl', 'sm', 'sn', 'sp',
  'st', 'sw', 'th', 'tr', 'tw', 'wh', 'wr', 'sq',
  'chr', 'phl', 'phr', 'sch', 'scr', 'shr', 'spl', 'spr', 'squ', 'str',
  'thr',
};

/// 少量不规则词，规则无法可靠切分时直接给出结果
const Map<String, List<String>> _syllableExceptions = {
  'business': ['busi', 'ness'],
  'colonel': ['colo', 'nel'],
  'comfortable': ['com', 'fort', 'a', 'ble'],
  'vegetable': ['veg', 'e', 'ta', 'ble'],
  'chocolate': ['choc', 'o', 'late'],
  'interesting': ['in', 'ter', 'est', 'ing'],
  'every': ['ev', 'ery'],
  'evening': ['eve', 'ning'],
  'favorite': ['fa', 'vor', 'ite'],
  'favourite': ['fa', 'vour', 'ite'],
  'temperature': ['tem', 'per', 'a', 'ture'],
  'wednesday': ['wednes', 'day'],
  'careless': ['care', 'less'],
  'different': ['dif', 'fer', 'ent'],
  'family': ['fam', 'i', 'ly'],
  'library': ['li', 'brar', 'y'],
  'available': ['avail', 'able'],
  'singer': ['sing', 'er'],
  'people': ['peo', 'ple'],
  'science': ['sci', 'ence'],
  'quiet': ['qui', 'et'],
  'diet': ['di', 'et'],
  'poem': ['po', 'em'],
  'create': ['cre', 'ate'],
  'react': ['re', 'act'],
  'real': ['re', 'al'],
  'idea': ['i', 'de', 'a'],
  'area': ['ar', 'ea'],
  'video': ['vid', 'e', 'o'],
  'theory': ['the', 'o', 'ry'],
  'previous': ['pre', 'vi', 'ous'],
  'ubiquitous': ['u', 'biq', 'ui', 'tous'],
  'museum': ['mu', 'se', 'um'],
  'nuclear': ['nu', 'cle', 'ar'],
  'theater': ['the', 'a', 'ter'],
  'theatre': ['the', 'a', 'tre'],
  'cereal': ['ce', 're', 'al'],
};

class _Nucleus {
  final int start;
  final int end;

  const _Nucleus(this.start, this.end);
}

/// 提取元音核；返回 null 表示存在无法可靠判断的组合
List<_Nucleus>? _nuclei(String w) {
  final groups = <_Nucleus>[];
  var i = 0;
  while (i < w.length) {
    if (!_vowelChars.contains(w[i])) {
      i++;
      continue;
    }
    final start = i;
    while (i < w.length && _vowelChars.contains(w[i])) {
      i++;
    }
    groups.add(_Nucleus(start, i));
  }
  if (groups.isEmpty) return null;

  // qu 中的 u 属于辅音丛，不计入音节核
  final adjusted = <_Nucleus>[];
  for (final g in groups) {
    var start = g.start;
    if (start > 0 &&
        w[start - 1] == 'q' &&
        w[start] == 'u' &&
        g.end - start > 1) {
      start++;
    }
    if (start < g.end) adjusted.add(_Nucleus(start, g.end));
  }
  if (adjusted.isEmpty) return null;

  // 词尾哑音 e：-le 前是辅音时保留（apple / table），否则并入前一音节
  if (w.endsWith('e') && adjusted.length > 1) {
    final last = adjusted.last;
    if (last.start == w.length - 1) {
      final prev = w[w.length - 2];
      final syllabicLE = prev == 'l' &&
          w.length >= 3 &&
          !_vowelChars.contains(w[w.length - 3]);
      if (!syllabicLE && !_vowelChars.contains(prev)) {
        adjusted.removeLast();
      }
    }
  }
  if (adjusted.isEmpty) return null;

  // 未识别的连续元音组合可能是分属两个音节，无法确定时不展示
  for (final g in adjusted) {
    final text = w.substring(g.start, g.end);
    if (text.length >= 2 && !_allowedVowelGroups.contains(text)) return null;
  }

  // 单个元音组却含 3 个以上元音字母，通常是 hiatus，规则不可靠
  final vowelLetters = w.split('').where(_vowelChars.contains).length;
  if (adjusted.length == 1 && vowelLetters >= 3) return null;

  return adjusted;
}

/// 计算辅音丛的切分点：返回留给前一个音节的字母数
int _onsetOffset(String cluster) {
  if (cluster.isEmpty) return 0;

  // x 通常留在前一音节：ex·act / box·er
  if (cluster.contains('x')) return cluster.indexOf('x') + 1;
  // ck 作为前一音节的结尾：pock·et
  if (cluster.endsWith('ck')) return cluster.length - 2;
  // nk 通常整体留在前一音节：think·er
  if (cluster.endsWith('nk')) return cluster.length;

  for (var len = min(3, cluster.length); len >= 1; len--) {
    final onset = cluster.substring(cluster.length - len);
    if (_onsets.contains(onset)) return cluster.length - len;
  }
  return cluster.length - 1;
}

List<String> _applyCase(String raw, List<String> parts) {
  var offset = 0;
  final out = <String>[];
  for (final part in parts) {
    final end = offset + part.length;
    if (end > raw.length) return parts;
    out.add(raw.substring(offset, end));
    offset = end;
  }
  return offset == raw.length ? out : parts;
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

/// 四选一提示：正确拼写 + 3 个干扰项；词池不足 4 个不同拼写时返回 null。
///
/// 干扰项优先取同首字母的词，其次取长度接近的词，让选项更有区分难度。
/// 例：`resilient` → `[resilient, rely, reject, ...]`（顺序随机）。
List<String>? buildSpellingChoices(
  Word word,
  List<Word> pool, {
  Random? random,
}) {
  final correct = word.w.trim();
  if (correct.isEmpty) return null;

  final r = random ?? Random();
  final seen = <String>{correct.toLowerCase()};
  final sameStart = <String>[];
  final similarLength = <String>[];
  final others = <String>[];

  for (final w in pool) {
    final s = w.w.trim();
    if (s.isEmpty || !seen.add(s.toLowerCase())) continue;
    if (s[0].toLowerCase() == correct[0].toLowerCase()) {
      sameStart.add(s);
    } else if ((s.length - correct.length).abs() <= 2) {
      similarLength.add(s);
    } else {
      others.add(s);
    }
  }

  sameStart.shuffle(r);
  similarLength.shuffle(r);
  others.shuffle(r);

  final picked = <String>[];
  for (final s in [...sameStart, ...similarLength, ...others]) {
    picked.add(s);
    if (picked.length == 3) break;
  }
  if (picked.length < 3) return null;

  return ([correct, ...picked]..shuffle(r));
}
