import 'package:english_study/domain/learning_quiz.dart';
import 'package:english_study/domain/srs.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 关闭 fuzz，保证测试可复现
  setUpAll(() {
    SrsEngine.scheduler = fsrs.Scheduler(enableFuzzing: false);
  });

  /// 把状态拨到「现在正好到期」：lastReview = now − interval，due = now。
  /// 模拟真实「准时复习」节奏（FSRS 对提前很久复习会抑制间隔增长）。
  ReviewState onTime(ReviewState s) {
    final now = DateTime.now();
    return ReviewState(
      ease: s.ease,
      interval: s.interval,
      reps: s.reps,
      lapses: s.lapses,
      due: now,
      updatedAt: now,
      stability: s.stability,
      difficulty: s.difficulty,
      fsrsState: s.fsrsState,
      fsrsStep: s.fsrsStep,
      lastReview: now.subtract(Duration(days: s.interval)),
    );
  }

  ReviewState fsrsNext(ReviewState s, ReviewGrade g) =>
      SrsEngine.next(s, g, algorithm: SrsAlgorithm.fsrs);

  test('FSRS-6 新词连续 good：状态推进、间隔递增、填充 FSRS 字段', () {
    var s = onTime(ReviewState.initial());

    s = fsrsNext(s, ReviewGrade.good); // 第一步：learning（约 10 分钟）
    expect(s.hasFsrs, isTrue);
    expect(s.fsrsState, 'learning');
    expect(s.stability, isNotNull);
    expect(s.difficulty, isNotNull);
    expect(s.interval, 0); // 10 分钟 < 1 天

    s = fsrsNext(onTime(s), ReviewGrade.good); // 第二步：毕业到复习，约 4 天
    expect(s.fsrsState, 'review');
    expect(s.interval, greaterThanOrEqualTo(3));
    final gradInterval = s.interval;

    s = fsrsNext(onTime(s), ReviewGrade.good);
    expect(s.interval, greaterThan(gradInterval)); // 间隔持续增长
  });

  test('FSRS-6 again 后进入 relearning、重置 reps、累加 lapses', () {
    var s = onTime(ReviewState.initial());
    s = fsrsNext(s, ReviewGrade.good);
    s = fsrsNext(onTime(s), ReviewGrade.good);
    expect(s.reps, greaterThan(0));
    final prevInterval = s.interval;

    s = fsrsNext(onTime(s), ReviewGrade.again);
    expect(s.fsrsState, 'relearning');
    expect(s.reps, 0);
    expect(s.lapses, 1);
    expect(s.interval, lessThan(prevInterval));
  });

  test('FSRS-6 懒迁移：纯 SM-2 状态首次评分后获得 FSRS 字段', () {
    final now = DateTime.now();
    final sm2 = ReviewState(
      ease: 2.5,
      interval: 8,
      reps: 3,
      lapses: 0,
      due: now,
      updatedAt: now.subtract(const Duration(days: 8)),
    );
    expect(sm2.hasFsrs, isFalse);

    final s = fsrsNext(sm2, ReviewGrade.good);
    expect(s.hasFsrs, isTrue);
    expect(s.stability, greaterThan(0));
    expect(s.interval, greaterThan(8)); // 迁移后 good 应拉长间隔
  });

  test('FSRS-6 与 SM-2 对同一序列给出不同结果（非同一实现）', () {
    var a = onTime(ReviewState.initial());
    var b = onTime(ReviewState.initial());
    for (var i = 0; i < 4; i++) {
      a = SrsEngine.next(onTime(a), ReviewGrade.good,
          algorithm: SrsAlgorithm.sm2);
      b = fsrsNext(onTime(b), ReviewGrade.good);
    }
    // 跳过前期 learning 步差异后，FSRS 间隔应明显大于 SM-2
    expect(b.interval, greaterThan(a.interval));
  });

  test('SM-2 路径不写入 FSRS 字段（保持纯 SM-2 数据，可回滚）', () {
    final s = SrsEngine.next(
      ReviewState.initial(),
      ReviewGrade.good,
      algorithm: SrsAlgorithm.sm2,
    );
    expect(s.hasFsrs, isFalse);
    expect(s.stability, isNull);
    expect(s.fsrsState, isNull);
  });

  test('ReviewState JSON 往返保留 FSRS 字段', () {
    final s = fsrsNext(onTime(ReviewState.initial()), ReviewGrade.good);
    final s2 = ReviewState.fromJson(s.toJson());
    expect(s2.hasFsrs, s.hasFsrs);
    expect(s2.stability, s.stability);
    expect(s2.difficulty, s.difficulty);
    expect(s2.fsrsState, s.fsrsState);
    expect(s2.fsrsStep, s.fsrsStep);
    expect(s2.interval, s.interval);
    expect(s2.reps, s.reps);
  });

  test('autoGrade：FSRS 模式答对一律 good，SM-2 模式 reps≥3 仍 easy', () {
    expect(autoGrade(correct: true, reps: 5, useFsrs: true), ReviewGrade.good);
    expect(autoGrade(correct: false, reps: 5, useFsrs: true), ReviewGrade.again);
    expect(autoGrade(correct: true, reps: 5, useFsrs: false), ReviewGrade.easy);
    expect(autoGrade(correct: true, reps: 1, useFsrs: false), ReviewGrade.good);
  });
}
