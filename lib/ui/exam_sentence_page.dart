import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../domain/word.dart';
import 'quiz_widgets.dart';

/// 真题例句：浏览词书配套考试原句
///
/// 数据与「考试练习」同源（[Word.quiz]），一句一题。
/// 源数据未标注年份与试卷出处，页面如实说明，不虚构来源。
class ExamSentencePage extends StatefulWidget {
  final AppState state;
  const ExamSentencePage({super.key, required this.state});

  @override
  State<ExamSentencePage> createState() => _ExamSentencePageState();
}

class _ExamSentencePageState extends State<ExamSentencePage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _tag;

  static const _filters = <String?, String>{
    null: '全部',
    'cet4': '四级',
    'cet6': '六级',
    'kaoyan': '考研',
  };

  @override
  void initState() {
    super.initState();
    _tag = widget.state.examTag;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<({Word word, QuizItem item})> _buildList() {
    final q = _query.trim().toLowerCase();
    final base =
        _tag == null ? widget.state.repo.all : widget.state.repo.byTag(_tag!);
    final out = <({Word word, QuizItem item})>[];
    for (final w in base) {
      for (final item in w.quiz) {
        if (q.isNotEmpty &&
            !w.w.toLowerCase().contains(q) &&
            !item.question.toLowerCase().contains(q)) {
          continue;
        }
        out.add((word: w, item: item));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _buildList();

    return Scaffold(
      appBar: AppBar(title: const Text('真题例句'), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: _filters.entries.map((e) {
                    return ChoiceChip(
                      label: Text(e.value),
                      selected: _tag == e.key,
                      onSelected: (_) => setState(() => _tag = e.key),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: '搜索单词或句子',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '共 ${list.length} 句 · 选自词书配套考试题',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '原文未标注年份与试卷出处，因此不标注「某年真题」',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('没有匹配的例句'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final entry = list[i];
                      return _SentenceCard(
                        word: entry.word,
                        item: entry.item,
                        onTap: () => _showDetail(entry.word, entry.item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showDetail(Word word, QuizItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (ctx, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(
                  word.w,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (word.primaryDefinition.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    word.primaryDefinition,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                QuizCard(item: item),
                const SizedBox(height: 12),
                Text(
                  '题目与例句来自词书配套试题，原文未标注年份与试卷出处。',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SentenceCard extends StatelessWidget {
  final Word word;
  final QuizItem item;
  final VoidCallback onTap;

  const _SentenceCard({
    required this.word,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          word.w,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      for (final tag in word.tags)
                        Text(
                          _tagName(tag),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.question,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

String _tagName(String tag) => switch (tag) {
      'cet4' => '四级',
      'cet6' => '六级',
      'kaoyan' => '考研',
      _ => tag,
    };
