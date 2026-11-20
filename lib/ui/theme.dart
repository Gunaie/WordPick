/// 视觉基础：配色、渐变背景、磨砂卡片
library;

import 'dart:ui';

import 'package:material_ui/material_ui.dart';

class AppColors {
  static const text = Color(0xFF2B2825);
  static const textSecondary = Color(0xFF6F6A63);
  static const textMuted = Color(0xFF9A948C);
  static const primary = Color(0xFF2F6F63);
  static const accent = Color(0xFFC4763F);
  static const danger = Color(0xFFB4544A);
}

/// 预设背景渐变（晨雾 / 苔绿 / 雾蓝 / 暮粉）
const List<List<Color>> kGradients = [
  [Color(0xFFFBF7F1), Color(0xFFEFE6D8)],
  [Color(0xFFEDF3EE), Color(0xFFD8E7DE)],
  [Color(0xFFEBF1F6), Color(0xFFDCE8F1)],
  [Color(0xFFFBF1EE), Color(0xFFF0DFDA)],
];

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    surface: const Color(0xFFFBF7F1),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFFBF7F1),
    textTheme: const TextTheme().apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
  );
}

/// 全屏渐变背景
class AppBackground extends StatelessWidget {
  final List<Color> colors;
  final Widget child;

  const AppBackground({
    super.key,
    this.colors = const [Color(0xFFFBF7F1), Color(0xFFEFE6D8)],
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: child,
    );
  }
}

/// 二级页面统一头部：可选返回键 + 标题 + 副标题 + 右侧操作
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBack;
  final List<Widget> actions;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = true,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(showBack ? 6 : 22, 12, 14, 8),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// 磨砂玻璃卡片
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.white.withValues(alpha: 0.62),
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
