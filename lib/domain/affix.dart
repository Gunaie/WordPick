/// 词根词缀模型与拆解算法（纯 Dart，便于单测）
library;

enum AffixType { prefix, root, suffix }

extension AffixTypeLabel on AffixType {
  String get label => switch (this) {
        AffixType.prefix => '前缀',
        AffixType.root => '词根',
        AffixType.suffix => '后缀',
      };
}

class Affix {
  final AffixType type;

  /// 展示形式，可能是多个变体，如 `in-/im-/il-/ir-`
  final String form;
  final String meaning;
  final List<String> examples;

  const Affix({
    required this.type,
    required this.form,
    required this.meaning,
    this.examples = const [],
  });

  /// 拆出所有变体，去掉连字符
  List<String> get variants => form
      .split('/')
      .map((e) => e.replaceAll('-', '').trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toList();

  factory Affix.fromJson(Map<String, dynamic> j) => Affix(
        type: switch ((j['type'] ?? '') as String) {
          'prefix' => AffixType.prefix,
          'suffix' => AffixType.suffix,
          _ => AffixType.root,
        },
        form: (j['form'] ?? '') as String,
        meaning: (j['meaning'] ?? '') as String,
        examples:
            ((j['examples'] ?? const []) as List).map((e) => '$e').toList(),
      );
}

class AffixMatch {
  final Affix affix;

  /// 实际命中的那个变体
  final String matched;
  final int start;
  final int end;

  const AffixMatch({
    required this.affix,
    required this.matched,
    required this.start,
    required this.end,
  });

  String get segment => affix.type == AffixType.prefix
      ? '$matched-'
      : affix.type == AffixType.suffix
          ? '-$matched'
          : matched;
}

/// 对单词做词缀拆解
///
/// 规则保守：
///   * 词缀长度 ≥ 2，词根 ≥ 3，且剩余部分至少 3 个字母
///   * 同类型只保留最长命中
///   * **2 字母后缀**（-en / -ly / -er 等）歧义大，只有「去掉后缀后是已知单词」
///     时才展示，避免把 abdomen 误拆成 -en
///
/// [isKnownWord] 传入词典查询函数（可为空）；为空时对 2 字母后缀一律不展示。
List<AffixMatch> analyzeWord(
  String word,
  List<Affix> affixes, {
  bool Function(String)? isKnownWord,
}) {
  final w = word.toLowerCase().trim();
  if (w.length < 4) return const [];

  final out = <AffixMatch>[];

  for (final a in affixes) {
    for (final v in a.variants) {
      if (v.length < 2) continue;

      if (a.type == AffixType.prefix) {
        if (w.startsWith(v) && w.length - v.length >= 3) {
          out.add(AffixMatch(affix: a, matched: v, start: 0, end: v.length));
        }
      } else if (a.type == AffixType.suffix) {
        if (!w.endsWith(v)) continue;
        final stem = w.substring(0, w.length - v.length);
        if (stem.length < 3) continue;

        // 短后缀歧义大，必须有词典佐证词干才展示
        if (v.length == 2) {
          if (isKnownWord == null || !isKnownWord(stem)) continue;
        }

        out.add(AffixMatch(
          affix: a,
          matched: v,
          start: w.length - v.length,
          end: w.length,
        ));
      } else {
        if (v.length >= 3 && w.contains(v)) {
          final i = w.indexOf(v);
          out.add(AffixMatch(affix: a, matched: v, start: i, end: i + v.length));
        }
      }
    }
  }

  // 同类型只保留最长的命中，避免 in-/inter- 同时出现
  final best = <AffixType, AffixMatch>{};
  for (final m in out) {
    final cur = best[m.affix.type];
    if (cur == null || m.matched.length > cur.matched.length) {
      best[m.affix.type] = m;
    }
  }

  final result = best.values.toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  return result;
}
