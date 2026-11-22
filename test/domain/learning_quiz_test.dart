import 'dart:math';

import 'package:english_study/domain/learning_quiz.dart';
import 'package:english_study/domain/word.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dueLabel', () {
    final now = DateTime(2026, 11, 22, 9);

    test('当天或已到期显示「今天复习」', () {
      expect(dueLabel(now.add(const Duration(hours: 2)), now: now), '今天复习');
      expect(
        dueLabel(now.subtract(const Duration(hours: 5)), now: now),
        '今天复习',
      );
    });

    test('一天后显示「1 天后复习」', () {
      expect(dueLabel(now.add(const Duration(days: 1)), now: now), '1 天后复习');
    });

    test('多天按整天数显示', () {
      expect(dueLabel(now.add(const Duration(days: 26)), now: now), '26 天后复习');
    });
  });

  group('buildQuiz 多释义轮换', () {
    final target = Word(w: 'apple', defs: const [
      WordSense(pos: 'n.', cn: '苹果'),
      WordSense(pos: 'n.', cn: '苹果公司'),
    ]);
    final pool = [
      target,
      Word(w: 'book', defs: const [WordSense(pos: 'n.', cn: '书')]),
      Word(w: 'pen', defs: const [WordSense(pos: 'n.', cn: '笔')]),
      Word(w: 'desk', defs: const [WordSense(pos: 'n.', cn: '桌子')]),
    ];

    test('正确选项必为该词的某条释义', () {
      final q = buildQuiz(target, pool, random: Random(1))!;
      final correct = q.options.firstWhere((o) => o.isCorrect).text;
      expect(target.defs.map((d) => d.cn), contains(correct));
    });

    test('多次出题能覆盖到不同释义（按释义轮换）', () {
      final r = Random(42);
      final seen = <String>{};
      for (var i = 0; i < 40; i++) {
        final q = buildQuiz(target, pool, random: r)!;
        seen.add(q.options.firstWhere((o) => o.isCorrect).text);
      }
      expect(seen, containsAll(['苹果', '苹果公司']));
    });
  });
}
