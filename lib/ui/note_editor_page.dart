import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../data/note_record.dart';
import 'markdown_text.dart';
import 'theme.dart';

/// 笔记编辑页：Markdown 编辑 + 简易工具栏 + 预览切换
class NoteEditorPage extends StatefulWidget {
  final AppState state;
  final NoteRecord? note;

  const NoteEditorPage({super.key, required this.state, this.note});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final TextEditingController _tags;
  final FocusNode _focus = FocusNode();

  bool _preview = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _title = TextEditingController(text: note?.title ?? '');
    _content = TextEditingController(text: note?.content ?? '');
    _tags = TextEditingController(text: note?.tags.join('，') ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _tags.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final content = _content.text.trim();
    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('写点什么再保存')),
      );
      return;
    }
    setState(() => _saving = true);
    final tags = _parseTags(_tags.text);
    final note = widget.note;
    if (note == null) {
      await widget.state.addNote(content, title: title, tags: tags);
    } else {
      await widget.state.updateNote(note.id, content, title: title, tags: tags);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        colors: kGradients[2],
        child: SafeArea(
          child: Column(
            children: [
              PageHeader(
                title: widget.note == null ? '新建小记' : '编辑小记',
                subtitle: _preview ? '预览' : '支持 Markdown',
                actions: [
                  IconButton(
                    tooltip: _preview ? '继续编辑' : '预览',
                    icon: Icon(
                      _preview
                          ? Icons.edit_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _preview = !_preview),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 2, right: 6),
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
                  children: [
                    TextField(
                      controller: _title,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: '标题（可选）',
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.55),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!_preview) ...[
                      _toolbar(theme),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _content,
                        focusNode: _focus,
                        minLines: 14,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                        decoration: InputDecoration(
                          hintText: '记下想法、例句、联想…\n'
                              '支持 **粗体**、*斜体*、- 列表、> 引用',
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.55),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ] else
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 220),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: MarkdownText(
                          _content.text,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tags,
                      decoration: InputDecoration(
                        labelText: '标签（可选）',
                        hintText: '用逗号或空格分隔，如：写作 例句',
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.55),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
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

  Widget _toolbar(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _toolButton(
            icon: Icons.title,
            tooltip: '标题',
            onTap: () => _prefixLine('# '),
          ),
          _toolButton(
            icon: Icons.format_bold,
            tooltip: '加粗',
            onTap: () => _wrapSelection('**', '**', '粗体'),
          ),
          _toolButton(
            icon: Icons.format_italic,
            tooltip: '斜体',
            onTap: () => _wrapSelection('*', '*', '斜体'),
          ),
          _toolButton(
            icon: Icons.format_list_bulleted,
            tooltip: '列表',
            onTap: () => _prefixLine('- '),
          ),
          _toolButton(
            icon: Icons.format_quote,
            tooltip: '引用',
            onTap: () => _prefixLine('> '),
          ),
          _toolButton(
            icon: Icons.code,
            tooltip: '行内代码',
            onTap: () => _wrapSelection('`', '`', '代码'),
          ),
        ],
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
      color: AppColors.textSecondary,
      onPressed: onTap,
    );
  }

  /// 在选区两侧插入标记；无选区时插入占位文字并选中它
  void _wrapSelection(String left, String right, String placeholder) {
    final value = _content.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final selected = text.substring(start, end);
    final body = selected.isEmpty ? placeholder : selected;
    _content.value = TextEditingValue(
      text: text.replaceRange(start, end, '$left$body$right'),
      selection: TextSelection(
        baseOffset: start + left.length,
        extentOffset: start + left.length + body.length,
      ),
    );
    _focus.requestFocus();
  }

  /// 在光标所在行首添加 / 移除前缀
  void _prefixLine(String prefix) {
    final value = _content.value;
    final text = value.text;
    final selection = value.selection;
    final offset = selection.isValid ? selection.start : text.length;
    final lineStart = offset <= 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;

    if (text.startsWith(prefix, lineStart)) {
      _content.value = TextEditingValue(
        text: text.replaceRange(lineStart, lineStart + prefix.length, ''),
        selection: TextSelection.collapsed(
          offset: offset - prefix.length < 0 ? 0 : offset - prefix.length,
        ),
      );
    } else {
      _content.value = TextEditingValue(
        text: text.replaceRange(lineStart, lineStart, prefix),
        selection: TextSelection.collapsed(offset: offset + prefix.length),
      );
    }
    _focus.requestFocus();
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
