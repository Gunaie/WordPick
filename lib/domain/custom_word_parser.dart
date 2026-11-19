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
library;

import 'word.dart';

final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');
final RegExp _wordPattern = RegExp(r"^[A-Za-z][A-Za-z'\- ]*$");
final RegExp _trailingSep = RegExp(r'[\s,，:：\-—–、]+$');
final RegExp _leadingMarker = RegExp(r'^\s*(?:[\(\[【]?\d+\s*[\)\]】\.、)]\s*)+');
final RegExp _bracket = RegExp(r'[\(\[【][^\)\]】]*[\)\]】]');
final RegExp _slashPhonetic = RegExp(r'/[^/]{1,40}/');
final RegExp _posToken = RegExp(
  r'(?:^|\s)(?:n|v|vt|vi|adj|adv|prep|conj|pron|art|num|int|aux|phr|abbr|pl)\.(?=\s|$)',
  caseSensitive: false,
);
final RegExp _firstToken = RegExp(r"[A-Za-z][A-Za-z'\-]*");
final RegExp _leadingJunk = RegExp(r'^[\s,，:：\-—–、\)\]】]+');

/// 解析结果：成功新增 / 因已存在而跳过 / 无法识别。
class CustomWordParseResult {
  final List<Word> added;
  final List<String> duplicates;
  final List<String> invalid;

  const CustomWordParseResult({
    this.added = const [],
    this.duplicates = const [],
    this.invalid = const [],
  });
}

/// 解析粘贴文本，返回可新增的词条列表。
///
/// [exclude] 为已存在的词 key（内置词库 + 已添加的自建词），会被跳过。
List<Word> parseCustomWords(String text, {Set<String> exclude = const {}}) {
  return parseCustomWordsDetailed(text, exclude: exclude).added;
}

/// 解析粘贴文本，同时给出跳过原因，便于界面提示。
CustomWordParseResult parseCustomWordsDetailed(
  String text, {
  Set<String> exclude = const {},
}) {
  final added = <Word>[];
  final duplicates = <String>[];
  final invalid = <String>[];
  final seen = <String>{...exclude};

  for (final line in text.split(RegExp(r'[\r\n]+'))) {
    final raw = line.trim();
    if (raw.isEmpty) continue;

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

    head = _cleanHead(head);

    if (head.isEmpty) {
      invalid.add(raw);
      continue;
    }

    final key = head.toLowerCase();
    if (seen.contains(key)) {
      duplicates.add(raw);
      continue;
    }

    final cleanDef = def.replaceFirst(_leadingJunk, '').trim();
    added.add(Word(
      w: head,
      defs: cleanDef.isEmpty ? const [] : [WordSense(cn: cleanDef)],
      tags: const ['custom'],
    ));
    seen.add(key);
  }

  return CustomWordParseResult(
    added: added,
    duplicates: duplicates,
    invalid: invalid,
  );
}

/// 从「单词段」里剔除序号、音标、词性标注等噪声，得到干净的词头。
String _cleanHead(String input) {
  var head = input;
  head = head.replaceAll(_bracket, ' '); // (vt.) / [əˈbændən]
  head = head.replaceAll(_slashPhonetic, ' '); // /əˈbændən/
  head = head.replaceAll(_leadingMarker, ''); // 1. / (2) / 3、
  head = head.replaceAll(_posToken, ' '); // v. / adj. / n./v.
  head = head.replaceAll(_trailingSep, '').trim();

  if (head.isNotEmpty && _wordPattern.hasMatch(head)) return head;

  // 兜底：取第一个英文 token（应对夹杂符号的写法）
  final token = _firstToken.firstMatch(head)?.group(0) ?? '';
  return token;
}
