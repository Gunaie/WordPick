import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../domain/learning_quiz.dart';
import '../domain/spelling_hints.dart';
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

  /// 关联插入的词 -> 易混组名，用于卡片上的小标
  Map<String, String> _companions = {};
  bool _quizMode = false;

  int _index = 0;

  QuizQuestion? _question;
  int? _selected;
  bool _revealed = false;
  int _definedCount = 0;

  /// 本轮答错过的词：答对后需要再做一次「看释义拼写」
  final Set<String> _missed = {};

  /// 本词答对后是否要先进入拼写环节
  bool _spellNext = false;

  /// 当前拼写环节的词；非 null 时界面切到拼写
  Word? _spellTarget;
  final TextEditingController _spellCtrl = TextEditingController();
  final FocusNode _spellFocus = FocusNode();
  String? _spellError;

  /// 每个词最终完成后的到期日，用于小结「N 天后复习」
  final Map<String, DateTime> _due = {};
  final Map<String, Word> _doneWords = {};
  final List<String> _order = [];

  /// 已完成的回合快照，键为队列下标；回看只读，不重新计分
  final Map<int, _RoundSnapshot> _history = {};
  int? _reviewIndex;

  @override
  void initState() {
    super.initState();
    _gradient = kGradients[DateTime.now().millisecondsSinceEpoch % kGradients.length];
    _start();
  }

  @override
  void dispose() {
    _audio.dispose();
    _spellCtrl.dispose();
    _spellFocus.dispose();
    super.dispose();
  }

  Word? get _current => _index < _queue.length ? _queue[_index] : null;

  void _start() {
    final pool = widget.state.pool;
    final round = widget.state.buildTodayQueue(
      newLimit: widget.state.settings.newWordsPerGroup,
      dueLimit: widget.state.settings.reviewWordsPerGroup,
    );
    _queue = round.words;
    _companions = {...round.companions};
    _definedCount =
        pool.where((w) => w.defs.any((d) => d.cn.trim().isNotEmpty)).length;
    _quizMode = canBuildQuiz(pool);
    _index = 0;
    _history.clear();
    _reviewIndex = null;
    _missed.clear();
    _spellNext = false;
    _spellTarget = null;
    _spellCtrl.clear();
    _spellError = null;
    _due.clear();
    _doneWords.clear();
    _order.clear();
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
    _history[_index] = _RoundSnapshot(
      word: word,
      question: question,
      selected: i,
      correct: correct,
      companion: _companions[word.key],
    );
    setState(() {
      _selected = i;
      _revealed = true;
      // 答错过的词答对后，先做一次「看释义拼写」才算完成
      _spellNext = correct && _missed.contains(word.key);
      if (!correct) _missed.add(word.key);
    });
    final next = await widget.state.grade(
      word,
      autoGrade(
        correct: correct,
        reps: reps,
        useFsrs: widget.state.settings.useFsrs,
      ),
    );
    if (correct) {
      _remember(word, next);
    } else {
      // 答错的词排到本轮末尾，其余单词过完后再考一次，直到答对
      _queue.add(word);
    }
  }

  Future<void> _rate(ReviewGrade grade) async {
    final word = _current;
    if (word == null) return;
    _history[_index] = _RoundSnapshot(
      word: word,
      grade: grade,
      companion: _companions[word.key],
    );
    setState(() => _revealed = true);
    final next = await widget.state.grade(word, grade);
    _remember(word, next);
    if (!mounted) return;
    _next();
  }

  /// 记录本词最终到期日，用于小结展示
  void _remember(Word word, ReviewState s) {
    _doneWords[word.key] = word;
    _due[word.key] = s.due;
    if (!_order.contains(word.key)) _order.add(word.key);
  }

  void _startSpelling() {
    final word = _current;
    if (word == null) return;
    _spellCtrl.clear();
    setState(() {
      _spellTarget = word;
      _spellError = null;
      _spellNext = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _spellFocus.requestFocus();
    });
  }

  void _submitSpelling() {
    final word = _spellTarget;
    if (word == null) return;
    final input = _spellCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _spellError = '先拼出单词再提交');
      return;
    }
    if (input.toLowerCase() != word.w.trim().toLowerCase()) {
      setState(() => _spellError = '拼写不对，看释义和发音再试一次');
      return;
    }
    setState(() {
      _spellTarget = null;
      _spellError = null;
      _spellCtrl.clear();
    });
    _next();
  }

  void _next() {
    setState(() {
      _index += 1;
      _prepare();
    });
  }

  void _skip() {
    final word = _current;
    if (word != null) {
      _history[_index] = _RoundSnapshot(
        word: word,
        question: _question,
        skipped: true,
        companion: _companions[word.key],
      );
    }
    setState(() {
      _index += 1;
      _prepare();
    });
  }

  /// 进入或继续向前回看；不改动当前题目的作答状态
  void _reviewPrevious() {
    final current = _reviewIndex;
    if (current != null) {
      if (current > 0 && _history.containsKey(current - 1)) {
        setState(() => _reviewIndex = current - 1);
      }
      return;
    }
    final target = _index - 1;
    if (target >= 0 && _history.containsKey(target)) {
      setState(() => _reviewIndex = target);
    }
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
        rows: [
          for (final key in _order)
            if (_doneWords[key] != null && _due[key] != null)
              _SummaryRow(word: _doneWords[key]!, due: _due[key]!),
        ],
        onBack: () => Navigator.of(context).pop(),
        onRestart: () => setState(_start),
      );
    }

    final reviewIndex = _reviewIndex;
    final snapshot = reviewIndex == null ? null : _history[reviewIndex];
    if (snapshot != null) {
      return _ReviewView(
        gradient: _gradient,
        snapshot: snapshot,
        index: reviewIndex!,
        total: _queue.length,
        canGoFurtherBack: reviewIndex > 0 && _history.containsKey(reviewIndex - 1),
        onPrevious: _reviewPrevious,
        onBackToCurrent: () => setState(() => _reviewIndex = null),
        onExit: () => Navigator.of(context).pop(),
        audio: _audio,
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
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    tooltip: '上一词',
                    onPressed: _spellTarget == null &&
                            _index > 0 &&
                            _history.containsKey(_index - 1)
                        ? _reviewPrevious
                        : null,
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
                  if (_spellTarget == null)
                    PopupMenuButton<String>(
                      tooltip: '更多',
                      icon: const Icon(Icons.more_horiz),
                      onSelected: (v) {
                        if (v == 'skip') _skip();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'skip', child: Text('跳过')),
                      ],
                    )
                  else
                    const SizedBox(width: 48),
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
                    if (_spellTarget != null)
                      _SpellingSection(
                        word: _spellTarget!,
                        controller: _spellCtrl,
                        focusNode: _spellFocus,
                        error: _spellError,
                        audio: _audio,
                        onSubmit: _submitSpelling,
                      )
                    else ...[
                      if (_companions[word.key] != null) ...[
                        _CompanionChip(name: _companions[word.key]!),
                        const SizedBox(height: 10),
                      ],
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
                      _SyllableLine(word: word.w),
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
                            onPressed: _spellNext ? _startSpelling : _next,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Text(_spellNext ? '去拼写' : '下一词'),
                          ),
                        ],
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

/// 小结行：完成后的单词与下次复习时间
class _SummaryRow {
  final Word word;
  final DateTime due;

  const _SummaryRow({required this.word, required this.due});
}

/// 一轮完成页：列出本轮单词与下次复习间隔，轻点可看释义
class _SummaryView extends StatefulWidget {
  final List<Color> gradient;
  final List<_SummaryRow> rows;
  final VoidCallback onBack;
  final VoidCallback onRestart;

  const _SummaryView({
    required this.gradient,
    required this.rows,
    required this.onBack,
    required this.onRestart,
  });

  @override
  State<_SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends State<_SummaryView> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        colors: widget.gradient,
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    tooltip: '返回',
                    onPressed: widget.onBack,
                  ),
                  Expanded(
                    child: Text(
                      '小结',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '轻点单词可查看释义',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  itemCount: widget.rows.length,
                  itemBuilder: (context, i) {
                    final row = widget.rows[i];
                    final key = row.word.key;
                    final open = _expanded.contains(key);
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() {
                        if (!_expanded.remove(key)) _expanded.add(key);
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    row.word.w,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.text,
                                    ),
                                  ),
                                ),
                                Text(
                                  dueLabel(row.due),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            if (open) ...[
                              const SizedBox(height: 6),
                              if (row.word.defs.isEmpty)
                                Text(
                                  '还没有释义',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              else
                                for (final d in row.word.defs)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      d.pos.isEmpty
                                          ? d.cn
                                          : '${d.pos}. ${d.cn}',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '本组 ${widget.rows.length} 个单词辨识完成',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryAction(
                            label: '再学一组',
                            onTap: widget.onRestart,
                          ),
                        ),
                        Expanded(
                          child: _SummaryAction(
                            label: '休息一下',
                            onTap: widget.onBack,
                          ),
                        ),
                      ],
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

/// 小结底部操作：文字 + 短下划线
class _SummaryAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SummaryAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 20,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 答错后的巩固：看释义 + 听发音，把单词拼出来才算完成
class _SpellingSection extends StatelessWidget {
  final Word word;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? error;
  final AudioService audio;
  final VoidCallback onSubmit;

  const _SpellingSection({
    required this.word,
    required this.controller,
    required this.focusNode,
    required this.error,
    required this.audio,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phonetic = word.uk.isNotEmpty ? word.uk : word.us;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '答错过 · 拼写巩固',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '根据释义和发音拼出这个单词',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(18),
          radius: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('释义', style: theme.textTheme.labelLarge),
                  ),
                  IconButton(
                    tooltip: '发音',
                    icon: const Icon(
                      Icons.volume_up_rounded,
                      color: AppColors.primary,
                    ),
                    onPressed: () => audio.play(word.w),
                  ),
                ],
              ),
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
              if (phonetic.isNotEmpty)
                Text(
                  '/$phonetic/',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: controller,
          focusNode: focusNode,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.none,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            hintText: '输入单词',
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.65),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.danger, fontSize: 13),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: onSubmit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: const Text('提交'),
        ),
        const SizedBox(height: 10),
        Text(
          '拼对后本词才会结束',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
      ],
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

/// 「关联复习」小标：由易混组带出的提前复习
class _CompanionChip extends StatelessWidget {
  final String name;

  const _CompanionChip({required this.name});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.compare_arrows_rounded,
              size: 14,
              color: AppColors.accent,
            ),
            const SizedBox(width: 5),
            Text(
              '关联复习 · $name',
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 音节参考：规则切分不可靠时不展示，避免误导
class _SyllableLine extends StatelessWidget {
  final String word;

  const _SyllableLine({required this.word});

  @override
  Widget build(BuildContext context) {
    final parts = splitSyllables(word);
    if (parts == null || parts.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        parts.join('·'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

/// 一回合的只读快照：作答结果已写入 SRS，回看时不再提供交互
class _RoundSnapshot {
  final Word word;
  final QuizQuestion? question;
  final int? selected;
  final bool? correct;
  final ReviewGrade? grade;
  final bool skipped;

  /// 该词由易混组关联插入时，记录组名
  final String? companion;

  const _RoundSnapshot({
    required this.word,
    this.question,
    this.selected,
    this.correct,
    this.grade,
    this.skipped = false,
    this.companion,
  });
}

/// 回看上一词：展示原题、原选项与原判定，不改变任何复习记录
class _ReviewView extends StatelessWidget {
  final List<Color> gradient;
  final _RoundSnapshot snapshot;
  final int index;
  final int total;
  final bool canGoFurtherBack;
  final VoidCallback onPrevious;
  final VoidCallback onBackToCurrent;
  final VoidCallback onExit;
  final AudioService audio;

  const _ReviewView({
    required this.gradient,
    required this.snapshot,
    required this.index,
    required this.total,
    required this.canGoFurtherBack,
    required this.onPrevious,
    required this.onBackToCurrent,
    required this.onExit,
    required this.audio,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final word = snapshot.word;
    final showOptions = snapshot.question != null && !snapshot.skipped;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        colors: gradient,
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onExit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    tooltip: '更早一个',
                    onPressed: canGoFurtherBack ? onPrevious : null,
                  ),
                  Expanded(
                    child: Text(
                      '回看 ${index + 1} / $total',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (index + 1) / total,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.45),
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                  children: [
                    _ReviewStatus(snapshot: snapshot),
                    if (snapshot.companion != null) ...[
                      const SizedBox(height: 10),
                      _CompanionChip(name: snapshot.companion!),
                    ],
                    const SizedBox(height: 18),
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
                    _SyllableLine(word: word.w),
                    const SizedBox(height: 10),
                    _PronunciationRow(word: word, audio: audio),
                    if (showOptions) ...[
                      const SizedBox(height: 24),
                      for (var i = 0; i < snapshot.question!.options.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _OptionCard(
                            option: snapshot.question!.options[i],
                            selected: snapshot.selected == i,
                            revealed: true,
                            onTap: () {},
                          ),
                        ),
                    ],
                    const SizedBox(height: 20),
                    if (word.defs.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          '该词还没有释义',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    else
                      _AnswerPanel(word: word),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: onBackToCurrent,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('回到当前'),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '回看不会改变复习记录',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
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

class _ReviewStatus extends StatelessWidget {
  final _RoundSnapshot snapshot;

  const _ReviewStatus({required this.snapshot});

  (IconData, String, Color) get _status {
    if (snapshot.skipped) {
      return (Icons.skip_next_outlined, '已跳过 · 未计分', AppColors.textSecondary);
    }
    if (snapshot.correct == true) {
      return (Icons.check_circle_outline, '答对', AppColors.primary);
    }
    if (snapshot.correct == false) {
      return (Icons.cancel_outlined, '答错', AppColors.danger);
    }
    return switch (snapshot.grade) {
      ReviewGrade.again => (Icons.refresh, '自评：重来', AppColors.danger),
      ReviewGrade.hard => (
          Icons.trending_up,
          '自评：难',
          const Color(0xFFB26A00),
        ),
      ReviewGrade.good => (Icons.check, '自评：一般', AppColors.primary),
      ReviewGrade.easy => (
          Icons.bolt,
          '自评：简单',
          const Color(0xFF2E7D32),
        ),
      null => (Icons.history, '回看', AppColors.textSecondary),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = _status;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
