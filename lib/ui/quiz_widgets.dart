import 'package:material_ui/material_ui.dart';

import '../domain/word.dart';

/// 考试练习题卡片（复习卡片与练习页共用）
class QuizCard extends StatefulWidget {
  final QuizItem item;

  /// 作答后回调（用于练习页统计得分）
  final void Function(bool correct)? onAnswered;

  const QuizCard({super.key, required this.item, this.onAnswered});

  @override
  State<QuizCard> createState() => _QuizCardState();
}

class _QuizCardState extends State<QuizCard> {
  int? _selected;

  bool get _answered => _selected != null;

  void _choose(int i) {
    if (_answered) return;
    setState(() => _selected = i);
    widget.onAnswered?.call(i == widget.item.answerIndex);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.question,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < item.options.length; i++)
            _OptionRow(
              label: String.fromCharCode(65 + i),
              text: item.options[i],
              state: _stateOf(i),
              onTap: () => _choose(i),
            ),
          if (_answered) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selected == item.answerIndex
                        ? '正确 · 答案 ${item.answerText}'
                        : '答案 ${item.answerText}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _selected == item.answerIndex
                          ? const Color(0xFF2E7D32)
                          : theme.colorScheme.error,
                    ),
                  ),
                  if (item.explain.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(item.explain, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  _OptionState _stateOf(int i) {
    if (!_answered) return _OptionState.idle;
    if (i == widget.item.answerIndex) return _OptionState.correct;
    if (i == _selected) return _OptionState.wrong;
    return _OptionState.idle;
  }
}

enum _OptionState { idle, correct, wrong }

class _OptionRow extends StatelessWidget {
  final String label;
  final String text;
  final _OptionState state;
  final VoidCallback onTap;

  const _OptionRow({
    required this.label,
    required this.text,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (border, bg, fg) = switch (state) {
      _OptionState.correct => (
          const Color(0xFF2E7D32),
          const Color(0xFF2E7D32).withValues(alpha: 0.10),
          const Color(0xFF1B5E20),
        ),
      _OptionState.wrong => (
          theme.colorScheme.error,
          theme.colorScheme.error.withValues(alpha: 0.08),
          theme.colorScheme.error,
        ),
      _OptionState.idle => (
          theme.colorScheme.outlineVariant,
          Colors.transparent,
          theme.colorScheme.onSurface,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(color: fg),
                ),
              ),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
