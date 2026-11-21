/// 易混词队列（纯函数，可注入 Random 做确定性测试）
///
/// 方案 A（软绑定）：当某个组成员出现在本轮队列时，把同组其他词紧接插入其后，
/// 提前复习并按实际作答正常计分。约束：
/// - 组大小 2–4；同组在一个词首次出现时只触发一次，不链式扩散；
/// - 已在队列中的词不重复插入；
/// - 关联插入占用本轮上限，超出时从队列尾部裁掉（优先挤占新词）；
/// - 组内顺序每轮随机，避免记住位置。
library;

import 'dart:math';

import 'confusable_group.dart';
import 'word.dart';

/// 组队结果：单词队列 + 每个「关联复习」词的组名
class ConfusableRound {
  final List<Word> words;

  /// 单词 key -> 组名，仅包含被关联插入的词
  final Map<String, String> companions;

  const ConfusableRound({
    required this.words,
    this.companions = const {},
  });
}

/// 在到期词 + 新词的基础上插入易混组同伴。
///
/// [maxLength] 为本轮上限（默认等于基础队列长度，不会额外变长）；
/// 传入 `dueLimit + newLimit` 可让关联词填补基础队列不足的空位。
ConfusableRound buildConfusableRound({
  required List<Word> dueWords,
  required List<Word> freshWords,
  required List<ConfusableGroup> groups,
  required Map<String, Word> poolByKey,
  int? maxLength,
  Random? random,
}) {
  final rng = random ?? Random();
  final base = [...dueWords, ...freshWords];
  final capacity = maxLength ?? base.length;
  if (base.isEmpty || groups.isEmpty) {
    return ConfusableRound(words: base);
  }

  final queueKeys = {for (final w in base) w.key};
  final usedGroups = <String>{};
  final insertions = <int, List<({Word word, String group})>>{};
  final companionNames = <String, String>{};

  for (var i = 0; i < base.length; i++) {
    final trigger = base[i];
    final group = _firstUnusedGroup(trigger.key, groups, usedGroups);
    if (group == null) continue;
    usedGroups.add(group.id);

    final others = <Word>[];
    for (final key in group.wordKeys) {
      if (key == trigger.key) continue;
      final word = poolByKey[key];
      if (word == null || !queueKeys.add(word.key)) continue;
      others.add(word);
    }
    if (others.isEmpty) continue;

    // 组内顺序每轮随机
    others.shuffle(rng);
    insertions[i] = [
      for (final w in others) (word: w, group: group.displayName),
    ];
    for (final w in others) {
      companionNames[w.key] = group.displayName;
    }
  }

  final result = <Word>[];
  for (var i = 0; i < base.length; i++) {
    result.add(base[i]);
    final extra = insertions[i];
    if (extra == null) continue;
    for (final e in extra) {
      if (result.length < capacity) result.add(e.word);
    }
  }

  // 超限时从尾部裁掉（新词在尾部，自然被挤占）
  while (result.length > capacity) {
    result.removeLast();
  }

  final present = {for (final w in result) w.key};
  final companions = {
    for (final e in companionNames.entries)
      if (present.contains(e.key)) e.key: e.value,
  };
  return ConfusableRound(words: result, companions: companions);
}

ConfusableGroup? _firstUnusedGroup(
  String key,
  List<ConfusableGroup> groups,
  Set<String> used,
) {
  for (final g in groups) {
    if (g.wordKeys.length < 2) continue;
    if (used.contains(g.id)) continue;
    if (g.wordKeys.contains(key)) return g;
  }
  return null;
}
