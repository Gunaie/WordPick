/// 易混词组（纯 Dart，无 Flutter 依赖，便于单独测试）
///
/// 一个词组包含 2–4 个单词 key，一个词可以同时属于多个组。
/// 存储复用 `user_meta` 的 JSON（与自建词书同机制），不改表。
library;

class ConfusableGroup {
  final String id;
  final String name;

  /// 单词 key（小写），组内顺序不代表展示顺序，队列每轮随机
  final List<String> wordKeys;

  final DateTime createdAt;

  const ConfusableGroup({
    required this.id,
    required this.name,
    required this.wordKeys,
    required this.createdAt,
  });

  /// 名称为空时用词组内容兜底
  String get displayName =>
      name.trim().isNotEmpty ? name.trim() : wordKeys.join(' / ');

  ConfusableGroup copyWith({
    String? name,
    List<String>? wordKeys,
    DateTime? createdAt,
  }) =>
      ConfusableGroup(
        id: id,
        name: name ?? this.name,
        wordKeys: wordKeys ?? this.wordKeys,
        createdAt: createdAt ?? this.createdAt,
      );

  factory ConfusableGroup.fromJson(Map<String, dynamic> j) {
    final created =
        DateTime.tryParse('${j['created_at'] ?? ''}') ?? DateTime.now();
    final rawKeys = (j['word_keys'] as List?) ?? const [];
    final keys = <String>[];
    for (final raw in rawKeys.whereType<String>()) {
      final key = raw.trim().toLowerCase();
      if (key.isNotEmpty && !keys.contains(key)) keys.add(key);
    }
    final id = '${j['id'] ?? ''}';
    return ConfusableGroup(
      id: id.isEmpty ? 'group-${created.millisecondsSinceEpoch}' : id,
      name: '${j['name'] ?? ''}',
      wordKeys: keys,
      createdAt: created,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'word_keys': wordKeys,
        'created_at': createdAt.toIso8601String(),
      };
}
