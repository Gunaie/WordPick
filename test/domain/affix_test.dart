import 'package:english_study/data/affix_repository.dart';
import 'package:english_study/domain/affix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('词根词缀拆解', () {
    const affixes = [
      Affix(type: AffixType.prefix, form: 'pre-', meaning: '在前'),
      Affix(type: AffixType.prefix, form: 'in-/im-', meaning: '不'),
      Affix(type: AffixType.root, form: 'dict', meaning: '说'),
      Affix(type: AffixType.root, form: 'spect', meaning: '看'),
      Affix(type: AffixType.suffix, form: '-tion/-sion', meaning: '名词后缀'),
    ];

    test('predict 拆出 pre- 与 dict', () {
      final m = analyzeWord('predict', affixes);
      expect(
        m.any((e) => e.affix.type == AffixType.prefix && e.matched == 'pre'),
        isTrue,
      );
      expect(
        m.any((e) => e.affix.type == AffixType.root && e.matched == 'dict'),
        isTrue,
      );
    });

    test('inspection 拆出前缀、词根、后缀', () {
      final m = analyzeWord('inspection', affixes);
      final types = m.map((e) => e.affix.type).toSet();
      expect(types.contains(AffixType.prefix), isTrue);
      expect(types.contains(AffixType.root), isTrue);
      expect(types.contains(AffixType.suffix), isTrue);
    });

    test('过短的词不拆解', () {
      expect(analyzeWord('in', affixes), isEmpty);
      expect(analyzeWord('pre', affixes), isEmpty);
    });

    test('同类型只保留最长命中', () {
      const list = [
        Affix(type: AffixType.prefix, form: 'in-', meaning: '不'),
        Affix(type: AffixType.prefix, form: 'inter-', meaning: '之间'),
      ];
      final m = analyzeWord('international', list);
      expect(m.length, 1);
      expect(m.first.matched, 'inter');
    });

    test('短后缀需词典佐证：abdomen 不拆、strengthen 拆', () {
      const list = [
        Affix(type: AffixType.suffix, form: '-en', meaning: '动词：使…'),
      ];

      // 词干 abdom 不是单词 → 不拆（避免误导）
      expect(
        analyzeWord('abdomen', list, isKnownWord: (k) => k == 'strength'),
        isEmpty,
      );

      // 词干 strength 是单词 → 正常拆
      final m = analyzeWord(
        'strengthen',
        list,
        isKnownWord: (k) => k == 'strength',
      );
      expect(m.length, 1);
      expect(m.first.matched, 'en');
    });

    test('未提供词典时，2 字母后缀一律不展示', () {
      const list = [Affix(type: AffixType.suffix, form: '-ly', meaning: '副词')];
      expect(analyzeWord('quickly', list), isEmpty);
    });
  });

  group('词缀仓库检索', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('按词形检索返回精确条目', () async {
      final repo = AffixRepository();
      await repo.load();

      expect(repo.all.length, greaterThan(70));

      // 搜索同时匹配「词形 / 含义 / 示例词」，
      // 因此 dict 也会命中 pre-（其示例词含 predict）
      final dict = repo.search('dict');
      expect(
        dict.any((a) => a.form == 'dict' && a.type == AffixType.root),
        isTrue,
      );
      expect(repo.search('dict', type: AffixType.root).length, 1);

      expect(repo.search('xyz不存在'), isEmpty);
    });

    test('类型筛选只返回对应类型', () async {
      final repo = AffixRepository();
      await repo.load();

      final suffixes = repo.search('', type: AffixType.suffix);
      expect(suffixes, isNotEmpty);
      expect(suffixes.every((a) => a.type == AffixType.suffix), isTrue);
    });
  });
}
