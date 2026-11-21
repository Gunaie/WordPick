import 'dart:math';

import 'package:english_study/domain/affix.dart';
import 'package:english_study/domain/edit_distance.dart';
import 'package:english_study/domain/learning_quiz.dart';
import 'package:english_study/domain/spelling_hints.dart';
import 'package:english_study/domain/srs.dart';
import 'package:english_study/domain/word.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    test('按音节切分常见词', () {
      expect(splitSyllables('predict'), ['pre', 'dict']);
      expect(splitSyllables('inspection'), ['in', 'spec', 'tion']);
      expect(splitSyllables('beautiful'), ['beau', 'ti', 'ful']);
      expect(splitSyllables('apple'), ['ap', 'ple']);
      expect(splitSyllables('table'), ['ta', 'ble']);
      expect(splitSyllables('resilient'), ['re', 'sil', 'ient']);
      expect(splitSyllables('business'), ['busi', 'ness']);
      expect(splitSyllables('people'), ['peo', 'ple']);
      expect(splitSyllables('ubiquitous'), ['u', 'biq', 'ui', 'tous']);
      expect(splitSyllables('make'), ['make']);
      expect(splitSyllables(''), isEmpty);
      expect(splitSyllables('well-known'), isNull);
    });

    test('音节数优先与切分结果一致', () {
      for (final w in [
        'predict',
        'inspection',
        'beautiful',
        'apple',
        'resilient',
      ]) {
        expect(syllableCount(w), splitSyllables(w)!.length, reason: w);
      }
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
}
