import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../domain/affix.dart';

/// 词根词缀专题：查词缀 + 拆解单词
class AffixPage extends StatefulWidget {
  final AppState state;
  const AffixPage({super.key, required this.state});

  @override
  State<AffixPage> createState() => _AffixPageState();
}

class _AffixPageState extends State<AffixPage> {
  final TextEditingController _input = TextEditingController();
  AffixType? _filter;
  String _query = '';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = widget.state.affixes;
    final list = repo.search(_query, type: _filter);
    final matches = _query.trim().isEmpty
        ? const <AffixMatch>[]
        : analyzeWord(
            _query.trim(),
            repo.all,
            isKnownWord: (k) => widget.state.repo.byKey(k) != null,
          );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '词根词缀',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '前缀 ${repo.countOf(AffixType.prefix)} · '
                '词根 ${repo.countOf(AffixType.root)} · '
                '后缀 ${repo.countOf(AffixType.suffix)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _input,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: '输入单词拆解，或搜索词缀',
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
                            _input.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
        if (matches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: _AnalysisCard(word: _query.trim(), matches: matches),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (final f in <AffixType?>[
                null,
                AffixType.prefix,
                AffixType.root,
                AffixType.suffix,
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f == null ? '全部' : f.label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    '没有匹配的词缀',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _AffixTile(affix: list[i]),
                ),
        ),
      ],
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  final String word;
  final List<AffixMatch> matches;

  const _AnalysisCard({required this.word, required this.matches});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '拆解：$word',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          for (final m in matches)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${m.affix.type.label} ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer
                            .withValues(alpha: 0.7),
                      ),
                    ),
                    TextSpan(
                      text: '${m.segment}  ',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    TextSpan(
                      text: m.affix.meaning,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AffixTile extends StatelessWidget {
  final Affix affix;
  const _AffixTile({required this.affix});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(affix.type.label, style: theme.textTheme.labelSmall),
          ),
          const SizedBox(width: 8),
          Text(
            affix.form,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ],
      ),
      subtitle: Text(affix.meaning),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: affix.examples
              .map((e) => Chip(
                    label: Text(e),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ))
              .toList(),
        ),
      ],
    );
  }
}
