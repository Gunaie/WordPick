import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../domain/edit_distance.dart';
import '../domain/spelling_hints.dart';
import '../domain/word.dart';
import '../services/audio_service.dart';

/// 拼写练习模式
enum SpellMode {
  /// 听音拼写：放音 → 敲字母
  listening,

  /// 看义拼写：给中文释义 → 写英文（带分级提示）
  meaning,
}

extension SpellModeLabel on SpellMode {
  String get label => switch (this) {
        SpellMode.listening => '听音拼写',
        SpellMode.meaning => '看义拼写',
      };
}

/// 拼写练习（听音 / 看义 双模式，共用队列、判定与结果卡片）
class SpellingPage extends StatefulWidget {
  final AppState state;

  /// 若提供，覆盖 [state.pool] 作为练习词池（用于错题专攻等场景）
  final List<Word>? words;

  /// 标题覆盖（如"错题专攻"）；为空则显示当前模式名
  final String? title;

  const SpellingPage({super.key, required this.state, this.words, this.title});

  @override
  State<SpellingPage> createState() => _SpellingPageState();
}

class _SpellingPageState extends State<SpellingPage> {
  final AudioService _audio = AudioService();
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  SpellMode _mode = SpellMode.listening;
  late List<Word> _queue;
  int _index = 0;
  SpellVerdict? _verdict;
  String? _answer;
  int _hintLevel = 0; // 0 = 无提示
  bool _hasSource = true; // 当前模式下是否有可练习的词

  /// 看义拼写有 3 级提示，听音拼写仅 1 级（直接给释义）
  int get _maxHint => _mode == SpellMode.meaning ? 3 : 1;

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
    final source = widget.words ?? widget.state.pool;
    final pool = source.where((w) {
      if (w.w.length < 3) return false;
      if (_mode == SpellMode.meaning && w.defs.isEmpty) return false;
      return true;
    }).toList();
    _hasSource = pool.isNotEmpty;
    pool.shuffle(Random());
    _queue = pool.take(10).toList();
    _index = 0;
    _resetRound();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mode == SpellMode.listening && _queue.isNotEmpty) {
        _audio.play(_queue.first.w);
      }
      _focus.requestFocus();
    });
  }

  void _resetRound() {
    _verdict = null;
    _answer = null;
    _hintLevel = 0;
    _input.clear();
  }

  void _switchMode(SpellMode m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _buildQueue();
    });
  }

  Word? get _current => _index < _queue.length ? _queue[_index] : null;

  void _advanceHint() {
    if (_verdict != null) return;
    setState(() {
      if (_hintLevel < _maxHint) _hintLevel++;
    });
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
      if (_mode == SpellMode.listening) await _audio.play(w.w);
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final word = _current;

    if (word == null) {
      if (!_hasSource) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              '没有可练习的单词',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.done_all, size: 56),
            const SizedBox(height: 12),
            const Text('本轮拼写结束'),
            const SizedBox(height: 20),
            FilledButton(onPressed: _buildQueue, child: const Text('再来一轮')),
          ],
        ),
      );
    }

    final graded = _verdict != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Row(
          children: [
            Text(widget.title ?? _mode.label, style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            )),
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
        ),
        const SizedBox(height: 16),

        SegmentedButton<SpellMode>(
          segments: const [
            ButtonSegment(
              value: SpellMode.listening,
              icon: Icon(Icons.hearing_outlined),
              label: Text('听音拼写'),
            ),
            ButtonSegment(
              value: SpellMode.meaning,
              icon: Icon(Icons.translate_outlined),
              label: Text('看义拼写'),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => _switchMode(s.first),
        ),
        const SizedBox(height: 28),

        _mode == SpellMode.listening
            ? _buildListeningPrompt(word, theme)
            : _buildMeaningPrompt(word, theme),
        const SizedBox(height: 24),

        _buildHintOrResult(word, theme, graded),

        const SizedBox(height: 20),
        TextField(
          controller: _input,
          focusNode: _focus,
          enabled: !graded,
          autofocus: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => graded ? _next() : _check(),
          decoration: InputDecoration(
            hintText: _mode == SpellMode.listening
                ? '输入你听到的单词'
                : '输入对应的英文单词',
            border: const OutlineInputBorder(),
            suffixIcon: graded || _hintLevel >= _maxHint
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
          _mode == SpellMode.listening
              ? '判定规则：完全一致为正确；仅差 1 个字母视为笔误（半对）。'
              : '判定规则：完全一致为正确；仅差 1 个字母视为笔误（半对）。可逐级提示：首字母 → 音节数 → 词根拆解。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildListeningPrompt(Word word, ThemeData theme) {
    return Center(
      child: Column(
        children: [
          IconButton.filledTonal(
            iconSize: 40,
            padding: const EdgeInsets.all(20),
            onPressed: () => _audio.play(word.w),
            icon: const Icon(Icons.volume_up_rounded),
          ),
          const SizedBox(height: 8),
          Text(
            '点击播放${word.tags.isEmpty ? '' : ' · ${_tagLabel(word.tags.first)}'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeaningPrompt(Word word, ThemeData theme) {
    final defs = word.defs.take(3).toList();
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.g_translate,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('给出释义，写出英文',
                    style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                if (word.tags.isNotEmpty)
                  Text(_tagLabel(word.tags.first),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            for (final d in defs)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  d.pos.isEmpty ? d.cn : '${d.pos}. ${d.cn}',
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.4),
                ),
              ),
            if (defs.isEmpty)
              Text('（该词暂无释义）', style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildHintOrResult(Word word, ThemeData theme, bool graded) {
    final phonetic = word.uk.isEmpty ? word.us : word.uk;

    if (graded) {
      final breakdown = _mode == SpellMode.meaning
          ? affixBreakdownHint(
              word.w,
              widget.state.affixes.all,
              isKnownWord: (k) => widget.state.findWord(k) != null,
            )
          : '';
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

    if (_mode == SpellMode.listening) {
      return _HintCard(
        definition: word.primaryDefinition,
        phonetic: phonetic,
        answer: null,
        verdict: null,
        input: '',
      );
    }

    // 看义拼写：分级提示
    final first = firstLetterHint(word.w);
    final syllables = _hintLevel >= 2 ? syllableCount(word.w) : 0;
    final breakdown = _hintLevel >= 3
        ? affixBreakdownHint(
            word.w,
            widget.state.affixes.all,
            isKnownWord: (k) => widget.state.findWord(k) != null,
          )
        : '';
    return _MeaningHintCard(
      firstLetter: first,
      syllables: syllables,
      breakdown: breakdown,
    );
  }
}

String _tagLabel(String tag) => switch (tag) {
      'cet4' => '四级',
      'cet6' => '六级',
      'kaoyan' => '考研',
      _ => tag,
    };

class _HintCard extends StatelessWidget {
  final String definition;
  final String phonetic;
  final String? answer;
  final SpellVerdict? verdict;
  final String input;
  final String breakdown;
  final VoidCallback? onPlay;

  const _HintCard({
    required this.definition,
    required this.phonetic,
    required this.answer,
    required this.verdict,
    required this.input,
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

/// 看义拼写的分级提示卡片（判定前展示，不泄露完整答案）
class _MeaningHintCard extends StatelessWidget {
  final String firstLetter;
  final int syllables; // 0 表示未展示
  final String breakdown;

  const _MeaningHintCard({
    required this.firstLetter,
    required this.syllables,
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
            Text('约 $syllables 个音节',
                style: theme.textTheme.bodyMedium),
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
