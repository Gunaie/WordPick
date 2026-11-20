import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../data/note_record.dart';
import 'theme.dart';

/// 笔记：时间线小记，支持标题、标签与可选单词关联
class NotesPage extends StatefulWidget {
  final AppState state;

  const NotesPage({super.key, required this.state});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NoteDraft {
  final String title;
  final String content;
  final List<String> tags;
  final String wordKey;

  const _NoteDraft(this.title, this.content, this.tags, this.wordKey);
}

class _NotesPageState extends State<NotesPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _tag;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> _allTags(List<NoteRecord> notes) {
    final seen = <String>{};
    for (final n in notes) {
      seen.addAll(n.tags);
    }
    final list = seen.toList()..sort();
    return list;
  }

  Future<void> _create() async {
    final draft = await _showEditor();
    if (draft == null) return;
    await widget.state.addNoteByKey(
      draft.wordKey,
      draft.content,
      title: draft.title,
      tags: draft.tags,
    );
  }

  Future<void> _edit(NoteRecord note) async {
    final draft = await _showEditor(note: note);
    if (draft == null) return;
    await widget.state.updateNote(
      note.id,
      draft.content,
      title: draft.title,
      tags: draft.tags,
    );
  }

  Future<_NoteDraft?> _showEditor({NoteRecord? note}) async {
    final title = TextEditingController(text: note?.title ?? '');
    final content = TextEditingController(text: note?.content ?? '');
    final tags = TextEditingController(text: note?.tags.join('，') ?? '');
    final word = TextEditingController(text: note?.wordKey ?? '');

    final result = await showDialog<_NoteDraft>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(note == null ? '新建小记' : '编辑小记'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: note == null,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '标题（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: content,
                  autofocus: note != null,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: '内容',
                    hintText: '记下想法、例句、联想…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tags,
                  decoration: const InputDecoration(
                    labelText: '标签（可选）',
                    hintText: '用逗号或空格分隔，如：写作 例句',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: word,
                  decoration: const InputDecoration(
                    labelText: '关联单词（可选）',
                    hintText: '留空则为独立小记',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = content.text.trim();
              final heading = title.text.trim();
              if (text.isEmpty && heading.isEmpty) return;
              Navigator.pop(
                ctx,
                _NoteDraft(
                  heading,
                  text,
                  _parseTags(tags.text),
                  word.text.trim().toLowerCase(),
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    title.dispose();
    content.dispose();
    tags.dispose();
    word.dispose();
    return result;
  }

  Future<void> _confirmDelete(NoteRecord note) async {
    final label = note.title.trim().isEmpty ? _firstLine(note.content) : note.title;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('删除这条小记？'),
        content: Text('「$label」删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.state.deleteNote(note.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        colors: kGradients[2],
        child: SafeArea(
          child: ListenableBuilder(
            listenable: widget.state,
            builder: (context, _) {
              final notes = widget.state.notes;
              final allTags = _allTags(notes);
              final activeTag = allTags.contains(_tag) ? _tag : null;
              final q = _query.trim().toLowerCase();
              final filtered = notes
                  .where((n) =>
                      (activeTag == null || n.tags.contains(activeTag)) &&
                      (q.isEmpty ||
                          n.title.toLowerCase().contains(q) ||
                          n.wordKey.toLowerCase().contains(q) ||
                          n.content.toLowerCase().contains(q) ||
                          n.tags.any((t) => t.toLowerCase().contains(q))))
                  .toList()
                ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

              // 扁平化为「日期标题 + 笔记」便于列表虚拟化
              final items = <Object>[];
              String? lastDay;
              for (final n in filtered) {
                final day = _fmtDay(n.updatedAt);
                if (day != lastDay) {
                  items.add(day);
                  lastDay = day;
                }
                items.add(n);
              }

              return Column(
                children: [
                  PageHeader(
                    title: '笔记',
                    subtitle: notes.isEmpty
                        ? '随手记，或关联到某个单词'
                        : '${notes.length} 条 · ${allTags.length} 个标签',
                    actions: [
                      IconButton(
                        tooltip: '新建小记',
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _create,
                      ),
                    ],
                  ),
                  if (notes.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v),
                        style: theme.textTheme.bodyMedium,
                        decoration: InputDecoration(
                          hintText: '搜索标题、内容、标签或单词',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _search.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.55),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    if (allTags.isNotEmpty)
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          children: [
                            _FilterChip(
                              label: '全部',
                              selected: activeTag == null,
                              onTap: () => setState(() => _tag = null),
                            ),
                            for (final t in allTags) ...[
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: '#$t',
                                selected: activeTag == t,
                                onTap: () => setState(
                                  () => _tag = _tag == t ? null : t,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                  Expanded(
                    child: notes.isEmpty
                        ? _EmptyView(onCreate: _create)
                        : filtered.isEmpty
                            ? Center(
                                child: Text(
                                  '没有匹配的小记',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(22, 8, 22, 40),
                                itemCount: items.length,
                                itemBuilder: (context, i) {
                                  final item = items[i];
                                  if (item is String) {
                                    return Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        4,
                                        12,
                                        4,
                                        6,
                                      ),
                                      child: Text(
                                        item,
                                        style:
                                            theme.textTheme.labelSmall?.copyWith(
                                          color: AppColors.textMuted,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    );
                                  }
                                  final note = item as NoteRecord;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _NoteCard(
                                      note: note,
                                      onEdit: () => _edit(note),
                                      onDelete: () => _confirmDelete(note),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final NoteRecord note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NoteCard({
    required this.note,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTitle = note.title.trim().isNotEmpty;
    final title = hasTitle ? note.title : _firstLine(note.content);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title.isEmpty ? '无标题' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _fmtTime(note.updatedAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          if (hasTitle && note.content.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note.content,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
          ],
          if (note.wordKey.isNotEmpty || note.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (note.wordKey.isNotEmpty)
                  _Tag(label: note.wordKey, accent: true),
                for (final t in note.tags) _Tag(label: '#$t'),
              ],
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: '编辑',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
              IconButton(
                tooltip: '删除',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final bool accent;

  const _Tag({required this.label, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final color = accent ? AppColors.accent : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.primary,
      backgroundColor: Colors.white.withValues(alpha: 0.55),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
      side: BorderSide.none,
      onSelected: (_) => onTap(),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyView({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 80),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit_note_rounded,
                size: 40,
                color: AppColors.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 12),
              Text('还没有小记', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                '像便签一样随手记下想法，\n可以打标签，也可以关联到某个单词。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onCreate,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text('写第一条小记'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<String> _parseTags(String raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final part in raw.split(RegExp(r'[,，、\s]+'))) {
    final tag = part.trim().replaceFirst(RegExp(r'^#'), '');
    if (tag.isNotEmpty && seen.add(tag)) out.add(tag);
  }
  return out;
}

String _firstLine(String text) {
  final line = text.trim().split('\n').first.trim();
  return line.length <= 40 ? line : '${line.substring(0, 40)}…';
}

String _fmtDay(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  return '${t.year}年${t.month}月${t.day}日';
}

String _fmtTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}
