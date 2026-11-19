import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../data/daily_stat.dart';

/// 学习统计
class StatsPage extends StatelessWidget {
  final AppState state;
  const StatsPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daily = state.dailyStats;
    final byDate = {for (final d in daily) d.date: d};

    // 近 14 天（按日期升序）
    final today = DateTime.now();
    final days = <DailyStat>[];
    for (var i = 13; i >= 0; i--) {
      final d = DateTime(today.year, today.month, today.day - i);
      final key = dayKey(d);
      days.add(byDate[key] ?? DailyStat(date: key));
    }
    final maxReviews =
        days.map((d) => d.reviews).fold<int>(0, (a, b) => math.max(a, b));

    int countByTag(String tag) {
      var n = 0;
      for (final k in state.states.keys) {
        final w = state.findWord(k);
        if (w != null && w.tags.contains(tag)) n++;
      }
      return n;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('学习统计')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Row(
            children: [
              _Metric(label: '已学', value: '${state.learnedCount}'),
              const SizedBox(width: 10),
              _Metric(label: '待复习', value: '${state.dueCount}', accent: true),
              const SizedBox(width: 10),
              _Metric(label: '熟记', value: '${state.masteredCount}'),
              const SizedBox(width: 10),
              _Metric(label: '连续', value: '${state.streakDays}天'),
            ],
          ),
          const SizedBox(height: 24),

          Text('最近 14 天', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '今日复习 ${state.todayReviews} 次',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              d.reviews == 0 ? '' : '${d.reviews}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontSize: 9,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              height: maxReviews == 0
                                  ? 3
                                  : 4 + (d.reviews / maxReviews) * 60,
                              decoration: BoxDecoration(
                                color: d.reviews == 0
                                    ? theme.colorScheme.outlineVariant
                                    : theme.colorScheme.primary
                                        .withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              d.date.substring(8),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 9,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          Text('已学构成', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _TagRow(label: '四级', count: countByTag('cet4')),
          _TagRow(label: '六级', count: countByTag('cet6')),
          _TagRow(label: '考研', count: countByTag('kaoyan')),
          _TagRow(label: '自建词', count: countByTag('custom')),
          const SizedBox(height: 24),

          Text('我的内容', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              _Metric(label: '收藏', value: '${state.favorites.length}'),
              const SizedBox(width: 10),
              _Metric(label: '错题', value: '${state.mistakeWords.length}'),
              const SizedBox(width: 10),
              _Metric(label: '笔记', value: '${state.notes.length}'),
              const SizedBox(width: 10),
              _Metric(label: '自建词', value: '${state.customWords.length}'),
            ],
          ),
          const SizedBox(height: 28),

          Text(
            '说明：熟记指复习间隔已达 21 天以上；'
            '每日次数从本次改版后开始累计，之前的记录无法回溯。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  const _Metric({required this.label, required this.value, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: accent
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: accent ? theme.colorScheme.onPrimaryContainer : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent ? theme.colorScheme.onPrimaryContainer : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  final String label;
  final int count;
  const _TagRow({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label, style: theme.textTheme.bodyMedium)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: count == 0 ? 0 : (count / 500).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('$count', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
