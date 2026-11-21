import 'package:english_study/domain/custom_word_parser.dart';
import 'package:english_study/domain/ocr_candidates.dart';
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
      expect(
        r.added[0].defs.map((d) => '${d.pos}|${d.cn}').toList(),
        ['n.|苹果', 'n.|苹果公司'],
      );
      expect(r.added[0].uk, isEmpty);
      expect(r.added[1].uk, 'əˈbændən');
      expect(
        r.added[1].defs.map((d) => '${d.pos}|${d.cn}').toList(),
        ['v.|放弃', 'v.|放任'],
      );
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

  group('拍照识别候选解析', () {
    test('同行「单词 + 释义」直接成候选', () {
      final r = parseOcrText('serendipity 意外发现');
      expect(r.candidates, hasLength(1));
      expect(r.candidates.single.word.w, 'serendipity');
      expect(r.candidates.single.word.primaryDefinition, '意外发现');
      expect(r.unparsed, isEmpty);
    });

    test('单词与释义分两行时合并', () {
      final r = parseOcrText('abandon\n放弃');
      expect(r.candidates, hasLength(1));
      expect(r.candidates.single.word.w, 'abandon');
      expect(r.candidates.single.word.primaryDefinition, '放弃');
    });

    test('释义行带词性与多释义也能合并', () {
      final r = parseOcrText('abandon\nv. 放弃; 抛弃');
      final defs = r.candidates.single.word.defs;
      expect(defs.map((d) => d.cn), ['放弃', '抛弃']);
      expect(defs.map((d) => d.pos), ['v.', 'v.']);
    });

    test('两个纯单词行不会被误合并', () {
      final r = parseOcrText('apple\nbanana');
      expect(r.candidates.map((c) => c.word.w), ['apple', 'banana']);
      expect(r.candidates.every((c) => c.word.defs.isEmpty), isTrue);
    });

    test('下一行本身是完整词条时保持独立', () {
      final r = parseOcrText('apple\norange 橙子');
      expect(r.candidates.map((c) => c.word.w), ['apple', 'orange']);
      expect(r.candidates.last.word.primaryDefinition, '橙子');
    });

    test('没有英文的行记为无法识别', () {
      final r = parseOcrText('apple 苹果\n这一行没有英文');
      expect(r.candidates, hasLength(1));
      expect(r.unparsed, ['这一行没有英文']);
    });

    test('同一次识别里的重复词只保留一条', () {
      final r = parseOcrText('apple 苹果\napple 苹果');
      expect(r.candidates, hasLength(1));
    });

    test('单行解析沿用批量导入规则', () {
      final w = parseCustomWordLine('1. abandon [əˈbændən] v. 放弃');
      expect(w?.w, 'abandon');
      expect(w?.uk, 'əˈbændən');
      expect(w?.defs.single.pos, 'v.');
      expect(w?.defs.single.cn, '放弃');
      expect(parseCustomWordLine('苹果'), isNull);
    });
  });
}
