/// 学习卡四选一与自动评分（纯 Dart，可单测）
library;

import 'dart:math';

import 'srs.dart';
import 'word.dart';

class QuizOption {
  final String pos;
  final String text;
  final bool isCorrect;

  const QuizOption({
    required this.pos,
    required this.text,
    required this.isCorrect,
  });
}

class QuizQuestion {
  final List<QuizOption> options;

  const QuizQuestion(this.options);
}

/// 至少要有 4 个带释义的词，才能凑出四选一
bool canBuildQuiz(List<Word> pool) =>
    pool.where((w) => w.defs.isNotEmpty && w.defs.first.cn.trim().isNotEmpty).length >= 4;

/// 为 [word] 生成四选一题目；词池不足或无释义时返回 null
QuizQuestion? buildQuiz(Word word, List<Word> pool, {Random? random}) {
  if (word.defs.isEmpty) return null;
  final correctSense = word.defs.first;
  final correct = correctSense.cn.trim();
  if (correct.isEmpty) return null;

  final r = random ?? Random();
  final seen = <String>{correct.toLowerCase()};
  final (pos, text) = (correctSense.pos, correct);

  final samePos = <(String, String)>[];
  final other = <(String, String)>[];
  for (final w in pool) {
    if (w.key == word.key || w.defs.isEmpty) continue;
    final d = w.defs.first;
    final t = d.cn.trim();
    if (t.isEmpty || !seen.add(t.toLowerCase())) continue;
    if (pos.isNotEmpty && d.pos == pos) {
      samePos.add((d.pos, t));
    } else {
      other.add((d.pos, t));
    }
  }

  samePos.shuffle(r);
  other.shuffle(r);
  final picked = <(String, String)>[];
  for (final c in [...samePos, ...other]) {
    if (picked.length == 3) break;
    picked.add(c);
  }
  if (picked.length < 3) return null;

  final options = <QuizOption>[
    QuizOption(pos: pos, text: text, isCorrect: true),
    for (final c in picked) QuizOption(pos: c.$1, text: c.$2, isCorrect: false),
  ]..shuffle(r);

  return QuizQuestion(options);
}

/// 自动评分映射：答错重来；答对一般；答对且已连续答对 3 次以上为简单
ReviewGrade autoGrade({required bool correct, required int reps}) {
  if (!correct) return ReviewGrade.again;
  return reps >= 3 ? ReviewGrade.easy : ReviewGrade.good;
}
