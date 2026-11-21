import 'package:english_study/data/app_settings.dart';
import 'package:english_study/data/daily_stat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  group('学习设置', () {
    test('默认英音、每组新词 10、每组复习 20、拼写 10 题、FSRS-6 调度', () {
      const s = AppSettings();
      expect(s.useUkAccent, isTrue);
      expect(s.newWordsPerGroup, 10);
      expect(s.reviewWordsPerGroup, 20);
      expect(s.spellingWords, 10);
      expect(s.useFsrs, isTrue);
    });

    test('显式选择 SM-2 可持久化并回滚', () {
      const s = AppSettings(useFsrs: false);
      expect(AppSettings.fromJson(s.toJson()).useFsrs, isFalse);
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
      expect(empty.useFsrs, isTrue);
    });
  });
}
