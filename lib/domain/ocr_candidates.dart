/// 拍照识别文本 → 候选词条（纯 Dart，无 Flutter 依赖，便于单独测试）
///
/// 手写草稿常见两种排版：一行「单词 释义」，或单词一行、释义另起一行。
/// 先按行合并，再复用 [parseCustomWordLine] 的规则解析，得到可校对的候选。
library;

import 'custom_word_parser.dart';
import 'word.dart';

/// 候选词条：解析后的词 + 原始识别文本（校对时对照来源）
class OcrCandidate {
  final Word word;
  final String raw;

  const OcrCandidate({required this.word, required this.raw});

  OcrCandidate copyWith({Word? word}) =>
      OcrCandidate(word: word ?? this.word, raw: raw);
}

/// 一次识别的解析结果
class OcrScanResult {
  /// 可导入的候选（已按单词去重）
  final List<OcrCandidate> candidates;

  /// 识别出文字但解析不出英文单词的行
  final List<String> unparsed;

  const OcrScanResult({
    this.candidates = const [],
    this.unparsed = const [],
  });

  bool get isEmpty => candidates.isEmpty && unparsed.isEmpty;
}

final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');
final RegExp _leadingPos = RegExp(
  r'^(?:n|v|vt|vi|adj|adv|prep|conj|pron|art|num|int|aux|phr|abbr|pl)\.\s*',
  caseSensitive: false,
);

/// 把 OCR 文本解析成候选词条
OcrScanResult parseOcrText(String text) {
  final lines = [
    for (final line in text.split(RegExp(r'[\r\n]+')))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  // 单词独占一行、释义在下一行时先合并，便于复用单行解析
  final merged = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final next = i + 1 < lines.length ? lines[i + 1] : null;
    final parsed = parseCustomWordLine(line);
    if (next != null &&
        parsed != null &&
        parsed.defs.isEmpty &&
        _looksLikeDefinition(next)) {
      merged.add('$line $next');
      i++;
    } else {
      merged.add(line);
    }
  }

  final candidates = <OcrCandidate>[];
  final unparsed = <String>[];
  final seen = <String>{};
  for (final raw in merged) {
    final word = parseCustomWordLine(raw);
    if (word == null) {
      unparsed.add(raw);
      continue;
    }
    if (!seen.add(word.key)) continue;
    candidates.add(OcrCandidate(word: word, raw: raw));
  }
  return OcrScanResult(candidates: candidates, unparsed: unparsed);
}

/// 该行是否像一条释义（以中文开头，或「n. 中文」这种词性 + 中文）
bool _looksLikeDefinition(String line) {
  final body = line.replaceFirst(_leadingPos, '').trimLeft();
  if (body.isEmpty) return false;
  return _cjk.hasMatch(body.substring(0, 1));
}
