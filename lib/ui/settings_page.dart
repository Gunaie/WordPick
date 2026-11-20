import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../data/app_settings.dart';
import '../data/daily_stat.dart';
import '../data/sync_config.dart';
import '../domain/export_builder.dart';
import '../domain/export_import.dart';
import '../services/audio_cache.dart';
import '../services/export_service.dart';
import 'theme.dart';

/// 设置：同步、发音缓存、数据导出与清理、关于
class SettingsPage extends StatefulWidget {
  final AppState state;

  const SettingsPage({super.key, required this.state});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int? _cacheBytes;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final bytes = await audioCache.sizeBytes();
    if (mounted) setState(() => _cacheBytes = bytes);
  }

  String _syncText() {
    if (!state.syncEnabled) return '未启用';
    final at = state.lastSyncedAt;
    if (state.syncing) return '同步中…';
    if (at == null) return '尚未同步';
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '已同步 · $hh:$mm';
  }

  String _fmtBytes(int? bytes) {
    if (bytes == null) return '计算中…';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _exportJson() async {
    final now = DateTime.now();
    final content = buildJsonExport(
      books: state.customBooks,
      notes: state.notes,
      states: state.states,
      daily: state.dailyStats,
      now: now,
    );
    await _save(
      fileName: 'english-study-${dayKey(now)}.json',
      content: content,
      mimeType: 'application/json',
    );
  }

  Future<void> _exportMarkdown() async {
    final now = DateTime.now();
    final content = buildNotesMarkdown(notes: state.notes, now: now);
    await _save(
      fileName: 'notes-${dayKey(now)}.md',
      content: content,
      mimeType: 'text/markdown',
    );
  }

  Future<void> _restoreFromJson() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('从 JSON 恢复'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '把导出的 english-study-*.json 文件内容粘贴到这里。\n'
              '恢复采用合并方式，不会删除现有数据。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: '在此粘贴备份 JSON…',
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = data?.text;
                  if (text != null && text.trim().isNotEmpty) {
                    controller.text = text;
                  }
                },
                icon: const Icon(Icons.content_paste, size: 16),
                label: const Text('从剪贴板粘贴'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('下一步'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null || raw.trim().isEmpty) return;

    final ImportedData data;
    try {
      data = parseExportJson(raw);
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法读取备份：${e.message}')));
      return;
    }

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('确认恢复'),
        content: Text(
          '备份包含：${data.books.length} 本词书、'
          '${data.books.fold<int>(0, (n, b) => n + b.words.length)} 个词、'
          '${data.notes.length} 条笔记、${data.states.length} 个复习状态、'
          '${data.daily.length} 天学习记录。\n\n'
          '将与现有数据合并：词按拼写去重，笔记与进度以较新者为准。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始恢复'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final report = await state.restoreFromJson(raw);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(report.hasChanges ? report.summary : '没有需要恢复的新数据'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('恢复失败：$e')));
    }
  }

  Future<void> _save({
    required String fileName,
    required String content,
    required String mimeType,
  }) async {
    try {
      final msg = await saveExport(
        fileName: fileName,
        content: content,
        mimeType: mimeType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('清理发音缓存？'),
        content: const Text('已缓存的 mp3 会被删除，需要时重新联网下载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await audioCache.clear();
    await _loadCacheSize();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已清理发音缓存')));
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('清空全部数据？'),
        content: const Text(
          '将永久删除本机与云端的：\n'
          '· 全部学习进度\n'
          '· 笔记\n'
          '· 自建单词本\n'
          '· 每日统计\n\n'
          '此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await state.resetAll();
    if (!context.mounted) return;
    final err = state.syncError;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err == null ? '已清空全部数据' : '本机已清空，但云端清空失败：$err')),
    );
  }

  Widget _countDropdown(
    int value,
    Future<void> Function(int) onChanged, {
    List<int> options = AppSettings.countOptions,
  }) {
    // 兼容手工改过的本地设置：把当前值并入选项，避免 Dropdown 断言失败
    final all = ({...options, value}.toList()..sort());
    return DropdownButton<int>(
      value: value,
      underline: const SizedBox.shrink(),
      items: [
        for (final v in all) DropdownMenuItem(value: v, child: Text('$v')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
      height: 1.5,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        colors: kGradients[2],
        child: SafeArea(
          child: Column(
            children: [
              const PageHeader(title: '设置', subtitle: '仅本人使用，不做账号体系'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
                  children: [
                    Text('云端同步', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      radius: 20,
                      child: Column(
                        children: [
                          ListTile(
                            dense: true,
                            title: const Text('状态'),
                            subtitle: Text(
                              '启动与回到前台时自动同步（1 分钟内不重复）',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                            trailing: Text(
                              _syncText(),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          ListTile(
                            dense: true,
                            title: const Text('环境'),
                            trailing: Text(
                              SyncConfig.envId,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          ListTile(
                            dense: true,
                            title: const Text('用户标识'),
                            trailing: Text(
                              SyncConfig.userId,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          if (state.syncError != null)
                            ListTile(
                              dense: true,
                              title: Text(
                                '最近错误',
                                style: TextStyle(color: AppColors.danger),
                              ),
                              subtitle: Text(
                                state.syncError!,
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                          if (state.syncEnabled)
                            ListTile(
                              dense: true,
                              title: const Text('立即同步'),
                              trailing: state.syncing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.sync,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                              onTap: state.syncing
                                  ? null
                                  : () async {
                                      await state.syncNow();
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                state.syncError == null
                                                    ? '同步完成'
                                                    : '同步失败：${state.syncError}',
                                              ),
                                            ),
                                          );
                                    },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('学习', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      radius: 20,
                      child: Column(
                        children: [
                          ListTile(
                            dense: true,
                            title: const Text('发音口音'),
                            subtitle: Text(
                              '影响单词发音与设备 TTS',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                            trailing: DropdownButton<bool>(
                              value: state.settings.useUkAccent,
                              underline: const SizedBox.shrink(),
                              items: const [
                                DropdownMenuItem(value: true, child: Text('英音')),
                                DropdownMenuItem(
                                  value: false,
                                  child: Text('美音'),
                                ),
                              ],
                              onChanged: (v) async {
                                if (v == null) return;
                                await state.updateSettings(
                                  state.settings.copyWith(useUkAccent: v),
                                );
                              },
                            ),
                          ),
                          ListTile(
                            dense: true,
                            title: const Text('每组新词'),
                            subtitle: Text(
                              '学习页每轮引入的新词数',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                            trailing: _countDropdown(
                              state.settings.newWordsPerGroup,
                              (v) => state.updateSettings(
                                state.settings.copyWith(newWordsPerGroup: v),
                              ),
                            ),
                          ),
                          ListTile(
                            dense: true,
                            title: const Text('每组复习'),
                            subtitle: Text(
                              '每轮最多复习的到期词数',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                            trailing: _countDropdown(
                              state.settings.reviewWordsPerGroup,
                              (v) => state.updateSettings(
                                state.settings
                                    .copyWith(reviewWordsPerGroup: v),
                              ),
                              options: AppSettings.reviewOptions,
                            ),
                          ),
                          ListTile(
                            dense: true,
                            title: const Text('拼写题量'),
                            subtitle: Text(
                              '拼写练习每轮题目数',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                            trailing: _countDropdown(
                              state.settings.spellingWords,
                              (v) => state.updateSettings(
                                state.settings.copyWith(spellingWords: v),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('发音', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      radius: 20,
                      child: Column(
                        children: [
                          ListTile(
                            dense: true,
                            title: const Text('发音缓存'),
                            subtitle: Text(
                              '已缓存的单词可直接离线播放',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _fmtBytes(_cacheBytes),
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: _cacheBytes == 0
                                      ? null
                                      : _clearCache,
                                  child: const Text('清理'),
                                ),
                              ],
                            ),
                          ),
                          ListTile(
                            dense: true,
                            title: const Text('网络失败时'),
                            trailing: Text(
                              '设备 TTS 朗读',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('数据', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      radius: 20,
                      child: Column(
                        children: [
                          ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.settings_backup_restore,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            title: const Text('从 JSON 恢复'),
                            subtitle: Text(
                              '粘贴导出的备份内容，合并到现有数据',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                            onTap: _restoreFromJson,
                          ),
                          ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.data_object,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            title: const Text('导出 JSON'),
                            subtitle: Text(
                              '词书、笔记、复习进度与每日统计',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                            onTap: _exportJson,
                          ),
                          ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.description_outlined,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            title: const Text('导出笔记 Markdown'),
                            subtitle: Text(
                              '按单词分组，便于阅读与归档',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                            onTap: _exportMarkdown,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _confirmReset(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: BorderSide(
                                color: AppColors.danger.withValues(alpha: 0.5),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              minimumSize: const Size.fromHeight(0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            icon: const Icon(Icons.delete_forever_outlined),
                            label: const Text('清空全部数据'),
                          ),
                          const SizedBox(height: 10),
                          Text('会同时清空云端，避免下次同步又把数据拉回来。', style: caption),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('关于', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      radius: 20,
                      child: Column(
                        children: [
                          ListTile(
                            dense: true,
                            title: const Text('版本'),
                            trailing: Text(
                              'v0.14',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          ListTile(
                            dense: true,
                            title: const Text('单词本'),
                            trailing: Text(
                              '${state.customBooks.length} 本',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          ListTile(
                            dense: true,
                            title: const Text('总词数'),
                            trailing: Text(
                              '${state.pool.length} 词',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
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
