import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../domain/word.dart';
import 'quiz_widgets.dart';

/// 考试练习：从带题目的词条中随机抽 10 题
class QuizPage extends StatefulWidget {
  final AppState state;
  const QuizPage({super.key, required this.state});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  static const _perRound = 10;

  final List<({Word word, QuizItem item})> _list = [];
  int _index = 0;
  int _correct = 0;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    _buildRound();
  }

  void _buildRound() {
    final pool = <({Word word, QuizItem item})>[];
    for (final w in widget.state.pool) {
      for (final q in w.quiz) {
        pool.add((word: w, item: q));
      }
    }
    pool.shuffle();
    _list
      ..clear()
      ..addAll(pool.take(_perRound));
    _index = 0;
    _correct = 0;
    _answered = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_list.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('考试练习')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('当前筛选下没有可用题目'),
          ),
        ),
      );
    }

    if (_index >= _list.length) {
      return Scaffold(
        appBar: AppBar(title: const Text('考试练习')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.emoji_events_outlined, size: 60),
              const SizedBox(height: 14),
              Text(
                '本轮 $_correct / ${_list.length}',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => setState(_buildRound),
                child: const Text('再来一轮'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    final current = _list[_index];

    return Scaffold(
      appBar: AppBar(
        title: Text('考试练习 ${_index + 1}/${_list.length}'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_index + 1) / _list.length,
            minHeight: 3,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              children: [
                QuizCard(
                  key: ValueKey('${current.item.question}-$_index'),
                  item: current.item,
                  onAnswered: (correct) {
                    setState(() {
                      _answered = true;
                      if (correct) _correct++;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  '对应单词：${current.word.w}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(
                onPressed: _answered
                    ? () => setState(() {
                          _index++;
                          _answered = false;
                        })
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_index + 1 == _list.length ? '查看结果' : '下一题'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
