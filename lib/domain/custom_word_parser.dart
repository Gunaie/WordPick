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
///
/// 也支持整段 JSON（检测到以 `[` 或 `{` 开头时先尝试）：
///   [{"word": "whip", "defs": ["n. 鞭子"]}]
///   [{"word": "whip", "phonetic": "/wɪp/", "defs": ["n. 鞭子"]}]
///   {"words": [{"w": "whip", "defs": [{"pos": "n.", "cn": "鞭子"}]}]}
library;

import 'dart:convert';

import 'word.dart';

final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');
final RegExp _wordPattern = RegExp(r"^[A-Za-z][A-Za-z'\- ]*$");
final RegExp _trailingSep = RegExp(r'[\s,，:：\-—–、]+$');
final RegExp _leadingMarker = RegExp(r'^\s*(?:[\(\[【]?\d+\s*[\)\]】\.、)]\s*)+');
final RegExp _bracket = RegExp(r'[\(\[【][^\)\]】]*[\)\]】]');
final RegExp _slashPhonetic = RegExp(r'/[^/]{1,40}/');
const String _posNames =
    r'(?:n|v|vt|vi|adj|adv|prep|conj|pron|art|num|int|aux|phr|abbr|pl|a|ad)';
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

  const CustomWordEntry({required this.word, this.addedAt, this.addCount = 1});

  String get key => word.key;

  CustomWordEntry copyWith({Word? word, DateTime? addedAt, int? addCount}) =>
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
  }) => CustomWordBook(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    words: words ?? this.words,
  );

  factory CustomWordBook.fromJson(Map<String, dynamic> j) {
    final created =
        DateTime.tryParse('${j['created_at'] ?? ''}') ?? DateTime.now();
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
  final trimmed = text.trim();
  final jsonText = _jsonCandidate(trimmed);
  if (jsonText != null) {
    final jsonResult = _parseJsonWords(jsonText, repeatable);
    if (jsonResult != null) return jsonResult;
  }

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

/// 从输入中提取 JSON 片段：兼容 Markdown 代码块和前后说明文字
String? _jsonCandidate(String text) {
  var s = text.trim();
  if (s.startsWith('\uFEFF')) s = s.substring(1).trimLeft();
  if (s.isEmpty) return null;

  // ```json ... ``` / ``` ... ```
  final fence = RegExp(r'```(?:json|JSON)?[ \t]*\r?\n').firstMatch(s);
  if (fence != null) {
    s = s.substring(fence.end);
    final end = s.indexOf('```');
    if (end >= 0) s = s.substring(0, end);
    return _bracketSlice(s.trim()) ?? s.trim();
  }

  // 直接以 [ 或 { 开头
  if (s.startsWith('[') || s.startsWith('{')) {
    return _bracketSlice(s) ?? s;
  }

  // 前面有「以下是结果：」之类的说明，从第一行以括号开头的位置截取
  final lines = s.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trimLeft();
    if (line.startsWith('[') || line.startsWith('{')) {
      final candidate = lines.sublist(i).join('\n');
      return _bracketSlice(candidate) ?? candidate.trim();
    }
  }
  return null;
}

/// 截取从第一个括号到最后一个闭合括号的内容
String? _bracketSlice(String input) {
  final start = input.indexOf(RegExp(r'[\[\{]'));
  if (start < 0) return null;
  final lastSquare = input.lastIndexOf(']');
  final lastCurly = input.lastIndexOf('}');
  final end = lastSquare > lastCurly ? lastSquare : lastCurly;
  if (end <= start) return null;
  return input.substring(start, end + 1).trim();
}

/// 修掉模型常见的尾逗号：`,}` / `,]`
String _repairJson(String input) =>
    input.replaceAllMapped(RegExp(r',\s*([\]}])'), (m) => m.group(1)!);

/// 解析整段 JSON；不是合法 JSON 时返回 null，调用方回退到按行解析
CustomWordParseResult? _parseJsonWords(String text, Set<String> repeatable) {
  dynamic decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    try {
      decoded = jsonDecode(_repairJson(text));
    } catch (_) {
      return null;
    }
  }

  final List<dynamic> items;
  if (decoded is List) {
    items = decoded;
  } else if (decoded is Map<String, dynamic>) {
    final words = decoded['words'];
    items = words is List ? words : [decoded];
  } else {
    return null;
  }

  // 合法 JSON 但不是词表（例如 `[1]`），回退按行解析
  if (items.isNotEmpty &&
      !items.any((e) => e is Map && (e['word'] ?? e['w']) != null)) {
    return null;
  }

  final added = <Word>[];
  final repeated = <String, int>{};
  final invalid = <String>[];
  final seen = <String>{};

  for (final item in items) {
    if (item is! Map) {
      invalid.add(item?.toString() ?? '');
      continue;
    }
    final word = _wordFromJson(Map<String, dynamic>.from(item));
    if (word == null) {
      invalid.add(jsonEncode(item));
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

/// JSON 词条：兼容 `word`/`w`、`defs` 字符串或对象、可选 `phonetic`/`uk`/`us`/`tags`
Word? _wordFromJson(Map<String, dynamic> map) {
  final rawWord = (map['word'] ?? map['w'] ?? '').toString().trim();
  if (rawWord.isEmpty) return null;
  final head = _cleanHead(rawWord);
  if (head.isEmpty) return null;

  final phonetic = (map['phonetic'] ?? '').toString().trim();
  final uk = (map['uk'] ?? phonetic).toString().trim();
  final us = (map['us'] ?? phonetic).toString().trim();

  final senses = <WordSense>[];
  final rawDefs = map['defs'] ?? map['definitions'] ?? map['definition'];
  if (rawDefs is List) {
    for (final item in rawDefs) {
      final sense = _senseFromJson(item);
      if (sense != null) senses.add(sense);
    }
  } else if (rawDefs != null) {
    final sense = _senseFromJson(rawDefs);
    if (sense != null) senses.add(sense);
  }
  // 同词性 + 同释义去重（模型输出或分号拆分时可能重复）
  final deduped = _dedupeSenses(senses);

  final tags = <String>{'custom'};
  final rawTags = map['tags'];
  if (rawTags is List) {
    for (final item in rawTags) {
      final tag = item.toString().trim();
      if (tag.isNotEmpty) tags.add(tag);
    }
  }

  return Word(
    w: head,
    uk: _cleanPhonetic(uk),
    us: _cleanPhonetic(us),
    defs: deduped,
    tags: tags.toList(),
  );
}

/// 按「词性 + 释义」去重，保留首次出现的顺序。
///
/// 比较前做轻量规范化（合并空白、词性小写去空格），避免 `n. 苹果` / `n .苹果`
/// 这类仅空白差异的重复。展示值仍用原始 trim 后的内容。
List<WordSense> _dedupeSenses(List<WordSense> senses) {
  final seen = <String>{};
  final out = <WordSense>[];
  for (final s in senses) {
    final key =
        '${s.pos.replaceAll(RegExp(r'\s+'), '').toLowerCase()}|${s.cn.replaceAll(RegExp(r'\s+'), ' ').trim()}';
    if (seen.add(key)) out.add(s);
  }
  return out;
}

WordSense? _senseFromJson(dynamic value) {
  if (value is Map) {
    final pos = (value['pos'] ?? '').toString().trim();
    final cn = (value['cn'] ?? value['def'] ?? value['meaning'] ?? '')
        .toString()
        .trim();
    if (cn.isEmpty) return null;
    return WordSense(pos: pos, cn: cn);
  }
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return _senseFromString(text);
}

/// 把 `n. 鞭子` / `a. 公正的` 拆成词性与释义
WordSense? _senseFromString(String raw) {
  var seg = raw.trim();
  if (seg.isEmpty) return null;
  var pos = '';
  final m = _leadingPos.firstMatch(seg);
  if (m != null) {
    pos = m.group(1)!.replaceAll(RegExp(r'\s+'), '');
    seg = seg.substring(m.end).trim();
  }
  if (seg.isEmpty) return null;
  return WordSense(pos: pos, cn: seg);
}

String _cleanPhonetic(String input) =>
    input.replaceAll('/', '').replaceAll(RegExp(r'^\[|\]$'), '').trim();

/// 解析单行文本为词条；取不到英文单词时返回 null。
///
/// 批量导入共用这一套规则。
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
    final inside = m.group(0)!.substring(1, m.group(0)!.length - 1).trim();
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
  return _dedupeSenses(senses);
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
