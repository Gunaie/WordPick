/// 词库仓库：加载打包在 assets 里的词表，提供检索与筛选
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../domain/word.dart';

/// 在后台 isolate 中解析 JSON，避免阻塞首帧
List<Word> _parseWords(String raw) {
  final list = jsonDecode(raw) as List<dynamic>;
  return list
      .map((e) => Word.fromJson(e as Map<String, dynamic>))
      .where((w) => w.w.isNotEmpty)
      .toList(growable: false);
}

class WordRepository {
  List<Word> _words = const [];
  Map<String, Word> _byKey = const {};

  bool get isLoaded => _words.isNotEmpty;
  int get count => _words.length;
  List<Word> get all => _words;

  Future<void> load() async {
    if (isLoaded) return;
    final raw = await rootBundle.loadString('assets/data/words.json');
    final parsed = await compute(_parseWords, raw);
    _words = parsed;
    _byKey = {for (final w in parsed) w.key: w};
  }

  Word? byKey(String key) => _byKey[key.toLowerCase()];

  /// 按前缀/包含搜索
  List<Word> search(String query, {int limit = 50}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final prefix = <Word>[];
    final contains = <Word>[];
    for (final w in _words) {
      final k = w.key;
      if (k.startsWith(q)) {
        prefix.add(w);
      } else if (k.contains(q)) {
        contains.add(w);
      }
      if (prefix.length >= limit) break;
    }
    return [...prefix, ...contains].take(limit).toList();
  }

  /// 按考试标签筛选
  List<Word> byTag(String tag, {int limit = 0}) {
    final out = _words.where((w) => w.tags.contains(tag)).toList();
    if (limit > 0 && out.length > limit) return out.sublist(0, limit);
    return out;
  }

  /// 生成当日学习队列：优先到期的复习词，再补新词
  List<Word> buildQueue({
    required Set<String> dueKeys,
    required Set<String> seenKeys,
    required String? examTag,
    int newLimit = 20,
    int dueLimit = 100,
  }) {
    final pool = examTag == null ? _words : byTag(examTag);

    final due = <Word>[];
    for (final w in pool) {
      if (dueKeys.contains(w.key)) due.add(w);
      if (due.length >= dueLimit) break;
    }

    final fresh = <Word>[];
    for (final w in pool) {
      if (seenKeys.contains(w.key)) continue;
      fresh.add(w);
      if (fresh.length >= newLimit) break;
    }

    return [...due, ...fresh];
  }
}
