/// SM-2 间隔重复算法
///
/// 为什么自己实现而不是引第三方包：
/// 1. 逻辑仅约 50 行，完全可控、可测、可读；
/// 2. 避免第三方包版本/维护风险；
/// 3. 后续要换 FSRS 时，只需替换本文件的 [SrsEngine.next] 实现，数据结构不变。
library;

import 'dart:math' as math;

/// 用户对一次复习的反馈
enum ReviewGrade {
  /// 完全想不起来
  again,

  /// 想起来了但很吃力
  hard,

  /// 正常想起
  good,

  /// 秒答
  easy,
}

/// 单个词条的复习状态（会被持久化）
class ReviewState {
  /// SM-2 难度因子，范围 [1.3, 2.8]
  final double ease;

  /// 当前间隔（天）
  final int interval;

  /// 连续答对次数
  final int reps;

  /// 累计遗忘次数
  final int lapses;

  /// 下次复习时间
  final DateTime due;

  /// 最后更新时间（用于跨端合并）
  final DateTime updatedAt;

  const ReviewState({
    this.ease = 2.5,
    this.interval = 0,
    this.reps = 0,
    this.lapses = 0,
    required this.due,
    required this.updatedAt,
  });

  factory ReviewState.initial() {
    final now = DateTime.now();
    return ReviewState(due: now, updatedAt: now);
  }

  bool get isDue => !due.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
        'ease': ease,
        'interval': interval,
        'reps': reps,
        'lapses': lapses,
        'due': due.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ReviewState.fromJson(Map<String, dynamic> j) => ReviewState(
        ease: (j['ease'] as num?)?.toDouble() ?? 2.5,
        interval: (j['interval'] as num?)?.toInt() ?? 0,
        reps: (j['reps'] as num?)?.toInt() ?? 0,
        lapses: (j['lapses'] as num?)?.toInt() ?? 0,
        due: DateTime.tryParse(j['due'] as String? ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class SrsEngine {
  /// SM-2 标准质量分（0-5）映射
  static int _quality(ReviewGrade g) => switch (g) {
        ReviewGrade.again => 0,
        ReviewGrade.hard => 3,
        ReviewGrade.good => 4,
        ReviewGrade.easy => 5,
      };

  /// 计算下一次复习状态
  static ReviewState next(ReviewState cur, ReviewGrade grade) {
    final q = _quality(grade);
    final now = DateTime.now();

    int reps = cur.reps;
    int interval = cur.interval;
    int lapses = cur.lapses;

    if (q < 3) {
      // 忘记：重置进度，10 分钟后重来
      reps = 0;
      lapses += 1;
      interval = 0;
      return ReviewState(
        ease: _clampEase(cur.ease + _easeDelta(q)),
        interval: interval,
        reps: reps,
        lapses: lapses,
        due: now.add(const Duration(minutes: 10)),
        updatedAt: now,
      );
    }

    reps += 1;
    if (reps == 1) {
      interval = 1;
    } else if (reps == 2) {
      interval = 3;
    } else {
      interval = (interval * cur.ease).round().clamp(1, 3650);
    }

    // "hard" 缩短间隔，"easy" 略微延长
    if (grade == ReviewGrade.hard) {
      interval = math.max(1, (interval * 0.7).round());
    } else if (grade == ReviewGrade.easy) {
      interval = (interval * 1.3).round();
    }

    return ReviewState(
      ease: _clampEase(cur.ease + _easeDelta(q)),
      interval: interval,
      reps: reps,
      lapses: lapses,
      due: now.add(Duration(days: interval)),
      updatedAt: now,
    );
  }

  /// SM-2 的 E-Factor 更新公式
  static double _easeDelta(int q) {
    final diff = 5 - q;
    return 0.1 - diff * (0.08 + diff * 0.02);
  }

  static double _clampEase(double v) => v.clamp(1.3, 2.8);
}
