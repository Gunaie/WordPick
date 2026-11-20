import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../data/daily_stat.dart';
import 'theme.dart';

/// 学习统计：连续天数、14 天柱状图、内容概览
class StatsPage extends StatelessWidget {
  final AppState state;
  const StatsPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byDate = {for (final d in state.dailyStats) d.date: d};

    // 近 14 天（按日期升序）
    final today = DateTime.now();
    final days = <DailyStat>[];
    for (var i = 13; i >= 0; i--) {
      final d = DateTime(today.year, today.month, today.day - i);
      days.add(byDate[dayKey(d)] ?? DailyStat(date: dayKey(d)));
    }
    final maxReviews =
        days.map((d) => d.reviews).fold<int>(0, (a, b) => math.max(a, b));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        colors: kGradients[2],
        child: SafeArea(
          child: Column(
            children: [
              PageHeader(
                title: '学习统计',
                subtitle: '今日学习 ${state.todayReviews} 次',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
                  children: [
                    GlassCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 20,
                      ),
                      child: Row(
                        children: [
                          _Metric(
                            label: '连续天数',
                            value: '${state.streakDays}',
                            unit: '天',
                            color: AppColors.accent,
                          ),
                          _Metric(
                            label: '累计已学',
                            value: '${state.learnedCount}',
                            unit: '词',
                            color: AppColors.primary,
                          ),
                          _Metric(
                            label: '今日已学',
                            value: '${state.todayLearnedCount}',
                            unit: '词',
                            color: AppColors.text,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text('最近 14 天', style: theme.textTheme.titleSmall),
                        const Spacer(),
                        _LegendDot(color: AppColors.accent, label: '新学'),
                        const SizedBox(width: 12),
                        _LegendDot(
                          color: AppColors.primary.withValues(alpha: 0.6),
                          label: '复习',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GlassCard(
                      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                      child: SizedBox(
                        height: 130,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final d in days)
                              Expanded(
                                child: _Bar(
                                  stat: d,
                                  maxReviews: maxReviews,
                                  isToday: d.date == dayKey(today),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('我的内容', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 10),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 20,
                      ),
                      child: Row(
                        children: [
                          _Metric(
                            label: '笔记',
                            value: '${state.notes.length}',
                            unit: '条',
                            color: AppColors.text,
                          ),
                          _Metric(
                            label: '单词本',
                            value: '${state.customBooks.length}',
                            unit: '本',
                            color: AppColors.primary,
                          ),
                          _Metric(
                            label: '自建词',
                            value: '${state.customWords.length}',
                            unit: '词',
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '签到由每日学习记录派生：当天学习至少 1 个词即算签到。'
                      '熟记指复习间隔已达 21 天以上。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final DailyStat stat;
  final int maxReviews;
  final bool isToday;

  const _Bar({
    required this.stat,
    required this.maxReviews,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const maxHeight = 82.0;
    final ratio = maxReviews == 0 ? 0.0 : stat.reviews / maxReviews;
    final barHeight = stat.reviews == 0 ? 3.0 : 4 + ratio * maxHeight;
    final newHeight =
        maxReviews == 0 ? 0.0 : (stat.newWords / maxReviews) * maxHeight;
    final reviewHeight = math.max(0.0, barHeight - newHeight);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            stat.reviews == 0 ? '' : '${stat.reviews}',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              color: isToday ? AppColors.accent : AppColors.textMuted,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: barHeight,
              child: stat.reviews == 0
                  ? Container(color: AppColors.textMuted.withValues(alpha: 0.18))
                  : Column(
                      children: [
                        if (reviewHeight > 0)
                          Container(
                            height: reviewHeight,
                            color: AppColors.primary.withValues(alpha: 0.55),
                          ),
                        if (newHeight > 0)
                          Container(
                            height: newHeight,
                            color: AppColors.accent.withValues(alpha: 0.8),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            stat.date.substring(8),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              color: isToday ? AppColors.text : AppColors.textMuted,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _Metric({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text.rich(
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              children: [
                TextSpan(
                  text: ' $unit',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}
