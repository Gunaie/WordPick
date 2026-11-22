import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import 'learning_page.dart';
import 'settings_page.dart';
import 'spelling_page.dart';
import 'stats_page.dart';
import 'theme.dart';

/// 今日：签到、今日数字、开始学习、拼写入口
class TodayPage extends StatelessWidget {
  final AppState state;
  final VoidCallback onGoBooks;

  const TodayPage({super.key, required this.state, required this.onGoBooks});

  void _openLearning(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LearningPage(state: state)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBooks = state.customBooks.isNotEmpty;
    final hasWords = state.pool.isNotEmpty;
    final due = state.dueCount;

    return AppBackground(
      colors: kGradients[0],
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 120),
          children: [
            Row(
              children: [
                Text(
                  '拾词',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '设置',
                  color: Colors.white.withValues(alpha: 0.9),
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsPage(state: state),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CheckInCard(state: state),
            const SizedBox(height: 28),

            if (!hasBooks) ...[
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('还没有单词本', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '先创建一本自己的单词本，再添加想学的词。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: onGoBooks,
                      child: const Text('创建第一本词书'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _NumberBlock(
                      label: '待复习',
                      value: '$due',
                      color: AppColors.accent,
                      onTap: hasWords ? () => _openLearning(context) : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _NumberBlock(
                      label: '今日已学',
                      value: '${state.todayLearnedCount}',
                      color: AppColors.primary,
                      onTap: hasWords ? () => _openLearning(context) : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: hasWords ? () => _openLearning(context) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  due > 0 ? '开始复习' : '开始学习',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              if (!hasWords) ...[
                const SizedBox(height: 10),
                Text(
                  '单词本里还没有词，去「词单」添加几个吧。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SpellingPage(state: state),
                  ),
                ),
                child: Text(
                  '拼写练习',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CheckInCard extends StatelessWidget {
  final AppState state;
  const _CheckInCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final date = '${now.month}/${now.day} ${weekdays[now.weekday - 1]}';
    final streak = state.streakDays;

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StatsPage(state: state)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              state.studiedToday
                  ? Icons.check_circle_rounded
                  : Icons.wb_sunny_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('签到', style: theme.textTheme.titleMedium),
                    const SizedBox(width: 8),
                    Text(
                      date,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  state.studiedToday ? '连续 $streak 天' : '今天还没开始',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _NumberBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _NumberBlock({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 22),
      onTap: onTap,
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w600,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
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
