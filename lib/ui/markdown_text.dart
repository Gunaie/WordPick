import 'package:material_ui/material_ui.dart';

import '../domain/markdown.dart';
import 'theme.dart';

/// 轻量 Markdown 预览：块级渲染 + 粗体 / 斜体 / 行内代码
class MarkdownText extends StatelessWidget {
  final String source;
  final TextStyle? style;

  const MarkdownText(this.source, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = (style ?? theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(color: AppColors.text, height: 1.6);
    final blocks = parseMarkdown(source);
    if (blocks.isEmpty) {
      return Text(
        '（还没有内容）',
        style: base.copyWith(color: AppColors.textMuted),
      );
    }

    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      children.add(_block(blocks[i], base));
      if (i != blocks.length - 1) children.add(const SizedBox(height: 8));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _block(MarkdownBlock block, TextStyle base) {
    switch (block.type) {
      case MarkdownBlockType.heading:
        final size = switch (block.level) {
          1 => 22.0,
          2 => 19.0,
          _ => 16.5,
        };
        return Text.rich(
          TextSpan(
            style: base.copyWith(
              fontSize: size,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
            children: _inline(block.text, base),
          ),
        );
      case MarkdownBlockType.bullet:
        return _row('•', block.text, base);
      case MarkdownBlockType.ordered:
        return _row('${block.level}.', block.text, base);
      case MarkdownBlockType.quote:
        return Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: Color(0x662F6F63), width: 3),
            ),
          ),
          child: Text.rich(
            TextSpan(
              style: base.copyWith(color: AppColors.textSecondary),
              children: _inline(block.text, base),
            ),
          ),
        );
      case MarkdownBlockType.code:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x142B2825),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            block.text,
            style: base.copyWith(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
            ),
          ),
        );
      case MarkdownBlockType.rule:
        return const Divider(height: 12, color: Color(0x332B2825));
      case MarkdownBlockType.paragraph:
        return Text.rich(
          TextSpan(style: base, children: _inline(block.text, base)),
        );
    }
  }

  Widget _row(String marker, String text, TextStyle base) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 18,
          child: Text(
            marker,
            style: base.copyWith(color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(style: base, children: _inline(text, base)),
          ),
        ),
      ],
    );
  }
}

final RegExp _inlinePattern = RegExp(r'(\*\*[^*\n]+\*\*|`[^`\n]+`|\*[^*\n]+\*)');

List<InlineSpan> _inline(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  var index = 0;
  for (final match in _inlinePattern.allMatches(text)) {
    if (match.start > index) {
      spans.add(TextSpan(text: text.substring(index, match.start)));
    }
    final token = match.group(0)!;
    if (token.startsWith('**')) {
      spans.add(
        TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    } else if (token.startsWith('`')) {
      spans.add(
        TextSpan(
          text: token.substring(1, token.length - 1),
          style: const TextStyle(
            fontFamily: 'monospace',
            backgroundColor: Color(0x142B2825),
          ),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: token.substring(1, token.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    }
    index = match.end;
  }
  if (index < text.length) {
    spans.add(TextSpan(text: text.substring(index)));
  }
  return spans;
}
