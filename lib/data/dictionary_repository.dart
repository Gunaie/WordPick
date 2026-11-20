/// 离线词典：assets/data/dict_core.json
///
/// 资产由 scripts/build_dict_assets.js 生成（约 1.4 万词，取自考纲词书），
/// 只用于加词时带出音标与释义，不做在线兜底。
library;

import 'dart:convert';

import 'package:flutter/services.dart';

class DictEntry {
  final String word;
  final String phonetic;
  final String translation;

  const DictEntry({
    required this.word,
    this.phonetic = '',
    required this.translation,
  });
}

class DictionaryRepository {
  static const assetPath = 'assets/data/dict_core.json';

  Map<String, DictEntry> _entries;

  DictionaryRepository({Map<String, DictEntry>? entries})
      : _entries = entries ?? const {};

  int get size => _entries.length;
  bool get isLoaded => _entries.isNotEmpty;

  Future<void> load() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      _entries = decode(raw);
    } catch (_) {
      // 词典是增强能力，加载失败不影响手动加词
      _entries = const {};
    }
  }

  DictEntry? lookup(String word) {
    final key = normalize(word);
    return key.isEmpty ? null : _entries[key];
  }

  static String normalize(String word) => word.trim().toLowerCase();

  /// 解析紧凑 JSON：{"word":["音标","中文释义"]}
  static Map<String, DictEntry> decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return const {};

    final result = <String, DictEntry>{};
    decoded.forEach((key, value) {
      if (value is! List || value.length < 2) return;
      final phonetic = value[0];
      final translation = value[1];
      if (phonetic is! String || translation is! String) return;

      final word = normalize(key);
      final text = translation.trim();
      if (word.isEmpty || text.isEmpty) return;
      result[word] = DictEntry(
        word: word,
        phonetic: phonetic.trim(),
        translation: text,
      );
    });
    return result;
  }
}
