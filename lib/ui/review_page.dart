import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../domain/affix.dart';
import '../domain/srs.dart';
import '../domain/word.dart';
import '../services/audio_service.dart';
import 'quiz_widgets.dart';

class ReviewPage extends StatefulWidget {
  final AppState state;
  const ReviewPage({super.key, required this.state});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final AudioService _audio = AudioService();
  late List<Word> _queue;
  int _index = 0;
  bool _revealed = false;
  int _done = 0;

  @override
  void initState() {
    super.initState();
    _queue = widget.state.buildTodayQueue();
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  Word get _current => _queue[_index];

  Future<void> _grade(ReviewGrade g) async {
    await widget.state.grade(_current, g);
    if (!mounted) return;
    setState(() {
      _done += 1;
      _index += 1;
      _revealed = false;
    });
  }

  Future<void> _addNote() async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('笔记 · ${_current.w}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '写下你的理解、联想或例句…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await widget.state.addNote(_current, controller.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('笔记已保存')),
      );
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_queue.isEmpty) {
      return _EmptyView(onBack: () => Navigator.of(context).pop());
    }

    if (_index >= _queue.length) {
      return _SummaryView(
        done: _done,
        onBack: () => Navigator.of(context).pop(),
      );
    }

    final theme = Theme.of(context);
    final word = _current;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_index + 1} / ${_queue.length}'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: widget.state.isFavorite(_current) ? '取消收藏' : '收藏',
            icon: Icon(
              widget.state.isFavorite(_current) ? Icons.star : Icons.star_border,
              color: widget.state.isFavorite(_current)
                  ? const Color(0xFFE0A800)
                  : null,
            ),
            onPressed: () async {
              await widget.state.toggleFavorite(_current);
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            tooltip: '记笔记',
            icon: const Icon(Icons.edit_note),
            onPressed: _addNote,
          ),
          TextButton(
            onPressed: () {
              setState(() => _audio.isUk = !_audio.isUk);
            },
            child: Text(
              _audio.isUk ? 'UK' : 'US',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_index + 1) / _queue.length,
            minHeight: 3,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    word.w,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PronounceButton(
                        label: '英',
                        phonetic: word.uk,
                        onTap: () => _audio.play(word.w, uk: true),
                      ),
                      const SizedBox(width: 16),
                      _PronounceButton(
                        label: '美',
                        phonetic: word.us,
                        onTap: () => _audio.play(word.w, uk: false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (word.tags.isNotEmpty)
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      children: word.tags.map((t) {
                        return Chip(
                          label: Text(_tagLabel(t), style: theme.textTheme.labelSmall),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 28),
                  if (!_revealed)
                    OutlinedButton(
                      onPressed: () => setState(() => _revealed = true),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('显示释义'),
                      ),
                    )
                  else
                    _WordDetail(
                      word: word,
                      affixes: widget.state.affixes.all,
                      isKnownWord: (k) => widget.state.repo.byKey(k) != null,
                    ),
                ],
              ),
            ),
          ),
          if (_revealed) _GradeBar(state: widget.state, word: word, onGrade: _grade),
        ],
      ),
    );
  }
}

String _tagLabel(String tag) => switch (tag) {
      'cet4' => '四级',
      'cet6' => '六级',
      'kaoyan' => '考研',
      _ => tag,
    };

class _PronounceButton extends StatelessWidget {
  final String label;
  final String phonetic;
  final VoidCallback onTap;

  const _PronounceButton({
    required this.label,
    required this.phonetic,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            Text(
              phonetic.isEmpty ? '—' : '/$phonetic/',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.volume_up_rounded, size: 18, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _WordDetail extends StatelessWidget {
  final Word word;
  final List<Affix> affixes;
  final bool Function(String)? isKnownWord;
  const _WordDetail({
    required this.word,
    required this.affixes,
    this.isKnownWord,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matches = analyzeWord(word.w, affixes, isKnownWord: isKnownWord);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final d in word.defs) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (d.pos.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 2, right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(d.pos, style: theme.textTheme.labelSmall),
                ),
              Expanded(
                child: Text(d.cn, style: theme.textTheme.bodyLarge),
              ),
            ],
          ),
          if (d.en.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 4, bottom: 4),
              child: Text(
                d.en,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (matches.isNotEmpty) ...[
          _SectionTitle('词形拆解'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: matches.map((m) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: m.segment,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      TextSpan(
                        text: '  ${m.affix.meaning}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        if (word.ex.isNotEmpty) ...[
          const SizedBox(height: 4),
          _SectionTitle('例句'),
          const SizedBox(height: 6),
          for (final e in word.ex)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.en, style: theme.textTheme.bodyMedium),
                  if (e.cn.isNotEmpty)
                    Text(
                      e.cn,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
        ],
        if (word.phr.isNotEmpty) ...[
          _SectionTitle('短语'),
          const SizedBox(height: 6),
          for (final p in word.phr)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: p.en,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: '  ${p.cn}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (word.rel.isNotEmpty) ...[
          _SectionTitle('同根词'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: word.rel.map((r) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  r.cn.isEmpty ? r.w : '${r.w} ${r.cn}',
                  style: theme.textTheme.bodySmall,
                ),
              );
            }).toList(),
          ),
        ],
        if (word.syn.isNotEmpty) ...[
          _SectionTitle('近义'),
          const SizedBox(height: 6),
          for (final s in word.syn)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${s.words.join(' / ')}  ${s.cn}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
        if (word.quiz.isNotEmpty) ...[
          _SectionTitle('考试练习'),
          const SizedBox(height: 6),
          Text(
            '选自词书配套试题，原文未标注年份与试卷出处',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final q in word.quiz)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: QuizCard(item: q),
            ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GradeBar extends StatelessWidget {
  final AppState state;
  final Word word;
  final Future<void> Function(ReviewGrade) onGrade;

  const _GradeBar({required this.state, required this.word, required this.onGrade});

  String _hint(ReviewGrade g) {
    final cur = state.states[word.key] ?? ReviewState.initial();
    final next = SrsEngine.next(cur, g);
    if (g == ReviewGrade.again) return '10 分钟';
    return '${next.interval} 天';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <(ReviewGrade, String, Color)>[
      (ReviewGrade.again, '重来', theme.colorScheme.error),
      (ReviewGrade.hard, '困难', const Color(0xFFB26A00)),
      (ReviewGrade.good, '一般', theme.colorScheme.primary),
      (ReviewGrade.easy, '简单', const Color(0xFF2E7D32)),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: items.map((item) {
            final (grade, label, color) = item;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: OutlinedButton(
                  onPressed: () => onGrade(grade),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(_hint(grade), style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onBack;
  const _EmptyView({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('今日学习')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 56),
            const SizedBox(height: 12),
            const Text('今天的任务已完成'),
            const SizedBox(height: 16),
            FilledButton(onPressed: onBack, child: const Text('返回')),
          ],
        ),
      ),
    );
  }
}

class _SummaryView extends StatelessWidget {
  final int done;
  final VoidCallback onBack;
  const _SummaryView({required this.done, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_outlined, size: 64),
            const SizedBox(height: 16),
            Text('完成 $done 个词', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            FilledButton(onPressed: onBack, child: const Text('返回首页')),
          ],
        ),
      ),
    );
  }
}
