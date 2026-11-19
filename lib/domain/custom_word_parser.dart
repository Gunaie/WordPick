/// 自建词解析（纯 Dart，无 Flutter 依赖，便于单独测试）
///
/// 支持每行以下格式：
///   word
///   word 释义            （单个空格也可以）
///   word,释义 / word，释义
///   word:释义 / word：释义
///   word    释义         （多空格）
///   word\t释义           （Tab）
library;

import 'word.dart';

final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');
final RegExp _wordPattern = RegExp(r"^[A-Za-z][A-Za-z'\- ]*$");
final RegExp _trailingSep = RegExp(r'[\s,，:：\-]+$');

/// 解析粘贴文本，返回可新增的词条列表。
///
/// [exclude] 为已存在的词 key（内置词库 + 已添加的自建词），会被跳过。
List<Word> parseCustomWords(String text, {Set<String> exclude = const {}}) {
  final out = <Word>[];
  final seen = <String>{...exclude};

  for (final line in text.split(RegExp(r'[\r\n]+'))) {
    final raw = line.trim();
    if (raw.isEmpty) continue;

    // 有中文：在第一个中文字符处切开，前面是单词，后面是释义
    final cjkMatch = _cjk.firstMatch(raw);
    String head;
    String def;
    if (cjkMatch != null) {
      head = raw.substring(0, cjkMatch.start).replaceAll(_trailingSep, '').trim();
      def = raw.substring(cjkMatch.start).trim();
    } else {
      // 纯英文：按标点/多空格切分，首段为单词
      final parts = raw.split(RegExp(r'[\t,，:：]|\s{2,}'));
      head = parts.first.trim();
      def = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';
    }

    if (head.isEmpty || !_wordPattern.hasMatch(head)) continue;

    final key = head.toLowerCase();
    if (seen.contains(key)) continue;

    out.add(Word(
      w: head,
      defs: def.isEmpty ? const [] : [WordSense(cn: def)],
      tags: const ['custom'],
    ));
    seen.add(key);
  }

  return out;
}
