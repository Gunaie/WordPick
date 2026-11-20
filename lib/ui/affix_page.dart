import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../domain/affix.dart';
import 'theme.dart';

/// 词根词缀专题：查词缀 + 拆解自建词
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

  void _searchWord(String word) {
    _input.text = word;
    setState(() => _query = word);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = widget.state.affixes;
    final query = _query.trim();
    final list = repo.search(_query, type: _filter);
    final matches = query.isEmpty
        ? const <AffixMatch>[]
        : analyzeWord(
            query,
            repo.all,
            isKnownWord: (k) => widget.state.findWord(k) != null,
          );

    // 自建词里能拆出词缀的词，最多展示 8 个
    final suggested = <String>[];
    if (query.isEmpty) {
      for (final entry in widget.state.customWords) {
        final w = entry.word.w;
        if (suggested.length >= 8) break;
        final m = analyzeWord(
          w,
          repo.all,
          isKnownWord: (k) => widget.state.findWord(k) != null,
        );
        if (m.isNotEmpty) suggested.add(w);
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        colors: kGradients[1],
        child: SafeArea(
          child: Column(
            children: [
              PageHeader(
                title: '词根词缀',
                subtitle: '前缀 ${repo.countOf(AffixType.prefix)} · '
                    '词根 ${repo.countOf(AffixType.root)} · '
                    '后缀 ${repo.countOf(AffixType.suffix)}',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
                child: TextField(
                  controller: _input,
                  onChanged: (v) => setState(() => _query = v),
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: '输入单词拆解，或搜索词缀',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.55),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _input.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
                  children: [
                    if (query.isNotEmpty)
                      matches.isEmpty
                          ? _HintCard(
                              icon: Icons.search_off_rounded,
                              title: '没拆出词缀',
                              text: '「$query」没有匹配到前缀 / 词根 / 后缀。\n'
                                  '换一个词，或直接搜索词缀含义。',
                            )
                          : _AnalysisCard(word: query, matches: matches),
                    if (query.isEmpty) ...[
                      Text('自建词拆解', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      if (suggested.isEmpty)
                        _HintCard(
                          icon: Icons.hub_outlined,
                          title: '还没有可拆解的词',
                          text: widget.state.customWords.isEmpty
                              ? '先在「词单」里添加单词，\n这里会自动拆解它们的词根词缀。'
                              : '当前自建词都拆不出常用词缀，\n可在下方直接搜索词缀。',
                        )
                      else
                        GlassCard(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final w in suggested)
                                ActionChip(
                                  label: Text(w),
                                  onPressed: () => _searchWord(w),
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.7),
                                  side: BorderSide(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.25),
                                  ),
                                  labelStyle:
                                      const TextStyle(color: AppColors.text),
                                ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text('词缀表', style: theme.textTheme.titleSmall),
                        const Spacer(),
                        if (query.isNotEmpty)
                          Text(
                            '${list.length} 条',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
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
                              showCheckmark: false,
                              selectedColor: AppColors.primary,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.55),
                              labelStyle: TextStyle(
                                color: _filter == f
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontWeight: _filter == f
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              side: BorderSide.none,
                              onSelected: (_) => setState(() => _filter = f),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (list.isEmpty)
                      _HintCard(
                        icon: Icons.search_off_rounded,
                        title: '没有匹配的词缀',
                        text: '试试只输入词缀的一部分，\n例如「pre」「dict」「tion」。',
                      )
                    else
                      for (final a in list) ...[
                        _AffixTile(affix: a),
                        const SizedBox(height: 10),
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

class _HintCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _HintCard({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        children: [
          Icon(icon, size: 30, color: AppColors.textMuted),
          const SizedBox(height: 10),
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
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
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                word,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '词缀拆解',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final m in matches)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      m.affix.type.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    m.segment,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m.affix.meaning,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
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
    return Material(
      color: Colors.white.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                affix.type.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              affix.form,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ),
        subtitle: Text(
          affix.meaning,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (affix.examples.isEmpty)
            Text(
              '暂无示例词',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textMuted,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: affix.examples
                  .map((e) => Chip(
                        label: Text(e),
                        labelStyle: theme.textTheme.labelSmall
                            ?.copyWith(color: AppColors.text),
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.6),
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}
