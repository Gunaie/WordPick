/// 间隔重复调度引擎
///
/// 支持两种算法（见 [SrsAlgorithm]）：
///   * [SrsAlgorithm.fsrs] —— FSRS-6（由 fsrs 包提供，默认算法）
///   * [SrsAlgorithm.sm2]  —— 自实现的 SM-2（回滚基线，行为稳定）
///
/// 数据结构向后兼容：SM-2 字段（ease / interval / reps / lapses）始终保留，
/// FSRS 字段（stability / difficulty / fsrsState / fsrsStep / lastReview）
/// 为 null 时表示该词条尚未迁移到 FSRS，仍是纯 SM-2 数据。切换算法不会丢数据，
/// 可随时切回 SM-2（FSRS 字段被忽略，SM-2 字段沿用最后一次的值）。
library;

import 'dart:math' as math;

import 'package:fsrs/fsrs.dart' as fsrs;

/// 可选的复习调度算法
enum SrsAlgorithm {
  /// 自实现 SM-2（回滚基线）
  sm2,

  /// FSRS-6（fsrs 包）
  fsrs,
}

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

/// 单个词条的复习状态（会被持久化 / 云同步 / 导出恢复）
class ReviewState {
  // ── SM-2 字段（始终保留，用于回滚与兼容统计）──
  /// SM-2 难度因子，范围 [1.3, 2.8]
  final double ease;

  /// 当前间隔（天）；FSRS 模式下取 due − lastReview 的天数
  final int interval;

  /// 连续答对次数（FSRS 不提供，自行维护，供评分启发式与统计）
  final int reps;

  /// 累计遗忘次数
  final int lapses;

  // ── 公共字段 ──
  /// 下次复习时间（本地时间）
  final DateTime due;

  /// 最后更新时间（用于跨端合并）
  final DateTime updatedAt;

  // ── FSRS-6 字段（null = 尚未迁移到 FSRS）──
  /// 记忆稳定性（天）
  final double? stability;

  /// 难度 [1, 10]
  final double? difficulty;

  /// FSRS 卡片状态：'learning' / 'review' / 'relearning'
  final String? fsrsState;

  /// 学习 / 重学步骤索引
  final int? fsrsStep;

  /// 上次复习时间（本地时间）
  final DateTime? lastReview;

  const ReviewState({
    this.ease = 2.5,
    this.interval = 0,
    this.reps = 0,
    this.lapses = 0,
    required this.due,
    required this.updatedAt,
    this.stability,
    this.difficulty,
    this.fsrsState,
    this.fsrsStep,
    this.lastReview,
  });

  factory ReviewState.initial() {
    final now = DateTime.now();
    return ReviewState(due: now, updatedAt: now);
  }

  /// 是否已迁移到 FSRS（FSRS 字段非空）
  bool get hasFsrs => stability != null;

  bool get isDue => !due.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
        'ease': ease,
        'interval': interval,
        'reps': reps,
        'lapses': lapses,
        'due': due.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (stability != null) 'stability': stability,
        if (difficulty != null) 'difficulty': difficulty,
        if (fsrsState != null) 'fsrs_state': fsrsState,
        if (fsrsStep != null) 'fsrs_step': fsrsStep,
        if (lastReview != null) 'last_review': lastReview!.toIso8601String(),
      };

  factory ReviewState.fromJson(Map<String, dynamic> j) => ReviewState(
        ease: (j['ease'] as num?)?.toDouble() ?? 2.5,
        interval: (j['interval'] as num?)?.toInt() ?? 0,
        reps: (j['reps'] as num?)?.toInt() ?? 0,
        lapses: (j['lapses'] as num?)?.toInt() ?? 0,
        due: DateTime.tryParse(j['due'] as String? ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
        stability: (j['stability'] as num?)?.toDouble(),
        difficulty: (j['difficulty'] as num?)?.toDouble(),
        fsrsState: j['fsrs_state'] as String?,
        fsrsStep: (j['fsrs_step'] as num?)?.toInt(),
        lastReview: j['last_review'] == null
            ? null
            : DateTime.tryParse(j['last_review'] as String),
      );
}

class SrsEngine {
  /// FSRS-6 调度器。
  ///
  /// 生产默认开启 fuzz（打散到期日，避免所有词挤在同一天）；
  /// 测试可赋值 `SrsEngine.scheduler = Scheduler(enableFuzzing: false)`
  /// 以保证结果可复现。
  static fsrs.Scheduler scheduler = fsrs.Scheduler();

  /// 计算下一次复习状态
  static ReviewState next(
    ReviewState cur,
    ReviewGrade grade, {
    SrsAlgorithm algorithm = SrsAlgorithm.fsrs,
  }) {
    return switch (algorithm) {
      SrsAlgorithm.sm2 => _nextSm2(cur, grade),
      SrsAlgorithm.fsrs => _nextFsrs(cur, grade),
    };
  }

  // ────────────────────────────────────────────────────
  // SM-2（保持原实现，行为不变，作为可回滚的基线）
  // ────────────────────────────────────────────────────

  static int _quality(ReviewGrade g) => switch (g) {
        ReviewGrade.again => 0,
        ReviewGrade.hard => 3,
        ReviewGrade.good => 4,
        ReviewGrade.easy => 5,
      };

  static ReviewState _nextSm2(ReviewState cur, ReviewGrade grade) {
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
        // 切回 SM-2 时不携带 FSRS 字段，保持纯 SM-2 数据
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

  static double _easeDelta(int q) {
    final diff = 5 - q;
    return 0.1 - diff * (0.08 + diff * 0.02);
  }

  static double _clampEase(double v) => v.clamp(1.3, 2.8);

  // ────────────────────────────────────────────────────
  // FSRS-6
  // ────────────────────────────────────────────────────

  static fsrs.Rating _toRating(ReviewGrade g) => switch (g) {
        ReviewGrade.again => fsrs.Rating.again,
        ReviewGrade.hard => fsrs.Rating.hard,
        ReviewGrade.good => fsrs.Rating.good,
        ReviewGrade.easy => fsrs.Rating.easy,
      };

  /// 懒迁移：把 SM-2 状态映射为 FSRS 初始参数。
  ///
  /// 只在「从未评分的新词」之外的已有词条首次走 FSRS 时调用：
  ///   * stability  ≈ 当前间隔（天），最小 1
  ///   * difficulty 从 ease 反推：ease 2.5 → 5.0（默认），ease 越高越易 → difficulty 越低
  ///   * state      = review（已学过的词视为复习卡）
  static ({double stability, double difficulty, fsrs.State state}) _fromSm2(
    ReviewState cur,
  ) {
    final stability = cur.interval > 0 ? cur.interval.toDouble() : 1.0;
    final difficulty = (5.0 + (2.5 - cur.ease) * 6.0).clamp(1.0, 10.0);
    return (
      stability: stability,
      difficulty: difficulty,
      state: fsrs.State.review,
    );
  }

  static ReviewState _nextFsrs(ReviewState cur, ReviewGrade grade) {
    final now = DateTime.now();
    final nowUtc = now.toUtc();

    // 从未评分的新词：让 FSRS 用默认 Card（走 learning 学习步，10min→4d…）
    final isNew = cur.interval == 0 && cur.reps == 0;
    final converted = isNew ? null : _fromSm2(cur);
    final hasFsrs = cur.hasFsrs;

    final card = fsrs.Card(
      cardId: 0,
      state: isNew
          ? fsrs.State.learning
          : hasFsrs
              ? _parseState(cur.fsrsState)
              : converted!.state,
      step: isNew ? null : cur.fsrsStep,
      stability: isNew
          ? null
          : hasFsrs
              ? cur.stability
              : converted!.stability,
      difficulty: isNew
          ? null
          : hasFsrs
              ? cur.difficulty
              : converted!.difficulty,
      due: cur.due.toUtc(),
      lastReview: (cur.lastReview ?? cur.updatedAt).toUtc(),
    );

    // 时区边界：传入 UTC，取回的 due / lastReview 是 UTC，转本地存储，
    // 这样 isDue（本地 now 比较）与现有数据零偏移。
    final result =
        scheduler.reviewCard(card, _toRating(grade), reviewDateTime: nowUtc);
    final next = result.card;

    final lastReviewLocal = next.lastReview?.toLocal() ?? now;
    final dueLocal = next.due.toLocal();
    final intervalDays = dueLocal.difference(lastReviewLocal).inDays;

    // 维护 SM-2 兼容字段：reps / lapses / interval，供统计与回滚
    final isAgain = grade == ReviewGrade.again;
    final newReps = isAgain ? 0 : cur.reps + 1;
    final newLapses = isAgain ? cur.lapses + 1 : cur.lapses;

    return ReviewState(
      ease: cur.ease, // SM-2 字段冻结，回滚时沿用最后值
      interval: intervalDays < 0 ? 0 : intervalDays,
      reps: newReps,
      lapses: newLapses,
      due: dueLocal,
      updatedAt: now,
      stability: next.stability,
      difficulty: next.difficulty,
      fsrsState: next.state.name,
      fsrsStep: next.step,
      lastReview: lastReviewLocal,
    );
  }

  static fsrs.State _parseState(String? name) {
    if (name == null) return fsrs.State.review;
    for (final s in fsrs.State.values) {
      if (s.name == name) return s;
    }
    return fsrs.State.review;
  }
}
