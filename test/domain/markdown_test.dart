import 'package:english_study/domain/markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Markdown 预览解析', () {
    test('识别标题、列表、引用、代码块与分隔线', () {
      final blocks = parseMarkdown('''
# 一级标题
## 二级标题
- 无序项
1. 有序项
> 引用内容
```
final a = 1;
```
---
普通段落
第二行
''');
      expect(blocks.map((b) => b.type).toList(), [
        MarkdownBlockType.heading,
        MarkdownBlockType.heading,
        MarkdownBlockType.bullet,
        MarkdownBlockType.ordered,
        MarkdownBlockType.quote,
        MarkdownBlockType.code,
        MarkdownBlockType.rule,
        MarkdownBlockType.paragraph,
      ]);
      expect(blocks[0].level, 1);
      expect(blocks[1].level, 2);
      expect(blocks[0].text, '一级标题');
      expect(blocks[3].level, 1);
      expect(blocks[5].text, 'final a = 1;');
      expect(blocks[7].text, '普通段落\n第二行');
    });

    test('空文本只产生空列表', () {
      expect(parseMarkdown('  \n\n'), isEmpty);
    });

    test('段落遇到新的块起始行时断开', () {
      final blocks = parseMarkdown('第一段\n- 列表项\n第二段');
      expect(blocks.map((b) => b.type).toList(), [
        MarkdownBlockType.paragraph,
        MarkdownBlockType.bullet,
        MarkdownBlockType.paragraph,
      ]);
      expect(blocks.first.text, '第一段');
      expect(blocks.last.text, '第二段');
    });
  });
}
