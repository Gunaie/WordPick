import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'ui/affix_page.dart';
import 'ui/exam_sentence_page.dart';
import 'ui/library_page.dart';
import 'ui/profile_page.dart';
import 'ui/quiz_page.dart';
import 'ui/review_page.dart';
import 'ui/spelling_page.dart';

void main() {
  runApp(const EnglishStudyApp());
}

class EnglishStudyApp extends StatefulWidget {
  const EnglishStudyApp({super.key});

  @override
  State<EnglishStudyApp> createState() => _EnglishStudyAppState();
}

class _EnglishStudyAppState extends State<EnglishStudyApp> {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    _state.init();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '英语学习',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D6F),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F8F7),
      ),
      home: ListenableBuilder(
        listenable: _state,
        builder: (context, _) {
          if (!_state.isReady) {
            return _SplashScreen(error: _state.error);
          }
          return _Shell(state: _state);
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  final String? error;
  const _SplashScreen({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('正在加载词库…'),
            ] else ...[
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text('加载失败：$error', textAlign: TextAlign.center),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  final AppState state;
  const _Shell({required this.state});

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomeTab(state: widget.state),
      SpellingPage(state: widget.state),
      LibraryPage(state: widget.state),
      AffixPage(state: widget.state),
      ProfilePage(state: widget.state),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: '学习',
          ),
          NavigationDestination(
            icon: Icon(Icons.keyboard_outlined),
            selectedIcon: Icon(Icons.keyboard),
            label: '拼写',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '词库',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub),
            label: '词缀',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  final AppState state;
  const _HomeTab({required this.state});

  static const _filters = <String?, String>{
    null: '全部',
    'cet4': '四级',
    'cet6': '六级',
    'kaoyan': '考研',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = state.dueCount;
    final learned = state.learnedCount;
    final total = state.pool.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text('英语学习', style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
        )),
        const SizedBox(height: 4),
        Text(
          '离线词库 · 英美双发音 · 间隔重复',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),

        Wrap(
          spacing: 8,
          children: _filters.entries.map((e) {
            final selected = state.examTag == e.key;
            return ChoiceChip(
              label: Text(e.value),
              selected: selected,
              onSelected: (_) => state.setExamTag(e.key),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            _StatCard(label: '待复习', value: '$due', accent: true),
            const SizedBox(width: 12),
            _StatCard(label: '已学', value: '$learned'),
            const SizedBox(width: 12),
            _StatCard(label: '词库', value: '$total'),
          ],
        ),
        const SizedBox(height: 12),
        _SyncBar(state: state),
        const SizedBox(height: 20),

        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReviewPage(state: state),
              ),
            );
          },
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('开始学习', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => QuizPage(state: state)),
            );
          },
          icon: const Icon(Icons.quiz_outlined),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('考试练习 · ${state.quizQuestionCount} 题'),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ExamSentencePage(state: state)),
            );
          },
          icon: const Icon(Icons.format_quote_outlined),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('真题例句 · ${state.quizQuestionCount} 句'),
          ),
        ),
        const SizedBox(height: 28),

        Text('词库覆盖', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CoverageRow(tag: 'CET-4', count: state.repo.byTag('cet4').length),
                const SizedBox(height: 10),
                _CoverageRow(tag: 'CET-6', count: state.repo.byTag('cet6').length),
                const SizedBox(height: 10),
                _CoverageRow(tag: '考研', count: state.repo.byTag('kaoyan').length),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '提示：词库为离线内置，发音在线获取。多端同步功能将在后续版本提供。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SyncBar extends StatelessWidget {
  final AppState state;
  const _SyncBar({required this.state});

  String _statusText() {
    if (!state.syncEnabled) return '云同步未启用';
    if (state.syncing) return '正在同步…';
    if (state.syncError != null) return '同步失败';
    final at = state.lastSyncedAt;
    if (at == null) return '尚未同步';
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '已同步 · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasError = state.syncError != null;
    final color = hasError
        ? theme.colorScheme.error
        : state.syncing
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant;

    final icon = hasError
        ? Icons.cloud_off
        : state.syncing
            ? Icons.sync
            : Icons.cloud_done_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_statusText(),
                    style: theme.textTheme.bodySmall?.copyWith(color: color)),
                if (hasError)
                  Text(
                    state.syncError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
              ],
            ),
          ),
          if (state.syncEnabled)
            TextButton(
              onPressed: state.syncing ? null : state.syncNow,
              child: const Text('立即同步'),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  const _StatCard({required this.label, required this.value, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: accent
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: accent ? theme.colorScheme.onPrimaryContainer : null,
            )),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(
              color: accent ? theme.colorScheme.onPrimaryContainer : null,
            )),
          ],
        ),
      ),
    );
  }
}

class _CoverageRow extends StatelessWidget {
  final String tag;
  final int count;
  const _CoverageRow({required this.tag, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(tag, style: theme.textTheme.bodyMedium),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: (count / 4500).clamp(0.0, 1.0),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 12),
        Text('$count 词', style: theme.textTheme.bodySmall),
      ],
    );
  }
}
