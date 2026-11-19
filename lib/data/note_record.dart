/// 笔记记录（跨端同步用）
///
/// 说明：
///   * id 使用 UUID 字符串，由客户端生成，避免多端自增冲突
///   * deleted 为软删除标记，保证"删除"也能同步到其他设备
library;

class NoteRecord {
  final String id;
  final String wordKey;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  const NoteRecord({
    required this.id,
    required this.wordKey,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  NoteRecord copyWith({
    String? content,
    DateTime? updatedAt,
    bool? deleted,
  }) =>
      NoteRecord(
        id: id,
        wordKey: wordKey,
        content: content ?? this.content,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'word_key': wordKey,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted': deleted,
      };

  factory NoteRecord.fromJson(Map<String, dynamic> j) => NoteRecord(
        id: (j['id'] ?? '') as String,
        wordKey: (j['word_key'] ?? '') as String,
        content: (j['content'] ?? '') as String,
        createdAt:
            DateTime.tryParse((j['created_at'] ?? '') as String) ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse((j['updated_at'] ?? '') as String) ?? DateTime.now(),
        deleted: (j['deleted'] ?? false) as bool,
      );
}
