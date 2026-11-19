import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../domain/word.dart';
import '../services/audio_service.dart';

/// 词库浏览：搜索 + 考试筛选 + 详情
class LibraryPage extends StatefulWidget {
  final AppState state;
  const LibraryPage({super.key, required this.state});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final TextEditingController _search = TextEditingController();
  final AudioService _audio = AudioService();
  List<Word> _results = const [];
  bool _searched = false;

  @override
  void dispose() {
    _audio.dispose();
    _search.dispose();
    super.dispose();
  }

  void _runSearch(String q) {
    setState(() {
      _searched = q.trim().isNotEmpty;
      _results = q.trim().isEmpty ? const [] : widget.state.repo.search(q, limit: 80);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _searched ? _results : widget.state.pool.take(60).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('词库', style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              )),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                onChanged: _runSearch,
                decoration: InputDecoration(
                  hintText: '搜索单词',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: _searched
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            _runSearch('');
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searched ? '搜索结果 ${_results.length}' : '共 ${widget.state.pool.length} 词（按字母序）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final w = list[i];
              return ListTile(
                title: Text(w.w, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  w.primaryDefinition,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.volume_up_outlined),
                  onPressed: () => _audio.play(w.w),
                ),
                onTap: () => _showDetail(w),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDetail(Word word) {
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
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (word.uk.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => _audio.play(word.w, uk: true),
                        icon: const Icon(Icons.volume_up, size: 18),
                        label: Text('英 /${word.uk}/'),
                      ),
                    if (word.us.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => _audio.play(word.w, uk: false),
                        icon: const Icon(Icons.volume_up, size: 18),
                        label: Text('美 /${word.us}/'),
                      ),
                  ],
                ),
                const Divider(),
                for (final d in word.defs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      d.pos.isEmpty ? d.cn : '[${d.pos}] ${d.cn}',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                if (word.ex.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('例句', style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  )),
                  const SizedBox(height: 6),
                  for (final e in word.ex)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.en),
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
                if (word.rel.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('同根词', style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  )),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: word.rel
                        .map((r) => Chip(label: Text('${r.w} ${r.cn}'.trim())))
                        .toList(),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
