import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import 'affix_page.dart';
import 'confusable_page.dart';
import 'notes_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'theme.dart';

/// 「我的」：笔记、词根词缀、学习统计、设置
class ProfilePage extends StatelessWidget {
  final AppState state;

  const ProfilePage({super.key, required this.state});

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBackground(
      colors: kGradients[3],
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 120),
          children: [
            Text(
              '我的',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '笔记、词缀、统计与设置',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            _MenuCard(
              icon: Icons.sticky_note_2_outlined,
              title: '笔记汇总',
              subtitle: '${state.notes.length} 条',
              onTap: () => _push(context, NotesPage(state: state)),
            ),
            const SizedBox(height: 10),
            _MenuCard(
              icon: Icons.hub_outlined,
              title: '词根词缀',
              subtitle: '拆解自建词的前缀 / 词根 / 后缀',
              onTap: () => _push(context, AffixPage(state: state)),
            ),
            const SizedBox(height: 10),
            _MenuCard(
              icon: Icons.compare_arrows_rounded,
              title: '易混词',
              subtitle: state.confusableGroups.isEmpty
                  ? '把容易混的词绑成一组'
                  : '${state.confusableGroups.length} 组',
              onTap: () => _push(context, ConfusablePage(state: state)),
            ),
            const SizedBox(height: 10),
            _MenuCard(
              icon: Icons.insights_outlined,
              title: '学习统计',
              subtitle: '连续 ${state.streakDays} 天 · 已学 ${state.learnedCount} 词',
              onTap: () => _push(context, StatsPage(state: state)),
            ),
            const SizedBox(height: 10),
            _MenuCard(
              icon: Icons.settings_outlined,
              title: '设置',
              subtitle: '同步状态 / 清空数据',
              onTap: () => _push(context, SettingsPage(state: state)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      radius: 20,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
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
