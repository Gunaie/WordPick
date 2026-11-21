import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../domain/edit_distance.dart';
import '../domain/spelling_hints.dart';
import '../domain/word.dart';
import '../services/audio_service.dart';
import 'theme.dart';

/// 拼写练习：发音与释义同时展示，用户据此拼写单词
///
/// 判题使用编辑距离容错（差 1 个字母算笔误），并提供递进提示：
/// 首字母 → 音节（数量与分节）→ 词根拆解 → 四选一。
class SpellingPage extends StatefulWidget {
  final AppState state;

  const SpellingPage({super.key, required this.state});

  @override
  State<SpellingPage> createState() => _SpellingPageState();
}

class _SpellingPageState extends State<SpellingPage> {
  final AudioService _audio = AudioService();
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// 首字母 → 音节数 → 词根拆解
  static const int _maxHint = 3;

  late List<Word> _queue;
  int _index = 0;
  SpellVerdict? _verdict;
  String? _answer;
  int _hintLevel = 0; // 0 = 无提示
  bool _hasSource = true;

  /// 第四级提示：四选一选项，null 表示尚未展开
  List<String>? _choices;
  final Set<String> _wrongChoices = {};

  @override
  void initState() {
    super.initState();
    _buildQueue();
  }

  @override
  void dispose() {
    _audio.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _buildQueue() {
    final pool = widget.state.pool
        .where((w) => w.w.length >= 3 && w.defs.isNotEmpty)
        .toList();
    _hasSource = pool.isNotEmpty;
    pool.shuffle(Random());
    _queue = pool.take(widget.state.settings.spellingWords).toList();
    _index = 0;
    _resetRound();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_queue.isNotEmpty) _audio.play(_queue.first.w);
      _focus.requestFocus();
    });
  }

  void _resetRound() {
    _verdict = null;
    _answer = null;
    _hintLevel = 0;
    _choices = null;
    _wrongChoices.clear();
    _input.clear();
  }

  Word? get _current => _index < _queue.length ? _queue[_index] : null;

  void _advanceHint() {
    if (_verdict != null) return;
    if (_hintLevel < _maxHint) {
      setState(() => _hintLevel++);
      return;
    }
    if (_choices != null) return;

    final w = _current;
    if (w == null) return;
    final choices = buildSpellingChoices(w, widget.state.pool);
    if (choices == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('词池不足 4 个不同拼写，无法生成选项')),
      );
      return;
    }
    setState(() => _choices = choices);
  }

  /// 四选一作答：选对即填充并判题，选错则划掉该选项
  void _choose(String value) {
    final w = _current;
    if (w == null || _verdict != null) return;
    if (value.toLowerCase() != w.w.toLowerCase()) {
      setState(() => _wrongChoices.add(value));
      return;
    }
    _input.text = w.w;
    _check();
  }

  void _check() {
    final w = _current;
    if (w == null) return;
    final verdict = SpellVerdict.of(_input.text, w.w);
    setState(() {
      _verdict = verdict;
      _answer = w.w;
    });
  }

  Future<void> _next() async {
    setState(() {
      _index += 1;
      _resetRound();
    });
    final w = _current;
    if (w != null) {
      await _audio.play(w.w);
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final word = _current;

    if (word == null) {
      if (!_hasSource) {
        return _frame(
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                '还没有可练习的单词。\n先去「词单」添加几个词吧。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }
      return _frame(
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.done_all, size: 56, color: AppColors.primary),
              const SizedBox(height: 12),
              const Text('本轮拼写结束'),
              const SizedBox(height: 20),
              FilledButton(onPressed: _buildQueue, child: const Text('再来一轮')),
            ],
          ),
        ),
      );
    }

    final graded = _verdict != null;

    return _frame(
      ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Row(
            children: [
              const Spacer(),
              Text('${_index + 1} / ${_queue.length}',
                  style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (_index + (graded ? 1 : 0)) / _queue.length,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
            backgroundColor: Colors.white.withValues(alpha: 0.45),
            color: AppColors.primary,
          ),
          const SizedBox(height: 20),

          _SpellPrompt(word: word, audio: _audio),
          const SizedBox(height: 16),

          _buildHintOrResult(word, theme, graded),
          if (_choices != null && !graded) ...[
            const SizedBox(height: 12),
            _ChoiceHint(
              choices: _choices!,
              wrong: _wrongChoices,
              onPick: _choose,
            ),
          ],

          const SizedBox(height: 20),
          TextField(
            controller: _input,
            focusNode: _focus,
            enabled: !graded,
            autofocus: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => graded ? _next() : _check(),
            decoration: InputDecoration(
              hintText: '输入对应的英文单词',
              border: const OutlineInputBorder(),
              suffixIcon: graded || (_hintLevel >= _maxHint && _choices != null)
                  ? null
                  : IconButton(
                      tooltip: '提示',
                      icon: const Icon(Icons.lightbulb_outline),
                      onPressed: _advanceHint,
                    ),
            ),
          ),
          const SizedBox(height: 16),
          if (!graded)
            FilledButton(
              onPressed: _check,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('检查'),
              ),
            )
          else
            FilledButton(
              onPressed: _next,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('下一个'),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            '判定规则：完全一致为正确；仅差 1 个字母视为笔误（半对）。'
            '可逐级提示：首字母 → 音节 → 词根拆解 → 四选一。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _frame(Widget child) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        colors: kGradients[1],
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Text(
                      '拼写练习',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHintOrResult(Word word, ThemeData theme, bool graded) {
    final phonetic = word.uk.isEmpty ? word.us : word.uk;

    if (graded) {
      final breakdown = affixBreakdownHint(
        word.w,
        widget.state.affixes.all,
        isKnownWord: (k) => widget.state.findWord(k) != null,
      );
      return _HintCard(
        definition: word.primaryDefinition,
        phonetic: phonetic,
        answer: _answer ?? word.w,
        verdict: _verdict!,
        input: _input.text,
        breakdown: breakdown,
        onPlay: () => _audio.play(word.w),
      );
    }

    if (_hintLevel == 0) return const SizedBox.shrink();

    final breakdown = _hintLevel >= 3
        ? affixBreakdownHint(
            word.w,
            widget.state.affixes.all,
            isKnownWord: (k) => widget.state.findWord(k) != null,
          )
        : '';
    final parts = _hintLevel >= 2 ? splitSyllables(word.w) : null;
    return _MeaningHintCard(
      firstLetter: firstLetterHint(word.w),
      syllables: _hintLevel >= 2 ? syllableCount(word.w) : 0,
      syllableSplit:
          parts != null && parts.length > 1 ? parts.join('·') : '',
      breakdown: breakdown,
    );
  }
}

/// 题面：发音按钮 + 释义（同时给出）
class _SpellPrompt extends StatelessWidget {
  final Word word;
  final AudioService audio;

  const _SpellPrompt({required this.word, required this.audio});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defs = word.defs.take(3).toList();

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: '听发音',
                  iconSize: 28,
                  onPressed: () => audio.play(word.w),
                  icon: const Icon(Icons.volume_up_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '听发音，按释义拼写',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              '释义',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            for (final d in defs)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  d.pos.isEmpty ? d.cn : '${d.pos}. ${d.cn}',
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 判定结果卡片
class _HintCard extends StatelessWidget {
  final String definition;
  final String phonetic;
  final String? answer;
  final SpellVerdict? verdict;
  final String input;
  final String breakdown;
  final VoidCallback? onPlay;

  const _HintCard({
    this.definition = '',
    this.phonetic = '',
    this.answer,
    required this.verdict,
    this.input = '',
    this.breakdown = '',
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, text) = switch (verdict) {
      SpellVerdict.correct =>
        (Icons.check_circle, const Color(0xFF2E7D32), '正确'),
      SpellVerdict.nearMiss =>
        (Icons.info, const Color(0xFFB26A00), '拼写有笔误'),
      SpellVerdict.wrong => (Icons.cancel, theme.colorScheme.error, '拼写错误'),
      null => (Icons.lightbulb_outline, theme.colorScheme.primary, '提示'),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(text,
                  style:
                      TextStyle(color: color, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          if (definition.isNotEmpty)
            Text(definition, style: theme.textTheme.bodyMedium),
          if (phonetic.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '/$phonetic/',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (breakdown.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '词根拆解：$breakdown',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (answer != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '正确拼写：$answer',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                if (onPlay != null)
                  IconButton(
                    tooltip: '听发音',
                    icon: const Icon(Icons.volume_up_outlined),
                    onPressed: onPlay,
                  ),
              ],
            ),
            if (input.trim().isNotEmpty && input.trim() != answer)
              Text(
                '你的输入：$input',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 四选一提示卡片：选出正确拼写，选错的选项划掉
class _ChoiceHint extends StatelessWidget {
  final List<String> choices;
  final Set<String> wrong;
  final ValueChanged<String> onPick;

  const _ChoiceHint({
    required this.choices,
    required this.wrong,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.quiz_outlined, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                '四选一提示',
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '选出正确的拼写，选错的选项会被划掉',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in choices)
                OutlinedButton(
                  onPressed: wrong.contains(c) ? null : () => onPick(c),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    c,
                    style: TextStyle(
                      letterSpacing: 0.5,
                      decoration: wrong.contains(c)
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 分级提示卡片（判定前展示，不泄露完整答案）
class _MeaningHintCard extends StatelessWidget {
  final String firstLetter;
  final int syllables; // 0 表示未展示
  final String syllableSplit; // 可可靠切分时展示，如 re·sil·ient
  final String breakdown;

  const _MeaningHintCard({
    required this.firstLetter,
    required this.syllables,
    required this.syllableSplit,
    required this.breakdown,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 18, color: color),
              const SizedBox(width: 6),
              Text('提示',
                  style:
                      TextStyle(color: color, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            firstLetter,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          if (syllables > 0) ...[
            const SizedBox(height: 8),
            Text(
              syllableSplit.isEmpty
                  ? '约 $syllables 个音节'
                  : '音节：$syllableSplit（$syllables）',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (breakdown.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('词根拆解：$breakdown',
                style: theme.textTheme.bodyMedium),
          ],
          if (breakdown.isEmpty && syllables >= 3) ...[
            const SizedBox(height: 4),
            Text('（该词暂无词根拆解）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ],
        ],
      ),
    );
  }
}
