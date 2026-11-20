import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../domain/custom_word_parser.dart';
import '../domain/word.dart';
import 'theme.dart';

/// 自建单词本详情：词条的增删改查 + 粘贴批量导入
class WordBookPage extends StatefulWidget {
  final AppState state;
  final String bookId;

  const WordBookPage({super.key, required this.state, required this.bookId});

  @override
  State<WordBookPage> createState() => _WordBookPageState();
}

class _WordBookPageState extends State<WordBookPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  Future<(String, String, List<WordSense>)?> _askWord({
    String word = '',
    String phonetic = '',
    List<WordSense> senses = const [],
    String title = '添加单词',
  }) {
    return showDialog<(String, String, List<WordSense>)>(
      context: context,
      builder: (_) => _WordFormDialog(
        state: widget.state,
        title: title,
        initialWord: word,
        initialPhonetic: phonetic,
        initialSenses: senses,
      ),
    );
  }

  Future<void> _addWord() async {
    final input = await _askWord();
    if (input == null) return;
    final err = await widget.state.addWordToBook(
      widget.bookId,
      word: input.$1,
      phonetic: input.$2,
      senses: input.$3,
    );
    if (err != null && mounted) _toast(err);
  }

  Future<void> _editWord(CustomWordEntry entry) async {
    final input = await _askWord(
      word: entry.word.w,
      phonetic: entry.word.uk,
      senses: entry.word.defs,
      title: '编辑单词',
    );
    if (input == null) return;
    final err = await widget.state.updateWordInBook(
      widget.bookId,
      entry,
      word: input.$1,
      phonetic: input.$2,
      senses: input.$3,
    );
    if (err != null && mounted) _toast(err);
  }

  Future<void> _deleteWord(CustomWordEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${entry.word.w}」？'),
        content: const Text('该词的复习记录会一并删除，此操作不可撤销。'),
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
    if (ok != true) return;
    await widget.state.removeWordFromBook(widget.bookId, entry.key);
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴导入'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '每行一个词，释义可选；用分号分隔多条释义，词性写在释义前：\n'
              'serendipity [ˌserənˈdɪpəti] n. 意外发现\n'
              'abandon v. 放弃; n. 放任',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '在此粘贴…',
                border: OutlineInputBorder(),
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
            child: const Text('导入'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null) return;

    final r = await widget.state.importWordsToBook(widget.bookId, text);
    if (!mounted) return;
    _toast(_importSummary(r));
  }

  Future<void> _rename() async {
    final book = widget.state.bookById(widget.bookId);
    if (book == null) return;
    final controller = TextEditingController(text: book.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名单词本'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    final err = await widget.state.renameCustomBook(widget.bookId, name);
    if (err != null && mounted) _toast(err);
  }

  Future<void> _deleteBook() async {
    final book = widget.state.bookById(widget.bookId);
    if (book == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${book.name}」？'),
        content: const Text('单词本及其中的词会被删除，此操作不可撤销。'),
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
    if (ok != true) return;
    await widget.state.deleteCustomBook(widget.bookId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final theme = Theme.of(context);
        final book = widget.state.bookById(widget.bookId);
        if (book == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('单词本已删除')),
          );
        }

        final q = _query.trim().toLowerCase();
        final words = q.isEmpty
            ? book.words
            : book.words
                .where((e) =>
                    e.key.contains(q) ||
                    e.word.uk.toLowerCase().contains(q) ||
                    _defsText(e.word).toLowerCase().contains(q))
                .toList();
        final learned = book.words
            .where((e) => widget.state.states.containsKey(e.key))
            .length;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: AppBackground(
            colors: kGradients[2],
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _header(theme, book, learned),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _addWord,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('添加单词'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _import,
                            icon: const Icon(Icons.playlist_add, size: 18),
                            label: const Text('粘贴导入'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(
                                color: AppColors.primary.withValues(alpha: 0.35),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '搜索单词、音标或释义',
                        hintStyle: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textMuted,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          size: 20,
                          color: AppColors.textMuted,
                        ),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清除',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _clearSearch,
                              ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.62),
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        q.isEmpty
                            ? '共 ${book.words.length} 个词'
                            : '匹配 ${words.length} 个词',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: words.isEmpty
                        ? _emptyState(theme, book)
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(22, 2, 22, 32),
                            itemCount: words.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final e = words[i];
                              return GlassCard(
                                radius: 18,
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  14,
                                  6,
                                  14,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  e.word.w,
                                                  style: theme
                                                      .textTheme.titleMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              if (e.word.uk.isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    _phonetic(e.word.uk),
                                                    style: theme
                                                        .textTheme.bodySmall
                                                        ?.copyWith(
                                                      color:
                                                          AppColors.textMuted,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (_defsText(e.word).isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              _defsText(e.word, maxSenses: 2),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 4),
                                          Text(
                                            '添加于 ${_fmtTime(e.addedAt)} · 添加 ${e.addCount} 次',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: '更多',
                                      icon: const Icon(
                                        Icons.more_horiz,
                                        color: AppColors.textMuted,
                                      ),
                                      onSelected: (v) {
                                        if (v == 'edit') {
                                          _editWord(e);
                                        } else if (v == 'delete') {
                                          _deleteWord(e);
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
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(ThemeData theme, CustomWordBook book, int learned) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back),
            color: AppColors.text,
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '共 ${book.words.length} 词 · 已学 $learned',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
            onSelected: (v) {
              if (v == 'rename') {
                _rename();
              } else if (v == 'delete') {
                _deleteBook();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('重命名')),
              PopupMenuItem(value: 'delete', child: Text('删除单词本')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData theme, CustomWordBook book) {
    final searching = _query.trim().isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off : Icons.menu_book_outlined,
              size: 40,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              searching ? '没有匹配的词' : '「${book.name}」还没有单词',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              searching ? '换个关键词试试，或清除搜索。' : '添加第一个词，或从别处粘贴一批导入。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            if (searching)
              TextButton(
                onPressed: _clearSearch,
                child: const Text('清除搜索'),
              )
            else
              FilledButton.icon(
                onPressed: _addWord,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加单词'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 加词 / 编辑表单：输入单词后从离线词典带出音标与释义（可修改）
class _SenseDraft {
  final TextEditingController pos;
  final TextEditingController cn;
  final TextEditingController en;

  _SenseDraft({
    String posText = '',
    String cnText = '',
    String enText = '',
  })  : pos = TextEditingController(text: posText),
        cn = TextEditingController(text: cnText),
        en = TextEditingController(text: enText);

  factory _SenseDraft.from(WordSense s) =>
      _SenseDraft(posText: s.pos, cnText: s.cn, enText: s.en);

  void dispose() {
    pos.dispose();
    cn.dispose();
    en.dispose();
  }
}

class _WordFormDialog extends StatefulWidget {
  final AppState state;
  final String title;
  final String initialWord;
  final String initialPhonetic;
  final List<WordSense> initialSenses;

  const _WordFormDialog({
    required this.state,
    required this.title,
    this.initialWord = '',
    this.initialPhonetic = '',
    this.initialSenses = const [],
  });

  @override
  State<_WordFormDialog> createState() => _WordFormDialogState();
}

class _WordFormDialogState extends State<_WordFormDialog> {
  late final TextEditingController _word;
  late final TextEditingController _phonetic;
  final List<_SenseDraft> _senses = [];

  Timer? _debounce;

  /// null / hit / miss
  String? _status;
  String _autoPhonetic = '';
  String _autoDefinition = '';
  bool _phoneticFromDict = false;
  bool _definitionFromDict = false;
  bool _appliedFromDict = false;

  @override
  void initState() {
    super.initState();
    _word = TextEditingController(text: widget.initialWord);
    _phonetic = TextEditingController(text: widget.initialPhonetic);
    for (final s in widget.initialSenses) {
      _senses.add(_SenseDraft.from(s));
    }
    if (_senses.isEmpty) _senses.add(_SenseDraft());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _word.dispose();
    _phonetic.dispose();
    for (final s in _senses) {
      s.dispose();
    }
    super.dispose();
  }

  void _onWordChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      if (_status != null) setState(() => _status = null);
      return;
    }
    if (_status != null) setState(() => _status = null);
    _debounce = Timer(const Duration(milliseconds: 300), _lookup);
  }

  void _lookup() {
    if (!mounted) return;
    final entry = widget.state.dictionary.lookup(_word.text);
    if (entry == null) {
      setState(() => _status = 'miss');
      return;
    }

    setState(() {
      _status = 'hit';
      if (entry.phonetic.isNotEmpty &&
          (_phonetic.text.trim().isEmpty || _phoneticFromDict)) {
        _phonetic.text = entry.phonetic;
        _autoPhonetic = entry.phonetic;
        _phoneticFromDict = true;
        _appliedFromDict = true;
      }
      final first = _senses.first.cn;
      if (entry.translation.isNotEmpty &&
          (first.text.trim().isEmpty || _definitionFromDict)) {
        first.text = entry.translation;
        _autoDefinition = entry.translation;
        _definitionFromDict = true;
        _appliedFromDict = true;
      }
    });
  }

  void _onPhoneticChanged(String value) {
    if (value != _autoPhonetic) _phoneticFromDict = false;
  }

  void _onDefinitionChanged(String value) {
    if (value != _autoDefinition) _definitionFromDict = false;
  }

  void _addSense() {
    setState(() => _senses.add(_SenseDraft()));
  }

  void _removeSense(int index) {
    late _SenseDraft removed;
    setState(() => removed = _senses.removeAt(index));
    // 等这一帧的输入框卸载后再释放控制器，避免「used after disposed」
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  Widget _senseRow(int index, ThemeData theme) {
    final sense = _senses[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: sense.pos,
                  style: theme.textTheme.bodyMedium,
                  decoration: const InputDecoration(
                    labelText: '词性',
                    hintText: 'n. / v. / adj. / phr.',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (_senses.length > 1)
                IconButton(
                  tooltip: '删除这条释义',
                  iconSize: 18,
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => _removeSense(index),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: sense.cn,
            style: theme.textTheme.bodyMedium,
            minLines: 1,
            maxLines: 3,
            onChanged: index == 0 ? _onDefinitionChanged : null,
            decoration: const InputDecoration(
              labelText: '中文释义',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: sense.en,
            style: theme.textTheme.bodyMedium,
            decoration: const InputDecoration(
              labelText: '英文释义（可选）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusLine(ThemeData theme) {
    if (_status == 'hit') {
      final text = _appliedFromDict ? '已从离线词典带出，可修改' : '词典已收录，可参考';
      return Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 14,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }
    if (_status == 'miss') {
      return Text(
        '未收录，请手动填写',
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.accent),
      );
    }
    return Text(
      '输入单词后自动带出音标与首条释义',
      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
    );
  }

  List<WordSense> _collectSenses() => [
        for (final s in _senses)
          if (s.cn.text.trim().isNotEmpty || s.en.text.trim().isNotEmpty)
            WordSense(
              pos: s.pos.text.trim(),
              cn: s.cn.text.trim(),
              en: s.en.text.trim(),
            ),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _word,
                autofocus: widget.initialWord.isEmpty,
                textInputAction: TextInputAction.next,
                onChanged: _onWordChanged,
                onSubmitted: (_) {
                  _debounce?.cancel();
                  _lookup();
                },
                decoration: const InputDecoration(
                  labelText: '单词',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              _statusLine(theme),
              const SizedBox(height: 12),
              TextField(
                controller: _phonetic,
                textInputAction: TextInputAction.next,
                onChanged: _onPhoneticChanged,
                decoration: const InputDecoration(
                  labelText: '音标（可选）',
                  hintText: '如 /səˈrɛndɪpəti/',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('释义', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addSense,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加释义'),
                  ),
                ],
              ),
              for (var i = 0; i < _senses.length; i++)
                _senseRow(i, theme),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (_word.text, _phonetic.text, _collectSenses()),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

String _defsText(Word word, {int maxSenses = 99}) {
  final parts = <String>[];
  for (final d in word.defs) {
    if (parts.length >= maxSenses) break;
    final pos = d.pos.trim();
    final cn = d.cn.trim();
    final en = d.en.trim();
    if (cn.isEmpty && en.isEmpty) continue;
    final body = [if (cn.isNotEmpty) cn, if (en.isNotEmpty) en].join(' ');
    parts.add(pos.isEmpty ? body : '$pos $body');
  }
  return parts.join('；');
}

String _phonetic(String raw) {
  final text = raw.trim();
  if (text.startsWith('/')) return text;
  return '/$text/';
}

String _importSummary(CustomWordParseResult r) {
  final parts = <String>[];
  if (r.added.isNotEmpty) parts.add('已添加 ${r.added.length} 个词');
  final repeats = r.repeated.values.fold<int>(0, (a, b) => a + b);
  if (repeats > 0) parts.add('$repeats 次重复已累加');
  if (r.invalid.isNotEmpty) parts.add('${r.invalid.length} 行无法识别');
  return parts.isEmpty ? '没有可导入的内容' : parts.join('；');
}

String _fmtTime(DateTime? t) {
  if (t == null) return '时间未知';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
