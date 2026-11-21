/// 用户设置（跨端持久化在本地存储，不参与云同步）
library;

/// 学习相关设置：发音口音、每组新词 / 复习数、每轮拼写题量。
class AppSettings {
  /// true = 英音，false = 美音
  final bool useUkAccent;

  /// 学习页每轮引入的新词数
  final int newWordsPerGroup;

  /// 学习页每轮最多复习的到期词数
  final int reviewWordsPerGroup;

  /// 拼写练习每轮题量
  final int spellingWords;

  /// 复习调度算法：true = FSRS-6（默认），false = SM-2（回滚基线）
  ///
  /// 切换为懒迁移：已有词条下次被评分时才转为 FSRS，旧到期日不受影响；
  /// 切回 SM-2 时 FSRS 字段被忽略，SM-2 字段沿用最后一次的值，可无损回滚。
  final bool useFsrs;

  const AppSettings({
    this.useUkAccent = true,
    this.newWordsPerGroup = 10,
    this.reviewWordsPerGroup = 20,
    this.spellingWords = 10,
    this.useFsrs = true,
  });

  static const int minCount = 5;
  static const int maxCount = 50;
  static const int maxReviewCount = 200;

  /// 可选值，供设置页下拉使用
  static const List<int> countOptions = [5, 10, 15, 20, 30, 50];
  static const List<int> reviewOptions = [10, 20, 30, 50, 100, 200];

  AppSettings copyWith({
    bool? useUkAccent,
    int? newWordsPerGroup,
    int? reviewWordsPerGroup,
    int? spellingWords,
    bool? useFsrs,
  }) =>
      AppSettings(
        useUkAccent: useUkAccent ?? this.useUkAccent,
        newWordsPerGroup: newWordsPerGroup ?? this.newWordsPerGroup,
        reviewWordsPerGroup: reviewWordsPerGroup ?? this.reviewWordsPerGroup,
        spellingWords: spellingWords ?? this.spellingWords,
        useFsrs: useFsrs ?? this.useFsrs,
      );

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        useUkAccent: (j['accent'] as String?)?.toLowerCase() != 'us',
        newWordsPerGroup:
            _clamp((j['new_words_per_group'] as num?)?.toInt() ?? 10),
        reviewWordsPerGroup:
            _clamp((j['review_words_per_group'] as num?)?.toInt() ?? 20,
                max: maxReviewCount),
        spellingWords: _clamp((j['spelling_words'] as num?)?.toInt() ?? 10),
        useFsrs: (j['use_fsrs'] as bool?) ?? true,
      );

  Map<String, dynamic> toJson() => {
        'accent': useUkAccent ? 'uk' : 'us',
        'new_words_per_group': newWordsPerGroup,
        'review_words_per_group': reviewWordsPerGroup,
        'spelling_words': spellingWords,
        'use_fsrs': useFsrs,
      };

  static int _clamp(int v, {int max = maxCount}) => v.clamp(minCount, max);
}
