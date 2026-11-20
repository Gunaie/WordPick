/// 笔记记录（跨端同步用）
///
/// 说明：
///   * id 使用 UUID 字符串，由客户端生成，避免多端自增冲突
///   * deleted 为软删除标记，保证"删除"也能同步到其他设备
library;

class NoteRecord {
  final String id;

  /// 关联单词（可选，空串表示随手记）
  final String wordKey;

  /// 标题（可选，空串时列表用正文首行）
  final String title;
  final String content;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  const NoteRecord({
    required this.id,
    required this.wordKey,
    this.title = '',
    required this.content,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  NoteRecord copyWith({
    String? title,
    String? content,
    List<String>? tags,
    DateTime? updatedAt,
    bool? deleted,
  }) =>
      NoteRecord(
        id: id,
        wordKey: wordKey,
        title: title ?? this.title,
        content: content ?? this.content,
        tags: tags ?? this.tags,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'word_key': wordKey,
        'title': title,
        'content': content,
        'tags': tags,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted': deleted,
      };

  factory NoteRecord.fromJson(Map<String, dynamic> j) => NoteRecord(
        id: (j['id'] ?? '') as String,
        wordKey: (j['word_key'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        content: (j['content'] ?? '') as String,
        tags: ((j['tags'] ?? const []) as List)
            .whereType<String>()
            .where((e) => e.trim().isNotEmpty)
            .toList(),
        createdAt:
            DateTime.tryParse((j['created_at'] ?? '') as String) ??
                DateTime.now(),
        updatedAt:
            DateTime.tryParse((j['updated_at'] ?? '') as String) ??
                DateTime.now(),
        deleted: (j['deleted'] ?? false) as bool,
      );
}
