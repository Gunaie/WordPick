import 'package:english_study/domain/custom_word_parser.dart';
import 'package:english_study/domain/word.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('自建词解析', () {
    test('支持纯单词、空格释义、逗号释义', () {
      final r = parseCustomWordsDetailed(
        'serendipity\nresilient 有韧性的\nubiquitous, 无处不在的',
      );
      expect(r.added.map((w) => w.w).toList(), [
        'serendipity',
        'resilient',
        'ubiquitous',
      ]);
      expect(r.added[1].primaryDefinition, '有韧性的');
      expect(r.invalid, isEmpty);
    });

    test('可容忍序号、音标与词性标注', () {
      final r = parseCustomWordsDetailed(
        '1. abandon 放弃\n'
        '2) resilient [rɪˈzɪliənt] 有韧性的\n'
        '3、ubiquitous /juːˈbɪkwɪtəs/ 无处不在的\n'
        'cosmopolitan adj. 世界性的\n'
        'diligent (adj.) 勤勉的',
      );
      expect(r.added.map((w) => w.w).toList(), [
        'abandon',
        'resilient',
        'ubiquitous',
        'cosmopolitan',
        'diligent',
      ]);
      expect(r.added[1].uk, 'rɪˈzɪliənt');
      expect(r.added[2].uk, 'juːˈbɪkwɪtəs');
      expect(r.added[3].defs.single.pos, 'adj.');
      expect(r.added[4].defs.single.pos, 'adj.');
      expect(r.invalid, isEmpty);
    });

    test('支持分号多释义、词性与音标', () {
      final r = parseCustomWordsDetailed(
        'apple n. 苹果; n. 苹果公司\n'
        'abandon [əˈbændən] v. 放弃; 放任',
      );
      expect(r.added, hasLength(2));
      expect(r.added[0].defs.map((d) => '${d.pos}|${d.cn}').toList(), [
        'n.|苹果',
        'n.|苹果公司',
      ]);
      expect(r.added[0].uk, isEmpty);
      expect(r.added[1].uk, 'əˈbændən');
      expect(r.added[1].defs.map((d) => '${d.pos}|${d.cn}').toList(), [
        'v.|放弃',
        'v.|放任',
      ]);
    });

    test('区分已存在与无法识别', () {
      final r = parseCustomWordsDetailed(
        'hello\n123\n!!!',
        repeatable: {'hello'},
      );
      expect(r.added, isEmpty);
      expect(r.repeated, {'hello': 1});
      expect(r.invalid, ['123', '!!!']);
    });

    test('重复导入只累加次数', () {
      final r = parseCustomWordsDetailed(
        'serendipity 意外发现\nserendipity\nresilient 有韧性的',
        repeatable: {'resilient'},
      );
      expect(r.added.map((w) => w.w).toList(), ['serendipity']);
      expect(r.repeated, {'serendipity': 1, 'resilient': 1});
    });

    test('支持 JSON 数组：word + defs 字符串', () {
      final r = parseCustomWordsDetailed('''
[
  {"word": "impartial", "defs": ["a. 公正的"]},
  {"word": "apart", "defs": ["ad. 相距；除外"]},
  {"word": "terrace", "defs": ["n. 露台，梯田"]}
]
''');
      expect(r.added.map((w) => w.w).toList(), [
        'impartial',
        'apart',
        'terrace',
      ]);
      expect(r.added[0].defs.single.pos, 'a.');
      expect(r.added[1].defs.single.pos, 'ad.');
      expect(r.added[2].primaryDefinition, '露台，梯田');
      expect(r.invalid, isEmpty);
    });

    test('支持 words 包裹、对象释义与音标', () {
      final r = parseCustomWordsDetailed('''
{"words": [
  {"w": "whip", "phonetic": "/wɪp/", "defs": [{"pos": "n.", "cn": "鞭子"}]}
]}
''');
      expect(r.added.single.w, 'whip');
      expect(r.added.single.uk, 'wɪp');
      expect(r.added.single.us, 'wɪp');
      expect(r.added.single.defs.single.pos, 'n.');
      expect(r.added.single.defs.single.cn, '鞭子');
    });

    test('JSON 内重复词只累加次数', () {
      final r = parseCustomWordsDetailed(
        '[{"word":"impart","defs":["v. 传达"]},'
        '{"word":"whip","defs":["n. 鞭子"]},'
        '{"word":"whip","defs":["n. 鞭子"]}]',
        repeatable: {'impart'},
      );
      expect(r.added.map((w) => w.w).toList(), ['whip']);
      expect(r.repeated, {'impart': 1, 'whip': 1});
    });

    test('不是合法 JSON 时回退按行解析', () {
      final r = parseCustomWordsDetailed('[1] apple 苹果');
      expect(r.added.single.w, 'apple');
      expect(r.added.single.primaryDefinition, '苹果');
    });

    test('兼容 Markdown 代码块与前后说明文字', () {
      final r = parseCustomWordsDetailed('''
以下是整理好的词表：
```json
[
  {"word": "whip", "defs": ["n. 鞭子"]},
  {"word": "ranch", "defs": ["n. 大牧场"]}
]
```
共 2 个词。
''');
      expect(r.added.map((w) => w.w).toList(), ['whip', 'ranch']);
      expect(r.invalid, isEmpty);
    });

    test('容忍模型输出里的尾逗号', () {
      final r = parseCustomWordsDetailed('''
[
  {"word": "whip", "defs": ["n. 鞭子"],},
  {"word": "ranch", "defs": ["n. 大牧场"],},
]
''');
      expect(r.added.map((w) => w.w).toList(), ['whip', 'ranch']);
    });

    test('词条 JSON 可往返，且兼容旧数据', () {
      final entry = CustomWordEntry(
        word: const Word(
          w: 'serendipity',
          defs: [WordSense(cn: '意外发现')],
        ),
        addedAt: DateTime(2026, 11, 20, 10, 30),
        addCount: 3,
      );
      final restored = CustomWordEntry.fromJson(entry.toJson());
      expect(restored.word.w, 'serendipity');
      expect(restored.word.primaryDefinition, '意外发现');
      expect(restored.addCount, 3);
      expect(restored.addedAt, DateTime(2026, 11, 20, 10, 30));

      // 旧版本没有 added_at / add_count
      final legacy = CustomWordEntry.fromJson(const {
        'w': 'legacy',
        'defs': [],
      });
      expect(legacy.addedAt, isNull);
      expect(legacy.addCount, 1);
    });

    test('导入时同词性同释义自动去重', () {
      final r = parseCustomWordsDetailed('''
[
  {"word": "apple", "defs": [
    {"pos": "n.", "cn": "苹果"},
    {"pos": "n.", "cn": "苹果"},
    {"pos": "v.", "cn": "苹果"},
    {"pos": "n.", "cn": "苹果公司"}
  ]}
]
''');
      expect(r.added.single.defs.map((d) => '${d.pos}|${d.cn}').toList(), [
        'n.|苹果',
        'v.|苹果',
        'n.|苹果公司',
      ]);
    });

    test('文本分号多释义也去重，并忽略空白差异', () {
      // 第二条与第一条仅多余空格不同，应合并为一条
      final r = parseCustomWordsDetailed('apple n. 苹果;  n.  苹果; n. 苹果公司');
      expect(r.added.single.defs.map((d) => '${d.pos}|${d.cn}').toList(), [
        'n.|苹果',
        'n.|苹果公司',
      ]);
    });

    test('单词本 JSON 可往返', () {
      final book = CustomWordBook(
        id: 'b1',
        name: '考研核心',
        createdAt: DateTime(2026, 11, 20),
        words: [
          CustomWordEntry(
            word: const Word(
              w: 'resilient',
              defs: [WordSense(cn: '有韧性的')],
            ),
            addedAt: DateTime(2026, 11, 20, 9),
            addCount: 2,
          ),
        ],
      );
      final restored = CustomWordBook.fromJson(book.toJson());
      expect(restored.id, 'b1');
      expect(restored.name, '考研核心');
      expect(restored.words.length, 1);
      expect(restored.words.first.word.w, 'resilient');
      expect(restored.words.first.word.primaryDefinition, '有韧性的');
      expect(restored.words.first.addCount, 2);
    });
  });

  test('单行解析沿用批量导入规则', () {
    final w = parseCustomWordLine('1. abandon [əˈbændən] v. 放弃');
    expect(w?.w, 'abandon');
    expect(w?.uk, 'əˈbændən');
    expect(w?.defs.single.pos, 'v.');
    expect(w?.defs.single.cn, '放弃');
    expect(parseCustomWordLine('苹果'), isNull);
  });
}
