import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../domain/learning_quiz.dart';
import '../domain/srs.dart';
import '../domain/word.dart';
import '../services/audio_service.dart';
import 'theme.dart';

/// 学习页：四选一 → 看答案 → 自动评分 → 下一词
class LearningPage extends StatefulWidget {
  final AppState state;

  const LearningPage({super.key, required this.state});

  @override
  State<LearningPage> createState() => _LearningPageState();
}

class _LearningPageState extends State<LearningPage> {
  final AudioService _audio = AudioService();
  final Random _random = Random();

  late List<Color> _gradient;
  late List<Word> _queue;
  bool _quizMode = false;

  int _index = 0;
  int _done = 0;
  int _correct = 0;

  QuizQuestion? _question;
  int? _selected;
  bool _revealed = false;
  int _definedCount = 0;

  @override
  void initState() {
    super.initState();
    _gradient = kGradients[DateTime.now().millisecondsSinceEpoch % kGradients.length];
    _start();
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  Word? get _current => _index < _queue.length ? _queue[_index] : null;

  void _start() {
    final pool = widget.state.pool;
    _queue = widget.state.buildTodayQueue(
      newLimit: widget.state.settings.newWordsPerGroup,
      dueLimit: widget.state.settings.reviewWordsPerGroup,
    );
    _definedCount =
        pool.where((w) => w.defs.any((d) => d.cn.trim().isNotEmpty)).length;
    _quizMode = canBuildQuiz(pool);
    _index = 0;
    _done = 0;
    _correct = 0;
    _prepare();
  }

  void _prepare() {
    _selected = null;
    _revealed = false;
    final word = _current;
    _question = (_quizMode && word != null)
        ? buildQuiz(word, widget.state.pool, random: _random)
        : null;
    if (word == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _audio.play(word.w);
    });
  }

  Future<void> _choose(int i) async {
    final question = _question;
    final word = _current;
    if (question == null || word == null || _revealed) return;

    final correct = question.options[i].isCorrect;
    final reps = widget.state.states[word.key]?.reps ?? 0;
    setState(() {
      _selected = i;
      _revealed = true;
      _done += 1;
      if (correct) _correct += 1;
    });
    await widget.state.grade(word, autoGrade(correct: correct, reps: reps));
  }

  Future<void> _rate(ReviewGrade grade) async {
    final word = _current;
    if (word == null) return;
    setState(() {
      _done += 1;
      _revealed = true;
    });
    await widget.state.grade(word, grade);
    if (!mounted) return;
    _next();
  }

  void _next() {
    setState(() {
      _index += 1;
      _prepare();
    });
  }

  void _skip() {
    setState(() {
      _index += 1;
      _prepare();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_queue.isEmpty) {
      final noWords = widget.state.pool.isEmpty;
      return _MessageView(
        gradient: _gradient,
        icon: noWords ? Icons.menu_book_outlined : Icons.check_circle_outline,
        title: noWords ? '还没有可学习的词' : '今天的学习已完成',
        subtitle: noWords
            ? '去「词单」创建单词本并添加单词后再来。'
            : '词书共 ${widget.state.pool.length} 个词（$_definedCount 个带释义），'
                '今天没有到期或未学的词，明天再来吧。',
        onBack: () => Navigator.of(context).pop(),
      );
    }

    if (_index >= _queue.length) {
      return _SummaryView(
        gradient: _gradient,
        done: _done,
        correct: _quizMode ? _correct : null,
        streak: widget.state.streakDays,
        remainingDue: widget.state.dueCount,
        canRestart: widget.state.dueCount > 0,
        onBack: () => Navigator.of(context).pop(),
        onRestart: () => setState(_start),
      );
    }

    final theme = Theme.of(context);
    final word = _current!;
    final noDefinition = word.defs.isEmpty;
    final canGrade = !noDefinition && _question != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        colors: _gradient,
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      '${_index + 1} / ${_queue.length}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (v) {
                      if (v == 'skip') _skip();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'skip', child: Text('跳过')),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (_index + (_revealed ? 1 : 0)) / _queue.length,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.45),
                    color: AppColors.primary,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                  children: [
                    Text(
                      word.w,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _PronunciationRow(word: word, audio: _audio),
                    const SizedBox(height: 12),
                    Text(
                      '先回想词义再选择，想不起来看答案',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (noDefinition)
                      _NoDefinitionCard(
                        word: word,
                        onSkip: _skip,
                      )
                    else if (!canGrade)
                      _SelfGradeSection(
                        word: word,
                        revealed: _revealed,
                        definedCount: _definedCount,
                        onReveal: () => setState(() => _revealed = true),
                        onRate: _rate,
                      )
                    else ...[
                      for (var i = 0; i < _question!.options.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _OptionCard(
                            option: _question!.options[i],
                            selected: _selected == i,
                            revealed: _revealed,
                            onTap: () => _choose(i),
                          ),
                        ),
                      if (_revealed) ...[
                        const SizedBox(height: 8),
                        _AnswerPanel(word: word),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text('下一词'),
                        ),
                      ],
                    ],
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

class _PronunciationRow extends StatelessWidget {
  final Word word;
  final AudioService audio;

  const _PronunciationRow({required this.word, required this.audio});

  @override
  Widget build(BuildContext context) {
    final phonetic = word.uk.isNotEmpty ? word.uk : word.us;
    final label = word.uk.isNotEmpty ? '英' : '美';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (phonetic.isNotEmpty)
          Text(
            '$label /$phonetic/',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: '发音',
          icon: const Icon(
            Icons.volume_up_rounded,
            color: AppColors.primary,
          ),
          onPressed: () => audio.play(word.w),
        ),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  final QuizOption option;
  final bool selected;
  final bool revealed;
  final VoidCallback onTap;

  const _OptionCard({
    required this.option,
    required this.selected,
    required this.revealed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color background = Colors.white.withValues(alpha: 0.62);
    Color border = Colors.transparent;
    Color foreground = AppColors.text;

    if (revealed) {
      if (option.isCorrect) {
        background = AppColors.primary.withValues(alpha: 0.14);
        border = AppColors.primary;
        foreground = AppColors.primary;
      } else if (selected) {
        background = AppColors.danger.withValues(alpha: 0.12);
        border = AppColors.danger;
        foreground = AppColors.danger;
      } else {
        background = Colors.white.withValues(alpha: 0.38);
        foreground = AppColors.textMuted;
      }
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: revealed ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border, width: 1.4),
          ),
          child: Row(
            children: [
              if (option.pos.isNotEmpty) ...[
                Text(
                  option.pos,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  option.text,
                  style: TextStyle(color: foreground, fontSize: 15),
                ),
              ),
              if (revealed && option.isCorrect)
                const Icon(Icons.check_circle,
                    size: 18, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnswerPanel extends StatelessWidget {
  final Word word;

  const _AnswerPanel({required this.word});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(18),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('完整释义', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          for (final d in word.defs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (d.pos.isNotEmpty) ...[
                    Text(
                      '${d.pos}. ',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  Expanded(child: Text(d.cn)),
                ],
              ),
            ),
          if (word.ex.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final e in word.ex)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  e.cn.isEmpty ? e.en : '${e.en}  ${e.cn}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 词池不足 4 个有释义的词时的降级：自评四档
class _SelfGradeSection extends StatelessWidget {
  final Word word;
  final bool revealed;
  final int definedCount;
  final VoidCallback onReveal;
  final Future<void> Function(ReviewGrade) onRate;

  const _SelfGradeSection({
    required this.word,
    required this.revealed,
    required this.definedCount,
    required this.onReveal,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!revealed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '四选一暂未开启：词书里带释义的词只有 $definedCount 个，'
            '至少需要 4 个。补充词条后会自动切换。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onReveal,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Text('显示答案'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AnswerPanel(word: word),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final (grade, label, color) in [
              (ReviewGrade.again, '重来', AppColors.danger),
              (ReviewGrade.hard, '难', const Color(0xFFB26A00)),
              (ReviewGrade.good, '一般', AppColors.primary),
              (ReviewGrade.easy, '简单', const Color(0xFF2E7D32)),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: OutlinedButton(
                    onPressed: () => onRate(grade),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _NoDefinitionCard extends StatelessWidget {
  final Word word;
  final VoidCallback onSkip;

  const _NoDefinitionCard({required this.word, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '「${word.w}」还没有释义',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            '补全释义后才能生成选项。可先跳过，去「词单」里编辑。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onSkip, child: const Text('跳过')),
        ],
      ),
    );
  }
}

class _SummaryView extends StatelessWidget {
  final List<Color> gradient;
  final int done;
  final int? correct;
  final int streak;
  final int remainingDue;
  final bool canRestart;
  final VoidCallback onBack;
  final VoidCallback onRestart;

  const _SummaryView({
    required this.gradient,
    required this.done,
    required this.correct,
    required this.streak,
    required this.remainingDue,
    required this.canRestart,
    required this.onBack,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        colors: gradient,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.emoji_events_outlined,
                    size: 56,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 16),
                  Text('本次学习 $done 个词', style: theme.textTheme.titleLarge),
                  if (correct != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      done == 0
                          ? '正确率 —'
                          : '正确率 ${(correct! / done * 100).round()}%',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    '连续 $streak 天',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (remainingDue > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '还有 $remainingDue 个到期词，可继续下一组',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: onBack,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                    ),
                    child: const Text('返回今日'),
                  ),
                  if (canRestart) ...[
                    const SizedBox(height: 8),
                    TextButton(onPressed: onRestart, child: const Text('再来一组')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  final List<Color> gradient;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  const _MessageView({
    required this.gradient,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        colors: gradient,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 56, color: AppColors.textMuted),
                  const SizedBox(height: 12),
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: onBack, child: const Text('返回')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
