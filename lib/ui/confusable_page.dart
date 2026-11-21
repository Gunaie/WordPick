import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../domain/confusable_group.dart';
import '../domain/word.dart';
import 'theme.dart';

/// 易混词：把 2–4 个容易混淆的词绑成一组
///
/// 学习时某个成员出现，同组其他词会紧接插入本轮队列，方便连续对比。
class ConfusablePage extends StatelessWidget {
  final AppState state;

  const ConfusablePage({super.key, required this.state});

  Future<void> _edit(BuildContext context, {ConfusableGroup? group}) async {
    if (state.pool.length < 2) return;
    final draft = await showDialog<_GroupDraft>(
      context: context,
      builder: (_) => _GroupEditorDialog(state: state, group: group),
    );
    if (draft == null) return;

    final err = await state.saveConfusableGroup(
      id: group?.id,
      name: draft.name,
      wordKeys: draft.wordKeys,
    );
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _delete(
    BuildContext context,
    ConfusableGroup group,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${group.displayName}」？'),
        content: const Text('只删除分组，不会删除单词本身。'),
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
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await state.deleteConfusableGroup(group.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = state.confusableGroups;
    final canCreate = state.pool.length >= 2;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        colors: kGradients[1],
        child: SafeArea(
          child: Column(
            children: [
              PageHeader(
                title: '易混词',
                subtitle: '同组词会连续出现，对比记忆',
                actions: [
                  IconButton(
                    tooltip: '新建易混组',
                    icon: const Icon(Icons.add),
                    onPressed: canCreate ? () => _edit(context) : null,
                  ),
                ],
              ),
              Expanded(
                child: groups.isEmpty
                    ? _EmptyState(
                        canCreate: canCreate,
                        onCreate: () => _edit(context),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
                        itemCount: groups.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final g = groups[i];
                          return GlassCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            radius: 20,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.compare_arrows_rounded,
                                      color: AppColors.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        g.displayName,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: '更多',
                                      onSelected: (v) {
                                        if (v == 'edit') {
                                          _edit(context, group: g);
                                        } else if (v == 'delete') {
                                          _delete(context, g);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('编辑'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('删除'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final key in g.wordKeys)
                                      _WordChip(
                                        word: state.findWord(key),
                                        fallback: key,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  final Word? word;
  final String fallback;

  const _WordChip({required this.word, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final def = word?.primaryDefinition ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            word?.w ?? fallback,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (def.isNotEmpty)
            Text(
              def,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool canCreate;
  final VoidCallback onCreate;

  const _EmptyState({required this.canCreate, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.compare_arrows_rounded,
              size: 44,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              '还没有易混词组',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              canCreate
                  ? '把拼写或意思相近的词绑在一起，学习时会连续出现。'
                  : '至少先在词单里添加 2 个词，才能创建易混组。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (canCreate) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建易混组'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupDraft {
  final String name;
  final List<String> wordKeys;

  const _GroupDraft({required this.name, required this.wordKeys});
}

/// 新建 / 编辑易混组：名称可选，词必须 2–4 个
class _GroupEditorDialog extends StatefulWidget {
  final AppState state;
  final ConfusableGroup? group;

  const _GroupEditorDialog({required this.state, this.group});

  @override
  State<_GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends State<_GroupEditorDialog> {
  late final TextEditingController _name;
  late final List<String> _selected;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.group?.name ?? '');
    _selected = [
      for (final key in widget.group?.wordKeys ?? const <String>[])
        if (widget.state.findWord(key) != null) key,
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (_) => _WordPickerDialog(
        pool: widget.state.pool,
        initial: _selected,
      ),
    );
    if (picked != null) {
      setState(() {
        _selected
          ..clear()
          ..addAll(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = _selected.length >= 2 && _selected.length <= 4;

    return AlertDialog(
      title: Text(widget.group == null ? '新建易混组' : '编辑易混组'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '组名（可选）',
                hintText: '留空则用单词拼接',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('词组 ${_selected.length} / 4', style: theme.textTheme.labelLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.checklist, size: 18),
                  label: const Text('选择单词'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_selected.isEmpty)
              Text(
                '选择 2–4 个容易混淆的词',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in _selected)
                    Chip(
                      label: Text(widget.state.findWord(key)?.w ?? key),
                      onDeleted: () => setState(() => _selected.remove(key)),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(
                    context,
                    _GroupDraft(
                      name: _name.text,
                      wordKeys: List.of(_selected),
                    ),
                  )
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 从词池里多选 2–4 个词，带搜索
class _WordPickerDialog extends StatefulWidget {
  final List<Word> pool;
  final List<String> initial;

  const _WordPickerDialog({required this.pool, required this.initial});

  @override
  State<_WordPickerDialog> createState() => _WordPickerDialogState();
}

class _WordPickerDialogState extends State<_WordPickerDialog> {
  final TextEditingController _search = TextEditingController();
  late final List<String> _selected = List.of(widget.initial);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(Word word) {
    setState(() {
      if (_selected.contains(word.key)) {
        _selected.remove(word.key);
      } else if (_selected.length >= 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('一组最多 4 个词')),
        );
      } else {
        _selected.add(word.key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final words = query.isEmpty
        ? widget.pool
        : widget.pool.where((w) {
            if (w.key.contains(query)) return true;
            return w.defs.any((d) => d.cn.toLowerCase().contains(query));
          }).toList();

    return AlertDialog(
      title: Text('选择单词（${_selected.length} / 4）'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: '搜索单词或释义',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: words.isEmpty
                  ? const Center(child: Text('没有匹配的词'))
                  : ListView.builder(
                      itemCount: words.length,
                      itemBuilder: (context, i) {
                        final w = words[i];
                        final checked = _selected.contains(w.key);
                        return CheckboxListTile(
                          dense: true,
                          value: checked,
                          onChanged: (_) => _toggle(w),
                          title: Text(w.w),
                          subtitle: w.primaryDefinition.isEmpty
                              ? null
                              : Text(
                                  w.primaryDefinition,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selected.length >= 2
              ? () => Navigator.pop(context, List.of(_selected))
              : null,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
