import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../data/sync_config.dart';
import '../domain/word.dart';
import '../services/audio_service.dart';
import 'spelling_page.dart';
import 'stats_page.dart';

/// 「我的」：收藏 / 错题 / 笔记 / 自建词库
class ProfilePage extends StatefulWidget {
  final AppState state;
  const ProfilePage({super.key, required this.state});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final AudioService _audio = AudioService();

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
            child: Row(
              children: [
                Text(
                  '我的',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StatsPage(state: widget.state),
                      ),
                    );
                  },
                  icon: const Icon(Icons.insights, size: 18),
                  label: const Text('学习统计'),
                ),
              ],
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '收藏 ${widget.state.favorites.length}'),
              Tab(text: '错题 ${widget.state.mistakeWords.length}'),
              Tab(text: '笔记 ${widget.state.notes.length}'),
              Tab(text: '自建词 ${widget.state.customWords.length}'),
              const Tab(text: '设置'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _FavoriteTab(state: widget.state, audio: _audio),
                _MistakeTab(state: widget.state, audio: _audio),
                _NotesTab(state: widget.state),
                _CustomTab(state: widget.state),
                _SettingsTab(state: widget.state),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _WordTile extends StatelessWidget {
  final Word word;
  final AudioService audio;
  final Widget? trailing;
  final int? lapses;

  const _WordTile({
    required this.word,
    required this.audio,
    this.trailing,
    this.lapses,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      title: Row(
        children: [
          Flexible(
            child: Text(word.w,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (lapses != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFB26A00).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '遗忘 ×$lapses',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFB26A00),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        word.primaryDefinition,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (word.uk.isNotEmpty)
              TextButton.icon(
                onPressed: () => audio.play(word.w, uk: true),
                icon: const Icon(Icons.volume_up, size: 16),
                label: Text('英 /${word.uk}/'),
              ),
            if (word.us.isNotEmpty)
              TextButton.icon(
                onPressed: () => audio.play(word.w, uk: false),
                icon: const Icon(Icons.volume_up, size: 16),
                label: Text('美 /${word.us}/'),
              ),
          ],
        ),
        for (final d in word.defs)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              d.pos.isEmpty ? d.cn : '[${d.pos}] ${d.cn}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        if (word.ex.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              word.ex.first.en,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _FavoriteTab extends StatelessWidget {
  final AppState state;
  final AudioService audio;
  const _FavoriteTab({required this.state, required this.audio});

  @override
  Widget build(BuildContext context) {
    final list = state.favoriteWords;
    if (list.isEmpty) {
      return const _Empty('还没有收藏的单词。\n在复习卡片右上角点星标即可收藏。');
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final w = list[i];
        return _WordTile(
          word: w,
          audio: audio,
          trailing: IconButton(
            icon: const Icon(Icons.star, color: Color(0xFFE0A800)),
            onPressed: () => state.toggleFavorite(w),
          ),
        );
      },
    );
  }
}

class _MistakeTab extends StatelessWidget {
  final AppState state;
  final AudioService audio;
  const _MistakeTab({required this.state, required this.audio});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = state.mistakeWords;
    if (list.isEmpty) {
      return const _Empty('暂无错题。\n复习时点「重来」的词会自动进入这里。');
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(
                '共 ${list.length} 个 · 按遗忘次数排序',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SpellingPage(
                      state: state,
                      words: list,
                      title: '错题专攻',
                    ),
                  ),
                ),
                icon: const Icon(Icons.spellcheck, size: 18),
                label: const Text('练错题'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final w = list[i];
              return _WordTile(
                word: w,
                audio: audio,
                lapses: state.lapsesFor(w.key),
                trailing: IconButton(
                  tooltip: '移出错题',
                  icon: const Icon(Icons.check_circle_outline),
                  onPressed: () => state.removeFromMistakes(w),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NotesTab extends StatelessWidget {
  final AppState state;
  const _NotesTab({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = state.notes;
    if (notes.isEmpty) {
      return const _Empty('还没有笔记。\n在复习卡片点「记笔记」写点什么吧。');
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: notes.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final n = notes[i];
        final y = n.createdAt.year.toString().padLeft(4, '0');
        final m = n.createdAt.month.toString().padLeft(2, '0');
        final d = n.createdAt.day.toString().padLeft(2, '0');
        return ListTile(
          title: Text(n.wordKey, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(n.content),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$y-$m-$d', style: theme.textTheme.labelSmall),
              IconButton(
                iconSize: 18,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => state.deleteNote(n.id),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CustomTab extends StatefulWidget {
  final AppState state;
  const _CustomTab({required this.state});

  @override
  State<_CustomTab> createState() => _CustomTabState();
}

class _CustomTabState extends State<_CustomTab> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final added = await widget.state.importCustomWords(_input.text);
    if (!mounted) return;
    if (added > 0) {
      _input.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加 $added 个词')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有新增（可能已存在或格式为空）')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = widget.state.customWords;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('粘贴生词', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          '每行一个词，可带释义：\n'
          'serendipity 意外发现\n'
          'resilient, 有韧性的',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _input,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '在此粘贴…',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _import,
          icon: const Icon(Icons.add),
          label: const Text('导入'),
        ),
        const SizedBox(height: 24),
        if (list.isEmpty)
          const _Empty('还没有自建词。')
        else ...[
          Text('已添加 ${list.length} 个', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final w in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(w.w, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(w.primaryDefinition),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => widget.state.removeCustomWord(w),
              ),
            ),
        ],
      ],
    );
  }
}

class _SettingsTab extends StatelessWidget {
  final AppState state;
  const _SettingsTab({required this.state});

  String _syncText() {
    if (!state.syncEnabled) return '未启用';
    final at = state.lastSyncedAt;
    if (state.syncing) return '同步中…';
    if (at == null) return '尚未同步';
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '已同步 · $hh:$mm';
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部数据？'),
        content: const Text(
          '将永久删除本机与云端的：\n'
          '· 全部学习进度\n'
          '· 笔记\n'
          '· 收藏\n'
          '· 自建词\n'
          '· 每日统计\n\n'
          '此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
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
      SnackBar(
        content: Text(
          err == null ? '已清空全部数据' : '本机已清空，但云端清空失败：$err',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text('云端同步', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          child: Column(
            children: [
              ListTile(
                dense: true,
                title: const Text('状态'),
                trailing: Text(_syncText(), style: theme.textTheme.bodySmall),
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
                  title: Text('最近错误',
                      style: TextStyle(color: theme.colorScheme.error)),
                  subtitle: Text(state.syncError!,
                      style: theme.textTheme.labelSmall),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        Text('危险操作', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _confirmReset(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('清空全部数据'),
        ),
        const SizedBox(height: 8),
        Text(
          '会同时清空云端，避免下次同步又把数据拉回来。',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 32),

        Center(
          child: Text(
            '英语学习 v0.6 · 词库 4441 词',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
