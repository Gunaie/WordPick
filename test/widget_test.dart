import 'package:english_study/data/affix_repository.dart';
import 'package:english_study/data/daily_stat.dart';
import 'package:english_study/data/word_repository.dart';
import 'package:english_study/domain/affix.dart';
import 'package:english_study/domain/custom_word_parser.dart';
import 'package:english_study/domain/edit_distance.dart';
import 'package:english_study/domain/spelling_hints.dart';
import 'package:english_study/domain/srs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SM-2 调度', () {
    test('首次答对间隔为 1 天', () {
      final s = SrsEngine.next(ReviewState.initial(), ReviewGrade.good);
      expect(s.reps, 1);
      expect(s.interval, 1);
      expect(s.lapses, 0);
    });

    test('连续答对间隔递增', () {
      var s = SrsEngine.next(ReviewState.initial(), ReviewGrade.good);
      s = SrsEngine.next(s, ReviewGrade.good);
      expect(s.interval, 3);
      s = SrsEngine.next(s, ReviewGrade.good);
      expect(s.interval, greaterThan(3));
    });

    test('忘记后重置并累计 lapses', () {
      var s = SrsEngine.next(ReviewState.initial(), ReviewGrade.good);
      s = SrsEngine.next(s, ReviewGrade.good);
      final before = s.lapses;
      s = SrsEngine.next(s, ReviewGrade.again);
      expect(s.reps, 0);
      expect(s.interval, 0);
      expect(s.lapses, before + 1);
      expect(s.due.difference(DateTime.now()).inMinutes, lessThanOrEqualTo(11));
    });

    test('E-Factor 不低于 1.3', () {
      var s = ReviewState.initial();
      for (var i = 0; i < 10; i++) {
        s = SrsEngine.next(s, ReviewGrade.again);
      }
      expect(s.ease, greaterThanOrEqualTo(1.3));
    });
  });

  group('拼写容错', () {
    test('完全一致', () {
      expect(SpellVerdict.of('predict', 'predict'), SpellVerdict.correct);
    });

    test('差一个字母算笔误', () {
      expect(SpellVerdict.of('accomodate', 'accommodate'), SpellVerdict.nearMiss);
    });

    test('差两个字母判错', () {
      expect(SpellVerdict.of('predekt', 'predict'), SpellVerdict.wrong);
    });

    test('大小写不敏感', () {
      expect(SpellVerdict.of('Predict', 'predict'), SpellVerdict.correct);
    });
  });

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
      expect(m.any((e) => e.affix.type == AffixType.prefix && e.matched == 'pre'),
          isTrue);
      expect(m.any((e) => e.affix.type == AffixType.root && e.matched == 'dict'),
          isTrue);
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
      const list = [
        Affix(type: AffixType.suffix, form: '-ly', meaning: '副词'),
      ];
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

  group('学习统计', () {
    final today = DateTime(2026, 11, 3);

    test('日期键格式固定为 yyyy-MM-dd', () {
      expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(dayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('连续 3 天（含今天）', () {
      final stats = [
        DailyStat(date: '2026-11-01', reviews: 5),
        DailyStat(date: '2026-11-02', reviews: 3),
        DailyStat(date: '2026-11-03', reviews: 8),
      ];
      expect(streakOf(stats, now: today), 3);
    });

    test('今天没学但昨天学了，连续不断', () {
      final stats = [
        DailyStat(date: '2026-11-01', reviews: 5),
        DailyStat(date: '2026-11-02', reviews: 3),
      ];
      expect(streakOf(stats, now: today), 2);
    });

    test('昨天也没学则归零', () {
      final stats = [DailyStat(date: '2026-11-01', reviews: 5)];
      expect(streakOf(stats, now: today), 0);
    });

    test('中间断开只算最近一段', () {
      final stats = [
        DailyStat(date: '2026-10-30', reviews: 2),
        DailyStat(date: '2026-11-02', reviews: 1),
        DailyStat(date: '2026-11-03', reviews: 4),
      ];
      expect(streakOf(stats, now: today), 2);
    });

    test('复习次数为 0 不算学习日', () {
      final stats = [
        DailyStat(date: '2026-11-02', reviews: 0),
        DailyStat(date: '2026-11-03', reviews: 2),
      ];
      expect(streakOf(stats, now: today), 1);
    });
  });

  group('考试练习题数据', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('题目结构完整且答案索引合法', () async {
      final repo = WordRepository();
      await repo.load();

      final withQuiz = repo.all.where((w) => w.quiz.isNotEmpty).toList();
      expect(withQuiz.length, greaterThan(400));

      var total = 0;
      for (final w in withQuiz) {
        for (final q in w.quiz) {
          total++;
          expect(q.question, isNotEmpty, reason: '${w.w} 题干为空');
          expect(q.options.length, greaterThanOrEqualTo(2),
              reason: '${w.w} 选项不足');
          expect(q.answerIndex, inInclusiveRange(0, q.options.length - 1),
              reason: '${w.w} 答案索引越界');
          expect(q.answerText, isNotEmpty, reason: '${w.w} 答案文本为空');
        }
      }
      expect(total, greaterThan(500));
    });
  });

  group('看义拼写提示', () {
    const affixes = [
      Affix(type: AffixType.prefix, form: 'pre-', meaning: '在前'),
      Affix(type: AffixType.root, form: 'dict', meaning: '说'),
      Affix(type: AffixType.suffix, form: '-tion/-sion', meaning: '名词后缀'),
    ];

    test('首字母提示揭示词长', () {
      expect(firstLetterHint('predict'), 'p _ _ _ _ _ _');
      expect(firstLetterHint('a'), 'a');
      expect(firstLetterHint(''), '');
    });

    test('音节数（元音组启发式 + 哑音 e 修正）', () {
      expect(syllableCount('predict'), 2);
      expect(syllableCount('beautiful'), 3);
      expect(syllableCount('inspection'), 3);
      expect(syllableCount('make'), 1); // 词尾哑音 e 不计
      expect(syllableCount('apple'), 2); // -le 前是辅音，保留
      expect(syllableCount('cat'), 1);
      expect(syllableCount(''), 0);
    });

    test('词根拆解提示拼接命中段', () {
      expect(affixBreakdownHint('predict', affixes), 'pre- + dict');
      expect(affixBreakdownHint('xyz不存在', affixes), '');
    });
  });

  group('自建词解析', () {
    test('支持纯单词、空格释义、逗号释义', () {
      final r = parseCustomWordsDetailed(
        'serendipity\nresilient 有韧性的\nubiquitous, 无处不在的',
      );
      expect(
        r.added.map((w) => w.w).toList(),
        ['serendipity', 'resilient', 'ubiquitous'],
      );
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
      expect(
        r.added.map((w) => w.w).toList(),
        ['abandon', 'resilient', 'ubiquitous', 'cosmopolitan', 'diligent'],
      );
      expect(r.invalid, isEmpty);
    });

    test('区分已存在与无法识别', () {
      final r = parseCustomWordsDetailed('hello\n123\n!!!', exclude: {'hello'});
      expect(r.added, isEmpty);
      expect(r.duplicates, ['hello']);
      expect(r.invalid, ['123', '!!!']);
    });
  });
}
