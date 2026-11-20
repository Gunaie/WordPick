import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:english_study/data/affix_repository.dart';
import 'package:english_study/data/app_settings.dart';
import 'package:english_study/data/daily_stat.dart';
import 'package:english_study/data/dictionary_repository.dart';
import 'package:english_study/data/note_record.dart';
import 'package:english_study/domain/export_builder.dart';
import 'package:english_study/domain/export_import.dart';
import 'package:english_study/domain/affix.dart';
import 'package:english_study/domain/custom_word_parser.dart';
import 'package:english_study/domain/edit_distance.dart';
import 'package:english_study/domain/learning_quiz.dart';
import 'package:english_study/domain/spelling_hints.dart';
import 'package:english_study/domain/srs.dart';
import 'package:english_study/domain/word.dart';
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
      expect(
        SpellVerdict.of('accomodate', 'accommodate'),
        SpellVerdict.nearMiss,
      );
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

  group('学习四选一', () {
    final pool = [
      const Word(
        w: 'resilient',
        defs: [WordSense(pos: 'adj', cn: '有韧性的')],
      ),
      const Word(
        w: 'abandon',
        defs: [WordSense(pos: 'v', cn: '放弃')],
      ),
      const Word(
        w: 'ubiquitous',
        defs: [WordSense(pos: 'adj', cn: '无处不在的')],
      ),
      const Word(
        w: 'diligent',
        defs: [WordSense(pos: 'adj', cn: '勤勉的')],
      ),
    ];

    test('词池足够时生成四个选项且只有一个正确', () {
      final q = buildQuiz(pool.first, pool);
      expect(q, isNotNull);
      expect(q!.options.length, 4);
      expect(q.options.where((o) => o.isCorrect).length, 1);
      expect(q.options.firstWhere((o) => o.isCorrect).text, '有韧性的');
    });

    test('优先使用同词性的干扰项', () {
      final q = buildQuiz(pool.first, pool)!;
      final wrongPos = q.options
          .where((o) => !o.isCorrect)
          .map((o) => o.pos)
          .toSet();
      expect(wrongPos.contains('adj'), isTrue);
    });

    test('少于 4 个带释义的词无法出题', () {
      expect(buildQuiz(pool.first, pool.take(3).toList()), isNull);
      expect(canBuildQuiz(pool.take(3).toList()), isFalse);
      expect(canBuildQuiz(pool), isTrue);
    });

    test('自动评分映射：错→重来，对→一般，熟词答对→简单', () {
      expect(autoGrade(correct: false, reps: 10), ReviewGrade.again);
      expect(autoGrade(correct: true, reps: 0), ReviewGrade.good);
      expect(autoGrade(correct: true, reps: 3), ReviewGrade.easy);
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

    test('四选一：4 个唯一选项且包含正确拼写', () {
      const pool = [
        Word(w: 'resilient'),
        Word(w: 'abandon'),
        Word(w: 'ubiquitous'),
        Word(w: 'diligent'),
        Word(w: 'predict'),
      ];
      final options =
          buildSpellingChoices(pool.first, pool, random: Random(1))!;
      expect(options.length, 4);
      expect(options.toSet().length, 4);
      expect(options.map((o) => o.toLowerCase()), contains('resilient'));
    });

    test('四选一：优先取同首字母的干扰项', () {
      const pool = [
        Word(w: 'resilient'),
        Word(w: 'rely'),
        Word(w: 'reject'),
        Word(w: 'random'),
        Word(w: 'apple'),
      ];
      final options =
          buildSpellingChoices(pool.first, pool, random: Random(3))!;
      final distractors = options.where((o) => o != 'resilient');
      expect(distractors.length, 3);
      expect(distractors.every((o) => o.startsWith('r')), isTrue);
    });

    test('四选一：不足 4 个不同拼写时返回 null', () {
      const pool = [
        Word(w: 'apple'),
        Word(w: 'apple'),
        Word(w: 'apply'),
        Word(w: 'APPLY'),
      ];
      expect(buildSpellingChoices(pool.first, pool), isNull);
    });
  });

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

  group('导出内容', () {
    final now = DateTime(2026, 11, 20, 21, 5);
    final notes = [
      NoteRecord(
        id: 'n1',
        wordKey: 'apple',
        title: '苹果的复数',
        content: '苹果；注意复数 apples',
        tags: const ['名词', '例句'],
        createdAt: now,
        updatedAt: now,
      ),
      NoteRecord(
        id: 'n2',
        wordKey: '',
        content: '今天读到一句好句子。',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    test('JSON 包含词书、笔记、复习状态与每日统计', () {
      final book = CustomWordBook(
        id: 'b1',
        name: '我的单词本',
        createdAt: now,
        words: [
          CustomWordEntry(
            word: const Word(
              w: 'apple',
              defs: [WordSense(cn: '苹果')],
            ),
            addedAt: now,
          ),
        ],
      );
      final state = ReviewState.initial();
      final raw = buildJsonExport(
        books: [book],
        notes: notes,
        states: {'apple': state},
        daily: [const DailyStat(date: '2026-11-20', reviews: 3, newWords: 1)],
        now: now,
      );

      final json = jsonDecode(raw) as Map<String, dynamic>;
      expect(json['schema'], 1);
      expect(json['exported_at'], now.toIso8601String());
      expect((json['books'] as List).single['name'], '我的单词本');
      expect((json['notes'] as List).length, 2);
      expect((json['notes'] as List).first['title'], '苹果的复数');
      expect((json['notes'] as List).first['tags'], ['名词', '例句']);
      expect((json['review_states'] as Map)['apple']['reps'], 0);
      expect((json['daily'] as List).single['date'], '2026-11-20');
      expect((json['daily'] as List).single['r'], 3);
    });

    test('Markdown 按单词分组并包含随手记', () {
      final md = buildNotesMarkdown(notes: notes, now: now);
      expect(md, contains('# 英语笔记'));
      expect(md, contains('## apple'));
      expect(md, contains('苹果的复数'));
      expect(md, contains('#名词 #例句'));
      expect(md, contains('苹果；注意复数 apples'));
      expect(md, contains('## 随手记'));
      expect(md, contains('今天读到一句好句子。'));
      expect(md, contains('2026-11-20 21:05'));
    });

    test('空笔记导出给出说明而不是空白', () {
      final md = buildNotesMarkdown(notes: const [], now: now);
      expect(md, contains('还没有笔记'));
    });
  });

  group('学习设置', () {
    test('默认英音、每组新词 10、每组复习 20、拼写 10 题', () {
      const s = AppSettings();
      expect(s.useUkAccent, isTrue);
      expect(s.newWordsPerGroup, 10);
      expect(s.reviewWordsPerGroup, 20);
      expect(s.spellingWords, 10);
    });

    test('JSON 往返保存口音与题量', () {
      const s = AppSettings(
        useUkAccent: false,
        newWordsPerGroup: 20,
        reviewWordsPerGroup: 30,
        spellingWords: 15,
      );
      final restored = AppSettings.fromJson(s.toJson());
      expect(restored.useUkAccent, isFalse);
      expect(restored.newWordsPerGroup, 20);
      expect(restored.reviewWordsPerGroup, 30);
      expect(restored.spellingWords, 15);
    });

    test('越界值钳制：新词 / 拼写 5–50，复习 5–200', () {
      final s = AppSettings.fromJson(const {
        'accent': 'us',
        'new_words_per_group': 1,
        'review_words_per_group': 999,
        'spelling_words': 999,
      });
      expect(s.useUkAccent, isFalse);
      expect(s.newWordsPerGroup, 5);
      expect(s.reviewWordsPerGroup, 200);
      expect(s.spellingWords, 50);

      final empty = AppSettings.fromJson(const {});
      expect(empty.newWordsPerGroup, 10);
      expect(empty.reviewWordsPerGroup, 20);
      expect(empty.spellingWords, 10);
      expect(empty.useUkAccent, isTrue);
    });
  });

  group('备份恢复解析', () {
    final now = DateTime(2026, 11, 20, 21, 5);

    test('可解析完整的导出备份', () {
      final book = CustomWordBook(
        id: 'b1',
        name: '我的单词本',
        createdAt: now,
        words: [
          CustomWordEntry(
            word: const Word(
              w: 'apple',
              defs: [WordSense(pos: 'n.', cn: '苹果')],
            ),
            addedAt: now,
          ),
        ],
      );
      final note = NoteRecord(
        id: 'n1',
        wordKey: 'apple',
        title: '苹果',
        content: '注意复数',
        tags: const ['名词'],
        createdAt: now,
        updatedAt: now,
      );
      final state = ReviewState(
        interval: 3,
        reps: 2,
        due: now,
        updatedAt: now,
      );
      final raw = buildJsonExport(
        books: [book],
        notes: [note],
        states: {'apple': state},
        daily: [const DailyStat(date: '2026-11-20', reviews: 4, newWords: 2)],
        now: now,
      );

      final data = parseExportJson(raw);
      expect(data.books.single.words.single.word.w, 'apple');
      expect(data.books.single.words.single.word.primaryDefinition, '苹果');
      expect(data.notes.single.id, 'n1');
      expect(data.notes.single.tags, ['名词']);
      expect(data.states['apple']?.interval, 3);
      expect(data.daily.single.reviews, 4);
      expect(data.daily.single.newWords, 2);
      expect(data.exportedAt, now);
    });

    test('拒绝空内容、非法 JSON、其他应用与过高版本', () {
      expect(() => parseExportJson('  '), throwsFormatException);
      expect(() => parseExportJson('not json'), throwsFormatException);
      expect(
        () => parseExportJson('{"app":"other"}'),
        throwsFormatException,
      );
      expect(
        () => parseExportJson('{"app":"english-study","schema":9}'),
        throwsFormatException,
      );
    });

    test('缺可选字段时解析为空数据而不是报错', () {
      final data = parseExportJson('{"app":"english-study","schema":1}');
      expect(data.isEmpty, isTrue);
      expect(data.notes, isEmpty);
      expect(data.books, isEmpty);
    });
  });

  group('离线词典', () {
    test('紧凑 JSON 解析后可按小写查词', () {
      final repo = DictionaryRepository(
        entries: DictionaryRepository.decode(
          '{"apple":["ˈæpl","n. 苹果"],"look after":["","照顾"]}',
        ),
      );
      expect(repo.lookup(' Apple ')?.phonetic, 'ˈæpl');
      expect(repo.lookup('LOOK AFTER')?.translation, '照顾');
      expect(repo.lookup('missing'), isNull);
    });

    test('缺字段或空释义的条目被忽略', () {
      final entries = DictionaryRepository.decode(
        '{"ok":["p","释义"],"empty":["p"," "],"bad":["p"],"num":[1,2]}',
      );
      expect(entries.keys, ['ok']);
    });

    test('内置词典资源包含常用词', () {
      final raw = File('assets/data/dict_core.json').readAsStringSync();
      final entries = DictionaryRepository.decode(raw);
      expect(entries.length, greaterThan(10000));
      expect(entries['apple']?.phonetic, isNotEmpty);
      expect(entries['apple']?.translation, contains('苹果'));
    });
  });
}
