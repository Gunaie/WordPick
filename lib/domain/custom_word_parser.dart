/// 自建词解析（纯 Dart，无 Flutter 依赖，便于单独测试）
///
/// 支持每行以下格式（可混用）：
///   word
///   word 释义                              （单个空格也可以）
///   word,释义 / word，释义 / word:释义
///   word    释义                           （多空格 / Tab）
///   1. word 释义 / (1) word 释义 / 1、word 释义
///   word [əˈbændən] 释义 / word /əˈbændən/ 释义
///   word v. 释义 / word (vt.) 释义 / word n./v. 释义
///   word n. 苹果; n. 苹果公司          （分号分隔多条释义，词性写在释义前）
library;

import 'word.dart';

final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');
final RegExp _wordPattern = RegExp(r"^[A-Za-z][A-Za-z'\- ]*$");
final RegExp _trailingSep = RegExp(r'[\s,，:：\-—–、]+$');
final RegExp _leadingMarker = RegExp(r'^\s*(?:[\(\[【]?\d+\s*[\)\]】\.、)]\s*)+');
final RegExp _bracket = RegExp(r'[\(\[【][^\)\]】]*[\)\]】]');
final RegExp _slashPhonetic = RegExp(r'/[^/]{1,40}/');
const String _posNames =
    r'(?:n|v|vt|vi|adj|adv|prep|conj|pron|art|num|int|aux|phr|abbr|pl)';
final RegExp _posRun = RegExp(
  '$_posNames\\.(?:\\s*[/、,]\\s*$_posNames\\.)*',
  caseSensitive: false,
);
final RegExp _leadingPos = RegExp(
  '^\\s*($_posNames\\.(?:\\s*[/、,]\\s*$_posNames\\.)*)\\s*',
  caseSensitive: false,
);
final RegExp _firstToken = RegExp(r"[A-Za-z][A-Za-z'\-]*");
final RegExp _leadingJunk = RegExp(r'^[\s,，:：\-—–、\)\]】]+');

/// 解析结果：新增 / 重复添加 / 无法识别。
class CustomWordParseResult {
  final List<Word> added;

  /// 已存在的自建词 key -> 本次重复出现次数（用于累加「添加次数」）
  final Map<String, int> repeated;

  final List<String> invalid;

  const CustomWordParseResult({
    this.added = const [],
    this.repeated = const {},
    this.invalid = const [],
  });
}

/// 自建词条：单词本体 + 导入元信息（添加时间 / 添加次数）
class CustomWordEntry {
  final Word word;

  /// 首次添加时间；旧版本数据没有该字段时为 null
  final DateTime? addedAt;

  /// 累计添加次数（同一词重复导入会累加）
  final int addCount;

  const CustomWordEntry({
    required this.word,
    this.addedAt,
    this.addCount = 1,
  });

  String get key => word.key;

  CustomWordEntry copyWith({
    Word? word,
    DateTime? addedAt,
    int? addCount,
  }) =>
      CustomWordEntry(
        word: word ?? this.word,
        addedAt: addedAt ?? this.addedAt,
        addCount: addCount ?? this.addCount,
      );

  factory CustomWordEntry.fromJson(Map<String, dynamic> j) => CustomWordEntry(
        word: Word.fromJson(j),
        addedAt: DateTime.tryParse('${j['added_at'] ?? ''}'),
        addCount: (j['add_count'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'w': word.w,
        'uk': word.uk,
        'us': word.us,
        'defs': word.defs
            .map((d) => {'pos': d.pos, 'cn': d.cn, 'en': d.en})
            .toList(),
        'tags': word.tags,
        if (addedAt != null) 'added_at': addedAt!.toIso8601String(),
        'add_count': addCount,
      };
}

/// 自建单词本：一本可命名的词书，内含若干自建词
class CustomWordBook {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<CustomWordEntry> words;

  const CustomWordBook({
    required this.id,
    required this.name,
    required this.createdAt,
    this.words = const [],
  });

  CustomWordBook copyWith({
    String? name,
    DateTime? createdAt,
    List<CustomWordEntry>? words,
  }) =>
      CustomWordBook(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
        words: words ?? this.words,
      );

  factory CustomWordBook.fromJson(Map<String, dynamic> j) {
    final created = DateTime.tryParse('${j['created_at'] ?? ''}') ?? DateTime.now();
    final id = '${j['id'] ?? ''}';
    final rawWords = (j['words'] as List?) ?? const [];
    return CustomWordBook(
      id: id.isEmpty ? 'book-${created.millisecondsSinceEpoch}' : id,
      name: '${j['name'] ?? '未命名单词本'}',
      createdAt: created,
      words: rawWords
          .whereType<Map<String, dynamic>>()
          .map(CustomWordEntry.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        'words': words.map((e) => e.toJson()).toList(),
      };
}

/// 解析粘贴文本，返回可新增的词条列表。
List<Word> parseCustomWords(String text) {
  return parseCustomWordsDetailed(text).added;
}

/// 解析粘贴文本，同时给出跳过原因，便于界面提示。
///
/// [repeatable] 为自建单词本里已有的词 key：再次导入不会新增词条，
/// 而是计入 [CustomWordParseResult.repeated]，由调用方累加添加次数。
CustomWordParseResult parseCustomWordsDetailed(
  String text, {
  Set<String> repeatable = const {},
}) {
  final added = <Word>[];
  final repeated = <String, int>{};
  final invalid = <String>[];
  final seen = <String>{};

  for (final line in text.split(RegExp(r'[\r\n]+'))) {
    final raw = line.trim();
    if (raw.isEmpty) continue;

    final word = parseCustomWordLine(raw);
    if (word == null) {
      invalid.add(raw);
      continue;
    }

    final key = word.key;
    if (repeatable.contains(key) || seen.contains(key)) {
      repeated[key] = (repeated[key] ?? 0) + 1;
      continue;
    }

    added.add(word);
    seen.add(key);
  }

  return CustomWordParseResult(
    added: added,
    repeated: repeated,
    invalid: invalid,
  );
}

/// 解析单行文本为词条；取不到英文单词时返回 null。
///
/// 批量导入与拍照识别候选共用这一套规则。
Word? parseCustomWordLine(String line) {
  final raw = line.trim();
  if (raw.isEmpty) return null;

  // 先按「第一个中文字符」切成 单词段 / 释义段
  final cjkMatch = _cjk.firstMatch(raw);
  String head;
  String def;
  if (cjkMatch != null) {
    head = raw.substring(0, cjkMatch.start);
    def = raw.substring(cjkMatch.start);
  } else {
    final parts = raw.split(RegExp(r'[\t,，:：;；]|\s{2,}'));
    head = parts.first;
    def = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';
  }

  final rawHead = head;
  head = _cleanHead(head);
  if (head.isEmpty) return null;

  return Word(
    w: head,
    uk: _extractPhonetic(rawHead) ?? '',
    defs: _parseSenses(def, _extractHeadPos(rawHead)),
    tags: const ['custom'],
  );
}

/// 从原始行首段提取音标：优先 /.../，其次 [..] / (..)（排除纯词性括号）
String? _extractPhonetic(String input) {
  final slash = _slashPhonetic.firstMatch(input);
  if (slash != null) {
    return slash.group(0)!.replaceAll('/', '').trim();
  }
  for (final m in _bracket.allMatches(input)) {
    final inside =
        m.group(0)!.substring(1, m.group(0)!.length - 1).trim();
    if (inside.isEmpty || _cjk.hasMatch(inside)) continue;
    if (RegExp(r'^\d+$').hasMatch(inside)) continue; // 序号 (1)
    final pos = _leadingPos.firstMatch(inside);
    if (pos != null && pos.end == inside.length) continue;
    return inside;
  }
  return null;
}

/// 词头里出现的词性（如 `n.`、`adj./adv.`），用于第一条释义
List<String> _extractHeadPos(String input) {
  final out = <String>[];
  for (final m in _posRun.allMatches(input)) {
    final pos = m.group(0)!.replaceAll(RegExp(r'\s+'), '');
    if (!out.contains(pos)) out.add(pos);
  }
  return out;
}

/// 按分号拆分多条释义，并提取每条前面的词性
List<WordSense> _parseSenses(String def, List<String> headPos) {
  final text = def
      .replaceFirst(_leadingMarker, '')
      .replaceFirst(_leadingJunk, '')
      .trim();
  if (text.isEmpty) return const [];

  final senses = <WordSense>[];
  for (final raw in text.split(RegExp(r'[;；]'))) {
    var seg = raw.trim().replaceFirst(_leadingMarker, '').trim();
    if (seg.isEmpty) continue;

    var pos = '';
    final m = _leadingPos.firstMatch(seg);
    if (m != null) {
      pos = m.group(1)!.replaceAll(RegExp(r'\s+'), '');
      seg = seg.substring(m.end).trim();
    }
    if (seg.isEmpty) continue;

    // 词性写在词头时（如 `v. 放弃; 放任`），后续释义没有单独标注则沿用
    if (pos.isEmpty && headPos.isNotEmpty) {
      pos = headPos.join('/');
    }
    senses.add(WordSense(pos: pos, cn: seg));
  }
  return senses;
}

/// 从「单词段」里剔除序号、音标、词性标注等噪声，得到干净的词头。
String _cleanHead(String input) {
  var head = input;
  head = head.replaceAll(_bracket, ' '); // (vt.) / [əˈbændən]
  head = head.replaceAll(_slashPhonetic, ' '); // /əˈbændən/
  head = head.replaceAll(_leadingMarker, ''); // 1. / (2) / 3、
  head = head.replaceAll(_posRun, ' '); // v. / adj./adv.
  head = head.replaceAll(_trailingSep, '').trim();

  if (head.isNotEmpty && _wordPattern.hasMatch(head)) return head;

  // 兜底：取第一个英文 token（应对夹杂符号的写法）
  final token = _firstToken.firstMatch(head)?.group(0) ?? '';
  return token;
}
