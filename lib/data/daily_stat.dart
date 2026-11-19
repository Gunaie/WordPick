/// 每日学习记录（用于统计与连续天数）
library;

class DailyStat {
  /// yyyy-MM-dd
  final String date;
  final int reviews;
  final int newWords;

  const DailyStat({
    required this.date,
    this.reviews = 0,
    this.newWords = 0,
  });

  int get total => reviews;

  Map<String, dynamic> toJson() => {'r': reviews, 'n': newWords};

  factory DailyStat.fromJson(String date, Map<String, dynamic> j) => DailyStat(
        date: date,
        reviews: (j['r'] as num?)?.toInt() ?? 0,
        newWords: (j['n'] as num?)?.toInt() ?? 0,
      );
}

/// 把 DateTime 转成 yyyy-MM-dd
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 计算连续学习天数（截至今天；若今天还没学，则从昨天往前算）
int streakOf(List<DailyStat> stats, {DateTime? now}) {
  final active = stats.where((s) => s.reviews > 0).map((s) => s.date).toSet();
  if (active.isEmpty) return 0;

  final today = now ?? DateTime.now();
  var cursor = DateTime(today.year, today.month, today.day);

  // 今天没学不算断，从昨天开始数
  if (!active.contains(dayKey(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
    if (!active.contains(dayKey(cursor))) return 0;
  }

  var streak = 0;
  while (active.contains(dayKey(cursor))) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}
