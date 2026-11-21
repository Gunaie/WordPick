/// 极简 Markdown 块级解析（仅用于笔记预览）
///
/// 只支持常用子集：标题（1–3 级）、无序 / 有序列表、引用、代码块、分隔线与段落。
/// 行内语法（粗体 / 斜体 / 行内代码）由界面层处理，这里只负责分块。
library;

enum MarkdownBlockType { heading, bullet, ordered, quote, code, rule, paragraph }

class MarkdownBlock {
  final MarkdownBlockType type;
  final String text;

  /// 标题层级（1–3）；有序列表的起始序号
  final int level;

  const MarkdownBlock(this.type, this.text, {this.level = 0});
}

final RegExp _heading = RegExp(r'^(#{1,3})\s+(.*)$');
final RegExp _bullet = RegExp(r'^[-*+]\s+(.*)$');
final RegExp _ordered = RegExp(r'^(\d+)[.)]\s+(.*)$');
final RegExp _rule = RegExp(r'^(-{3,}|\*{3,}|_{3,})$');

bool _isFence(String line) => line.startsWith('```');

bool _startsBlock(String line) =>
    _isFence(line) ||
    _heading.hasMatch(line) ||
    _rule.hasMatch(line) ||
    line.startsWith('>') ||
    _bullet.hasMatch(line) ||
    _ordered.hasMatch(line);

/// 将 Markdown 文本转换为块列表；空行只用于分隔，不产生块
List<MarkdownBlock> parseMarkdown(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <MarkdownBlock>[];
  var i = 0;

  while (i < lines.length) {
    final line = lines[i].trim();
    if (line.isEmpty) {
      i++;
      continue;
    }

    if (_isFence(line)) {
      final body = <String>[];
      i++;
      while (i < lines.length && !_isFence(lines[i].trim())) {
        body.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++;
      blocks.add(MarkdownBlock(MarkdownBlockType.code, body.join('\n')));
      continue;
    }

    final heading = _heading.firstMatch(line);
    if (heading != null) {
      blocks.add(
        MarkdownBlock(
          MarkdownBlockType.heading,
          heading.group(2)!.trim(),
          level: heading.group(1)!.length,
        ),
      );
      i++;
      continue;
    }

    if (_rule.hasMatch(line)) {
      blocks.add(const MarkdownBlock(MarkdownBlockType.rule, ''));
      i++;
      continue;
    }

    if (line.startsWith('>')) {
      final quote = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        quote.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
        i++;
      }
      blocks.add(MarkdownBlock(MarkdownBlockType.quote, quote.join('\n')));
      continue;
    }

    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      blocks.add(MarkdownBlock(MarkdownBlockType.bullet, bullet.group(1)!.trim()));
      i++;
      continue;
    }

    final ordered = _ordered.firstMatch(line);
    if (ordered != null) {
      blocks.add(
        MarkdownBlock(
          MarkdownBlockType.ordered,
          ordered.group(2)!.trim(),
          level: int.tryParse(ordered.group(1)!) ?? 1,
        ),
      );
      i++;
      continue;
    }

    // 普通段落：连续的非空、非块起始行合并为一段
    final paragraph = <String>[line];
    i++;
    while (i < lines.length) {
      final next = lines[i].trim();
      if (next.isEmpty || _startsBlock(next)) break;
      paragraph.add(next);
      i++;
    }
    blocks.add(MarkdownBlock(MarkdownBlockType.paragraph, paragraph.join('\n')));
  }

  return blocks;
}
